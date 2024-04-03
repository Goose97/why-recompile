defmodule WhyRecompile.SourceFile do
  @moduledoc """
  Represents a source file. A source file consists of multiple modules
  """

  import Mix.Compilers.Elixir,
    only: [source: 1]

  alias Mix.Compilers.Elixir, as: Compilers
  alias WhyRecompile.Manifest

  @type t :: %__MODULE__{
          path: WhyRecompile.file_path(),
          modules: [atom()],
          compile_references: [atom()],
          export_references: [atom()],
          runtime_references: [atom()]
        }

  defstruct [
    :path,
    :modules,
    # Compile references modules of this file
    :compile_references,
    # Export references modules of this file
    :export_references,
    # Runtime references modules of this file
    :runtime_references
  ]

  @spec from_record(source :: Compilers.source()) :: %__MODULE__{}
  def from_record(source) do
    source(
      source: path,
      modules: modules,
      compile_references: compile_references,
      export_references: export_references,
      runtime_references: runtime_references
    ) = source

    %__MODULE__{
      path: path,
      modules: modules,
      compile_references: compile_references,
      export_references: export_references,
      runtime_references: runtime_references
    }
  end

  def build_lookup_table(manifest) do
    table_ref = :ets.new(Module.concat(__MODULE__, LookupTable), [:set])
    {_modules, sources} = Manifest.read_manifest(manifest)

    Enum.each(sources, fn source ->
      struct = from_record(source)
      :ets.insert(table_ref, {struct.path, struct})
    end)

    table_ref
  end

  def lookup!(table, path) do
    [{_, source}] = :ets.lookup(table, path)
    source
  end

  def delete_lookup_table(table), do: :ets.delete(table)
end
