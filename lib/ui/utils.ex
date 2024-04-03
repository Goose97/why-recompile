defmodule Ui.Utils do
  @doc """
  Compact the file path to fit the maximum length, prioritizing the latter parts of the path

  ## Example

      iex> compact_file_path("lib/fixtures/D1.ex", 10)
      iex> ".../D1.ex"
  """
  def compact_file_path(file_path, maximum) do
    if render_length(file_path) > maximum do
      substrings = String.split(file_path, "/")
      # {output, truncated}
      initial = {["..."], false}

      {output, truncated} =
        Enum.reduce_while(substrings, initial, fn substring, {output, truncated} ->
          total_length =
            length(output) - 1 +
              (output |> Enum.map(&render_length/1) |> Enum.sum())

          # Can we fit the current substring?
          if total_length + render_length(substring) + 1 > maximum do
            {:halt, {output, true}}
          else
            output = List.insert_at(output, 1, substring)
            {:cont, {output, truncated}}
          end
        end)

      output = if not truncated, do: tl(output), else: output
      Enum.join(output, "/")
    else
      file_path
    end
  end

  @compile {:inline, render_length: 1}
  defp render_length(string), do: String.graphemes(string) |> length()
end
