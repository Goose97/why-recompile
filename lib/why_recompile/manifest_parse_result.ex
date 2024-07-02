defmodule WhyRecompile.ManifestParseResult do
  defstruct [
    :graph,
    :modules_map,
    :source_files_map
  ]
end
