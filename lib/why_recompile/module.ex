defmodule WhyRecompile.Module do
  @moduledoc """
  Represents a module. A module belongs to a source file
  """

  @type t :: %__MODULE__{
          module: atom(),
          source_paths: [WhyRecompile.file_path()]
        }

  defstruct [
    :module,
    :source_paths
  ]
end
