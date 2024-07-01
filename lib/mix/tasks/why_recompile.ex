defmodule Mix.Tasks.WhyRecompile do
  @moduledoc "Find out which files will be recompiled when you edit and why `mix help why_recompile`"

  use Mix.Task

  @impl Mix.Task
  def run([action | args]) do
    case action do
      "list" ->
        Mix.Task.run("compile")
        list(args)

      "show" ->
        Mix.Task.run("compile")
        show(args)

      _ ->
        help()
    end
  end

  defp list(args) do
    {parsed_args, _, invalid} =
      OptionParser.parse(args,
        strict: [all: :boolean, limit: :integer],
        aliases: [a: :all, l: :limit]
      )

    if invalid != [] do
      color("Invalid option: #{inspect(invalid)}", :red) |> IO.puts()
      help()
    else
      graph = WhyRecompile.get_graph()

      # There are two types of recompile dependencies:
      # 1. hard (compile related): if A has a hard dependency on B and B recompiled, then DEFINITELY A will be recompiled
      # 2. soft (export related): if A has a soft dependency on B and B recompiled, then MAYBE A will be recompiled
      #
      # Struct dependency is one of the soft dependencies example. A uses struct defined in B. If B
      # recompiled without changing the struct definition, A WON'T have to recompile.
      rows =
        for vertex <- graph do
          hard_dependencies =
            vertex.recompile_dependencies
            |> Enum.filter(fn %{reason: reason} -> reason in [:compile, :compile_then_runtime] end)
            |> Enum.count()

          soft_dependencies =
            vertex.recompile_dependencies
            |> Enum.filter(fn %{reason: reason} -> reason in [:exports, :exports_then_compile] end)
            |> Enum.count()

          %{
            path: vertex.id,
            hard_recompile_dependencies_count: hard_dependencies,
            soft_recompile_dependencies_count: soft_dependencies
          }
        end
        |> Enum.sort_by(& &1.hard_recompile_dependencies_count, &>=/2)

      rows =
        if !Keyword.get(parsed_args, :all, false),
          do:
            Enum.reject(
              rows,
              &(&1.hard_recompile_dependencies_count + &1.soft_recompile_dependencies_count == 0)
            ),
          else: rows

      rows = if parsed_args[:limit], do: Enum.take(rows, parsed_args[:limit]), else: rows

      columns = [
        %{field: :path, title: "File path"},
        %{field: :hard_recompile_dependencies_count, title: "Number of recompile files"},
        %{field: :soft_recompile_dependencies_count, title: "Number of MAYBE recompile files"}
      ]

      WhyRecompile.TablePrinter.print_table(rows, columns)
    end
  end

  defp show(args) do
    {parsed_args, [file_path], invalid} =
      OptionParser.parse(args,
        strict: [verbose: :integer, filter: :string, include_export: :boolean],
        aliases: [v: :verbose, f: :filter]
      )

    verbose_level = Keyword.get(parsed_args, :verbose, 0)

    if invalid != [] do
      color("Invalid option: #{inspect(invalid)}", :red) |> IO.puts()
      help()
    else
      graph = WhyRecompile.get_graph()
      vertex = Enum.find(graph, fn vertex -> vertex.id == file_path end)

      dependencies =
        if parsed_args[:filter] do
          Enum.filter(vertex.recompile_dependencies, fn %{path: path} ->
            String.contains?(path, parsed_args[:filter])
          end)
        else
          vertex.recompile_dependencies
        end

      {hard_dependencies, soft_dependencies} =
        Enum.split_with(dependencies, fn %{reason: reason} ->
          reason in [:compile, :compile_then_runtime]
        end)

      if parsed_args[:include_export] do
        bold("Compile dependencies:") |> IO.puts()
        print_dependencies(hard_dependencies, verbose_level)

        bold("\nExport dependencies:") |> IO.puts()
        print_dependencies(soft_dependencies, verbose_level)
      else
        print_dependencies(hard_dependencies, verbose_level)
      end
    end
  end

  defp print_dependencies(dependencies, verbose_level) do
    Enum.with_index(dependencies)
    |> Enum.each(fn {dependency, index} ->
      %{
        path: path,
        dependency_chain: dependency_chain
      } = dependency

      IO.puts(color(path, :magenta))

      if verbose_level >= 1, do: print_dependency_chain(dependency_chain)

      if verbose_level >= 2 do
        new_line()

        WhyRecompile.get_detailed_explanation(dependency_chain)
        |> print_dependency_link_explanation()
      end

      if verbose_level >= 1 && index != length(dependencies) - 1, do: new_line()
    end)
  end

  defp print_dependency_chain(chain) do
    Enum.with_index(chain)
    |> Enum.map(fn {{reason, _, sink}, index} ->
      offset = 2 + index * 4

      text_color =
        case reason do
          :compile -> :red
          :exports -> :white
          :runtime -> :white
        end

      puts_offset("│", offset)
      puts_offset("│ #{color(reason, text_color)}", offset)
      puts_offset("│", offset)
      puts_offset("└─➤ #{sink}", offset)
    end)
  end

  [
    %{
      sink: "lib/fixtures/D2.ex",
      snippets: [
        %{
          content:
            "defmodule D1 do\n  require D2\n\n  def x(), do: D2.x()\n\n  def y(), do: %D2{a: 1}\nend\n",
          file: "lib/fixtures/D1.ex",
          highlight: {4, 4},
          lines_span: {1, 7}
        }
      ],
      source: "lib/fixtures/D1.ex",
      type: :compile
    },
    %{
      sink: "lib/fixtures/D3.ex",
      snippets: [
        %{
          content: "    end\n  end\n\n  defstruct [:a]\n\n  def z(), do: D3.z()\nend\n",
          file: "lib/fixtures/D2.ex",
          highlight: {14, 14},
          lines_span: {9, 15}
        },
        %{
          content:
            "defmodule D2 do\n  require D3\n\n  defmacro x() do\n    x = D3.y()\n\n    quote do\n      unquote(x) + 2\n    end\n  end\n",
          file: "lib/fixtures/D2.ex",
          highlight: {5, 5},
          lines_span: {1, 10}
        }
      ],
      source: "lib/fixtures/D2.ex",
      type: :compile
    }
  ]

  defp print_dependency_link_explanation(explanation) do
    Enum.with_index(explanation)
    |> Enum.each(fn {item, index} ->
      puts_offset("#{index + 1}. #{item.source} ────➤ #{item.sink} (#{item.type})", 2)

      Enum.with_index(item.snippets)
      |> Enum.each(fn {snippet, index} ->
        print_code_snippet(snippet)
        if index != length(item.snippets) - 1, do: new_line()
      end)

      if index != length(explanation) - 1, do: new_line()
    end)
  end

  defp print_code_snippet(snippet) do
    "-- #{snippet.file}"
    |> italic()
    |> puts_offset(4)

    {start_line, end_line} = snippet.lines_span
    line_number_width = end_line |> to_string() |> String.length()

    snippet.content
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.each(fn {line, index} ->
      line_number = index + start_line

      text_color =
        if line_number >= elem(snippet.highlight, 0) && line_number <= elem(snippet.highlight, 1),
          do: :green,
          else: :white

      line_number_text =
        line_number
        |> to_string()
        |> String.pad_trailing(line_number_width)

      "#{line_number_text}  #{line}"
      |> color(text_color)
      |> puts_offset(4)
    end)
  end

  defp color(text, color) do
    case color do
      :red -> "#{IO.ANSI.red()}#{text}#{IO.ANSI.reset()}"
      :blue -> "#{IO.ANSI.blue()}#{text}#{IO.ANSI.reset()}"
      :green -> "#{IO.ANSI.green()}#{text}#{IO.ANSI.reset()}"
      :yellow -> "#{IO.ANSI.yellow()}#{text}#{IO.ANSI.reset()}"
      :magenta -> "#{IO.ANSI.magenta()}#{text}#{IO.ANSI.reset()}"
      :cyan -> "#{IO.ANSI.cyan()}#{text}#{IO.ANSI.reset()}"
      :white -> "#{IO.ANSI.white()}#{text}#{IO.ANSI.reset()}"
      :black -> "#{IO.ANSI.black()}#{text}#{IO.ANSI.reset()}"
      {r, g, b} -> "#{IO.ANSI.color(r, g, b)}#{text}#{IO.ANSI.reset()}"
    end
  end

  defp puts_offset(text, offset) do
    text = String.duplicate(" ", offset) <> text
    IO.puts(text)
  end

  defp bold(text), do: "#{IO.ANSI.bright()}#{text}#{IO.ANSI.reset()}"
  defp italic(text), do: "#{IO.ANSI.italic()}#{text}#{IO.ANSI.reset()}"

  @compile {:inline, new_line: 0}
  defp new_line(), do: IO.puts("")

  defp help() do
    IO.puts("""
    #{bold("list")}   List all files in the source code and their recompile dependencies count

    Usage:
      mix why_recompile list [-a | --all] [-l | --limit=<number>]

    Option:
      --all             List all files. By default, files without any recompile dependencies are not listed
      --limit=<number>  Limit the number of files

    #{String.duplicate("-", 60)}

    #{bold("show")}   Show the recompile dependencies of a file

    Usage:
      mix why_recompile show [-v | --verbose=<level>] [-f | --filter] [--include-export] <file-path>

    Option:
      -v, --verbose     The verbosity level
        • 1: Print the dependency chain
        • 2: Same as 1 and print the detailed dependency reason

      -f, --filter      Filter the dependency by name, support partial match
      --include-export  Include export dependencies
    """)
  end
end