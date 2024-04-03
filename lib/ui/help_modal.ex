defmodule Ui.HelpModal do
  @behaviour Orange.Component

  import Orange.Macro

  @impl true
  def init(_attrs), do: %{state: %{open: false}, events_subscription: true}

  @impl true
  def handle_event(event, state, attrs) do
    case event do
      %Orange.Terminal.KeyEvent{code: {:char, "?"}} ->
        if !state.open do
          Orange.focus(attrs[:id])
          %{state | open: true}
        else
          state
        end

      %Orange.Terminal.KeyEvent{code: :esc} ->
        if state.open do
          Orange.unfocus(attrs[:id])
          %{state | open: false}
        else
          state
        end

      _ ->
        state
    end
  end

  defp keybindings(:files) do
    [
      {"j/<arrow down>", "Move down"},
      {"k/<arrow up>", "Move up"},
      {"<enter>", "View the recompile list"},
      {"/", "Search"},
      {"q", "Quit"}
    ]
  end

  defp keybindings({:file_dependents, _}) do
    [
      {"j/<arrow down>", "Move down"},
      {"k/<arrow up>", "Move up"},
      {"<enter>", "Expand/Collapse"},
      {"<esc>", "Back"},
      {"q", "Quit"}
    ]
  end

  @impl true
  def render(state, attrs, _update) do
    {_, height} = Orange.Terminal.terminal_size()

    keybindings = keybindings(attrs[:panel])

    offset_y =
      cond do
        height < 16 -> 4
        height < 32 -> 8
        true -> 12
      end

    longest_key =
      Enum.map(keybindings, &(elem(&1, 0) |> String.length()))
      |> Enum.max()

    keybindings_block =
      rect do
        span style: [text_modifiers: [:bold]] do
          "Keybindings:"
        end

        rect style: [padding: {0, 2}] do
          for {key, description} <- keybindings do
            line do
              span style: [color: :cyan] do
                String.pad_leading(key, longest_key, " ")
              end

              span(do: " ")
              span(do: description)
            end
          end
        end
      end

    explanation_block =
      rect do
        line do
          "This panel displays a list of files and their respective recompile dependencies count. For example:"
        end

        rect style: [padding: {0, 2}, border: true], direction: :row do
          rect style: [padding: {0, 3, 0, 0}] do
            "lib/some/example/file.ex"
          end

          rect style: [color: :yellow] do
            "3"
          end
        end

        line do
          "This means that if lib/some/example/file.ex is recompiled, 3 other files will be recompiled as well."
        end
      end

    modal_content =
      rect style: [padding: {1, 1}] do
        keybindings_block
        line(do: "")

        if attrs[:panel] == :files do
          explanation_block
        end
      end

    {
      Orange.Component.Modal,
      open: state.open,
      offset_x: 12,
      offset_y: offset_y,
      children: modal_content,
      title: %{
        text: "Help (<esc> to close)",
        color: :green,
        text_modifiers: [:bold],
        offset: 1
      },
      style: [border_color: :green]
    }
  end
end
