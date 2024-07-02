defmodule WhyRecompile.SourceFile do
  @moduledoc """
  Represents a source file. A source file consists of multiple modules
  """

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
end
