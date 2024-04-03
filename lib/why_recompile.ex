defmodule WhyRecompile do
  @moduledoc """
  API to interact with the dependency graph
  """

  @type manifest_path :: binary()
  @type file_path :: binary()

  def start() do
    :ets.new(__MODULE__.Cache, [:set, :named_table, :public])
    Orange.start(Ui.App)
  end

  def get_graph() do
    load_code_path_task = Task.async(fn -> add_code_path() end)

    graph = __MODULE__.Graph.build(manifest_path())
    :ets.insert(__MODULE__.Cache, {:graph, graph})

    graph_summary =
      for vertex <- __MODULE__.Graph.summarize(graph) do
        dependencies =
          __MODULE__.Dependency.recompile_dependencies(graph, vertex.id)
          |> Enum.flat_map(fn {reason, dependents} ->
            for {{file, chain}, index} <- Enum.with_index(dependents) do
              %{
                # Sometimes, a dependency between two files has multiple paths,
                # we need to differentiate them
                id: make_ref(),
                path: file,
                reason: reason,
                dependency_chain: format_dependency_chain(chain, vertex.id)
              }
            end
          end)
          |> Enum.sort_by(& &1.id)

        recompile_dependencies_count = Enum.uniq_by(dependencies, & &1.path) |> length()

        Map.merge(vertex, %{
          recompile_dependencies: dependencies,
          recompile_dependencies_count: recompile_dependencies_count
        })
      end

    cache_dependency_path(graph_summary)
    Task.await(load_code_path_task)

    graph_summary
  end

  defp add_code_path() do
    app_code_path = get_project_code_path()
    :code.add_path(String.to_charlist(app_code_path))
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

  defp cache_dependency_path(graph_summary) do
    Enum.each(graph_summary, fn vertex ->
      Enum.each(vertex.recompile_dependencies, fn dependent ->
        key = {:dependency_path, vertex.id, dependent.id, dependent.reason}
        :ets.insert(__MODULE__.Cache, {key, dependent.dependency_chain})
      end)
    end)
  end

  @spec get_recompile_dependency_causes(
          file_path,
          file_path,
          __MODULE__.Dependency.dependency_reason()
        ) :: any()
  def get_recompile_dependency_causes(source_file, sink_file, reason) do
    case :ets.lookup(__MODULE__.Cache, {:dependency_path, sink_file, source_file, reason}) do
      [{_, path}] ->
        # get_detailed_explanation(path ++ [{:eof, sink_file, nil}])
        get_detailed_explanation(path)

      [] ->
        []
    end
  end

  # Expand the dependency path to a detailed explanation
  defp get_detailed_explanation(path) do
    get_detailed_explanation(path, [])
  end

  defp get_detailed_explanation([], result), do: result

  defp get_detailed_explanation([{:runtime, source, sink} | tail], result) do
    new_entry = %{
      type: :runtime,
      source: source,
      sink: sink,
      snippets: []
    }

    get_detailed_explanation(tail, result ++ [new_entry])
  end

  defp get_detailed_explanation([{type, source, sink} | tail], result)
       when type in [:exports, :compile] do
    snippets =
      WhyRecompile.Dependency.dependency_causes(%{
        source_file: source,
        sink_file: sink,
        manifest: manifest_path(),
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
    get_detailed_explanation(tail, result)
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
    manifest_path = :persistent_term.get({__MODULE__, :manifest_path}, nil)

    if manifest_path do
      manifest_path
    else
      manifest_path = do_get_manifest_path()
      :persistent_term.put({__MODULE__, :manifest_path}, manifest_path)
      manifest_path
    end
  end

  # This is a workaround to get the manifest path
  # The erl PATH is override by the release, therefore, if we invoke elixir directly,
  # it won't able the find the boot script.
  #
  # The release shipped with start.boot and start_clean. Both are not suitable for our case since
  # we only want the minimal modules to be loaded, not our entire application.
  #
  # To solve this, we include the no_dot_erlang boot script in the release.
  # This boot script is shipped with the default Erlang distribution (https://www.erlang.org/doc/system_principles/system_principles#default-boot-scripts)
  defp do_get_manifest_path() do
    manifest_path =
      if System.get_env("RELEASE_ROOT") == nil do
        # dev environment
        Mix.Project.manifest_path()
      else
        boot = Path.join(System.get_env("RELEASE_ROOT"), "no_dot_erlang")

        output_label = "manifest"

        output =
          :os.cmd(
            'elixir --boot "#{boot}" -S mix eval "Mix.Project.manifest_path() |> IO.inspect(label: \\"#{output_label}\\")"'
          )
          |> to_string()

        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.starts_with?(line, "#{output_label}: ") do
            String.replace(line, "#{output_label}: ", "")
            |> String.replace(~s/"/, "")
            |> String.trim()
          end
        end)
      end

    Path.join(manifest_path, "compile.elixir")
  end

  defp get_project_code_path() do
    manifest_path =
      if System.get_env("RELEASE_ROOT") == nil do
        # dev environment
        Mix.Project.app_path()
      else
        boot = Path.join(System.get_env("RELEASE_ROOT"), "no_dot_erlang")

        output_label = "app_path"

        output =
          :os.cmd(
            'elixir --boot "#{boot}" -S mix eval "Mix.Project.app_path() |> IO.inspect(label: \\"#{output_label}\\")"'
          )
          |> to_string()

        output
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.starts_with?(line, "#{output_label}: ") do
            String.replace(line, "#{output_label}: ", "")
            |> String.replace(~s/"/, "")
            |> String.trim()
          end
        end)
      end

    Path.join(manifest_path, "ebin")
  end
end
