defmodule WhyRecompile.Module do
  @moduledoc """
  Represents a module. A module belongs to a source file
  """

  import Mix.Compilers.Elixir,
    only: [module: 1]

  alias Mix.Compilers.Elixir, as: Compilers

  @type t :: %__MODULE__{
          module: atom(),
          source_paths: [WhyRecompile.file_path()]
        }

  defstruct [
    :module,
    :source_paths
  ]

  @spec from_record(record :: Compilers.module()) :: %__MODULE__{}
  def from_record(record) do
    module(module: module, sources: sources) = record

    %__MODULE__{
      module: module,
      source_paths: sources
    }
  end
end
