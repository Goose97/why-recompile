defmodule WhyRecompile do
  @moduledoc """
  API to interact with the dependency graph
  """

  @type manifest_path :: binary()
  @type file_path :: binary()

  @spec parse_manifest() :: WhyRecompile.ManifestParseResult.t()
  def parse_manifest() do
    # Add the app code path to the code path so modules can be loaded
    app_code_path = Mix.Project.app_path() |> Path.join("ebin")
    :code.add_path(String.to_charlist(app_code_path))

    %{graph: graph, modules_map: modules_map, source_files_map: source_files_map} =
      __MODULE__.Graph.build(manifest_path())

    graph_with_recompile_dependencies =
      for vertex <- __MODULE__.Graph.summarize(graph) do
        dependencies =
          __MODULE__.Dependency.recompile_dependencies(graph, vertex.id)
          |> Enum.flat_map(fn {reason, dependents} ->
            for {file, chain} <- dependents do
              %{
                path: file,
                reason: reason,
                dependency_chain: format_dependency_chain(chain, vertex.id)
              }
            end
          end)
          |> Enum.sort_by(& &1.path)

        Map.put(vertex, :recompile_dependencies, dependencies)
      end

    %__MODULE__.ManifestParseResult{
      graph: graph_with_recompile_dependencies,
      modules_map: modules_map,
      source_files_map: source_files_map
    }
  end

  # From this:
  # chain = [
  #   [:compile, "lib/fixtures/D1.ex"],
  #   [:compile, "lib/fixtures/D2.ex"]
  # ]
  # recompile_source = "lib/fixtures/D3.ex"
  #
  # To this:
  # chain = [
  #   [:compile, "lib/fixtures/D1.ex", "lib/fixtures/D2.ex"],
  #   [:compile, "lib/fixtures/D2.ex",  "lib/fixtures/D3.ex"]
  # ]
  defp format_dependency_chain([], _), do: []

  defp format_dependency_chain(chain, recompile_source) do
    Enum.zip(chain, tl(chain) ++ [{nil, recompile_source}])
    |> Enum.map(fn {item, {_, next_file}} ->
      Tuple.append(item, next_file)
    end)
  end

  # Expand the dependency path to a detailed explanation
  def get_detailed_explanation(
        %WhyRecompile.ManifestParseResult{} = parsed_manifest,
        dependency_chain
      ),
      do: get_detailed_explanation(parsed_manifest, dependency_chain, [])

  defp get_detailed_explanation(_parsed_manifest, [], result), do: result

  defp get_detailed_explanation(parsed_manifest, [{:runtime, source, sink} | tail], result) do
    new_entry = %{
      type: :runtime,
      source: source,
      sink: sink,
      snippets: []
    }

    get_detailed_explanation(parsed_manifest, tail, result ++ [new_entry])
  end

  defp get_detailed_explanation(parsed_manifest, [{type, source, sink} | tail], result)
       when type in [:exports, :compile] do
    snippets =
      WhyRecompile.Dependency.dependency_causes(%{
        modules_map: parsed_manifest.modules_map,
        source_files_map: parsed_manifest.source_files_map,
        source_file: source,
        sink_file: sink,
        dependency_type: type
      })
      |> Enum.map(&extract_snippet/1)

    new_entry = %{
      type: type,
      source: source,
      sink: sink,
      snippets: snippets
    }

    result = result ++ [new_entry]
    get_detailed_explanation(parsed_manifest, tail, result)
  end

  @lines_span_padding 5
  defp extract_snippet(%WhyRecompile.Dependency.Cause{origin_file: file, lines_span: lines_span}) do
    # We want to add some paddings to the lines span
    {from, to} = lines_span
    from = max(from - @lines_span_padding, 1)
    to = to + @lines_span_padding

    lines =
      File.stream!(file, [], :line)
      |> Stream.drop(from - 1)
      |> Stream.take(to - from + 1)
      |> Enum.to_list()

    # to may exceeds the file lines count
    to = min(from + length(lines) - 1, to)

    %{
      file: file,
      content: Enum.join(lines),
      lines_span: {from, to},
      highlight: lines_span
    }
  end

  defp manifest_path() do
    manifest_path = Mix.Project.manifest_path()
    Path.join(manifest_path, "compile.elixir")
  end
end
