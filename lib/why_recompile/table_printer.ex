defmodule WhyRecompile.TablePrinter do
  @header_column_separator "-+-"

  def print_table(rows, columns) do
    table =
      Enum.map(rows, fn row ->
        for %{field: field} <- columns, do: Map.get(row, field) |> to_string()
      end)

    headers = Enum.map(columns, &Map.get(&1, :title))
    columns_widths = columns_widths([headers | table])

    hr = List.duplicate("-", length(headers))

    print_row(hr, columns_widths, @header_column_separator)
    print_row(headers, columns_widths)
    print_row(hr, columns_widths, @header_column_separator)
    Enum.map(table, &print_row(&1, columns_widths))
    print_row(hr, columns_widths, @header_column_separator)
  end

  defp columns_widths(table) do
    table
    |> transpose()
    |> Enum.map(fn cell ->
      cell
      |> Enum.map(&String.length/1)
      |> Enum.max()
      # for the padding
      |> Kernel.+(2)
    end)
  end

  defp transpose(rows) do
    rows
    |> List.zip()
    |> Enum.map(&Tuple.to_list/1)
  end

  defp print_row(row, column_widths, separator \\ " | ") do
    padding = String.slice(separator, 0, 1)

    # Add left padding for the first column
    row = List.update_at(row, 0, &(padding <> &1))

    IO.puts(
      row
      |> Enum.zip(column_widths)
      |> Enum.map(fn {cell, column_width} ->
        String.pad_trailing(cell, column_width, padding)
      end)
      |> Enum.join(separator)
    )
  end
end
