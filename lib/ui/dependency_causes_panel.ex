defmodule Ui.DependencyCausesPanel do
  @behaviour Orange.Component

  import Orange.Macro

  @type file_path :: binary()
  @type snippet :: %{
          file: file_path,
          content: binary(),
          highlight: {integer(), integer()},
          lines_span: {integer(), integer()}
        }

  @impl true
  @spec init(snippets: [snippet]) :: %{state: nil}
  def init(_attrs), do: %{state: nil}

  @impl true
  def render(_state, attrs, _update) do
    rect style: [
           width: "1fr",
           height: "100%",
           border: true,
           padding: 1
         ],
         title: "Dependency causes" do
      case attrs[:snippets] do
        nil ->
          nil

        [] ->
          span style: [color: :green] do
            "No dependency causes found"
          end

        snippets ->
          for snippet <- snippets do
            code_snippet(snippet)
          end
      end
    end
  end

  defp code_snippet(snippet) do
    {start_line, _end_line} = snippet.lines_span
    {start_highlight, end_highlight} = snippet.highlight

    lines =
      String.split(snippet.content, "\n")
      |> Enum.with_index()

    max_line_number =
      lines
      |> Enum.map(fn {_, line_number} -> line_number + start_line end)
      |> Enum.max()

    line_number_width = max_line_number |> to_string() |> String.length()

    rect do
      line do
        "-- File: "

        span style: [text_modifiers: [:bold]] do
          snippet.file
        end
      end

      rect style: [padding: {1, 0}] do
        Enum.map(lines, fn {line, index} ->
          line_number = start_line + index
          highlight = line_number >= start_highlight && line_number <= end_highlight

          padded_line_number =
            line_number |> to_string() |> String.pad_leading(line_number_width, " ")

          if highlight do
            span style: [color: :dark_green] do
              "#{padded_line_number} => │ #{line}"
            end
          else
            span do
              "#{padded_line_number}    │ #{line}"
            end
          end
        end)
      end
    end
  end
end
