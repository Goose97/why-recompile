defmodule Ui.FileDependentsList do
  @behaviour Orange.Component

  import Orange.Macro
  alias Ui.Utils

  @type dependency_reason :: :runtime | :exports | :compile
  @type file_path :: binary()
  @type dependent_file :: %{
          dependency_chain: [{dependency_reason, file_path, file_path}],
          id: binary(),
          path: file_path,
          reason: dependency_reason
        }

  @type state :: %{
          # The id of the file that is currently selected
          # It's a pair of the file id and the item index in the chain. If the index is nil,
          # it means that we are selecting the parent file
          selected_file_id: {binary(), integer()} | nil,
          expanding_file_id: binary() | nil,
          scroll_offset: integer()
        }

  @impl true
  @spec init(files: [dependent_file]) :: state
  def init(attrs) do
    selected_file_id =
      case attrs[:files] do
        [file | _] -> file.id
        _ -> nil
      end

    state = %{selected_file_id: {selected_file_id, nil}, expanding_file_id: nil, scroll_offset: 0}
    %{state: state, events_subscription: true}
  end

  @impl true
  def handle_event(event, state, attrs) do
    case event do
      %Orange.Terminal.KeyEvent{code: {:char, "j"}} ->
        move_down(state, attrs)

      %Orange.Terminal.KeyEvent{code: :down} ->
        move_down(state, attrs)

      %Orange.Terminal.KeyEvent{code: {:char, "k"}} ->
        move_up(state, attrs)

      %Orange.Terminal.KeyEvent{code: :up} ->
        move_up(state, attrs)

      %Orange.Terminal.KeyEvent{code: :enter} ->
        expanding_file_id = state.expanding_file_id

        case state.selected_file_id do
          # Collapse the expanding parent file
          {^expanding_file_id, nil} ->
            %{state | expanding_file_id: nil}

          # Expand the expanding parent file
          {parent_file_id, nil} ->
            attrs[:on_dependent_file_select].(parent_file_id)
            %{state | expanding_file_id: parent_file_id}

          # Expand the children file is a no-op
          {^expanding_file_id, children_index} when children_index != nil ->
            state
        end

      %Orange.Terminal.KeyEvent{code: :esc} ->
        attrs[:on_exit].()
        state

      _ ->
        state
    end
  end

  defp move_up(state, attrs) do
    files = attrs[:files]

    entries =
      Enum.flat_map(files, fn file ->
        entries = [{file.id, nil}]

        if file.id == state.expanding_file_id do
          children_entries =
            Enum.with_index(file.dependency_chain)
            |> Enum.map(fn {_, children_index} ->
              {file.id, children_index}
            end)

          entries ++ children_entries
        else
          entries
        end
      end)

    index = Enum.find_index(entries, &(&1 == state.selected_file_id))

    if index > 0 do
      entry = Enum.at(entries, index - 1)
      invoke_callback(entry, attrs)

      state = maybe_scroll(entries, index - 1, :up, attrs, state)
      %{state | selected_file_id: entry}
    else
      state
    end
  end

  defp move_down(state, attrs) do
    files = attrs[:files]

    entries =
      Enum.flat_map(files, fn file ->
        entries = [{file.id, nil}]

        if file.id == state.expanding_file_id do
          children_entries =
            Enum.with_index(file.dependency_chain)
            |> Enum.map(fn {_, children_index} ->
              {file.id, children_index}
            end)

          entries ++ children_entries
        else
          entries
        end
      end)

    index = Enum.find_index(entries, &(&1 == state.selected_file_id))

    if index < length(entries) - 1 do
      entry = Enum.at(entries, index + 1)
      invoke_callback(entry, attrs)

      state = maybe_scroll(entries, index + 1, :down, attrs, state)
      %{state | selected_file_id: entry}
    else
      state
    end
  end

  # We need to calculate the y offset of the current selected entry
  # If it's out of the viewport, we need to scroll to it
  defp maybe_scroll(entries, selected_entry_index, direction, attrs, state) do
    selected_entry_offset_y =
      case direction do
        # Not include the current selected entry
        :up -> Enum.slice(entries, 0, selected_entry_index)
        # Include the current selected entry
        :down -> Enum.slice(entries, 0, selected_entry_index + 1)
      end
      |> Enum.map(fn
        # Parent entry has height of 1
        {_, nil} -> 1
        # Child entry has height of 4
        _ -> 4
      end)
      |> Enum.sum()

    case direction do
      :up ->
        if selected_entry_offset_y < state.scroll_offset,
          do: %{state | scroll_offset: selected_entry_offset_y},
          else: state

      :down ->
        # Minus the border top and bottom
        scroll_viewport_height = attrs[:height] - 2

        if selected_entry_offset_y > scroll_viewport_height + state.scroll_offset,
          do: %{state | scroll_offset: selected_entry_offset_y - scroll_viewport_height},
          else: state
    end
  end

  defp invoke_callback({parent_file_id, children_index}, attrs) do
    parent_file = Enum.find(attrs[:files], &(&1.id == parent_file_id))

    if children_index do
      dependency_link = Enum.at(parent_file.dependency_chain, children_index)
      attrs[:on_viewing_dependency_link].({parent_file.id, dependency_link})
    else
      # Viewing parent file
      attrs[:on_viewing_dependency_link].(nil)
    end
  end

  defp content_height(attrs, state) do
    Enum.map(attrs[:files], fn file ->
      height = 1

      if file.id == state.expanding_file_id do
        height + length(file.dependency_chain) * 4
      else
        height
      end
    end)
    |> Enum.sum()
  end

  @impl true
  def render(state, attrs, _update) do
    rect style: [width: "100%", height: "100%"] do
      {
        Orange.Component.VerticalScrollableRect,
        height: attrs[:height],
        content_height: content_height(attrs, state),
        scroll_offset: state.scroll_offset,
        children:
          for file <- attrs[:files] do
            if state.expanding_file_id == file.id do
              List.flatten([
                parent_file(file, state, attrs),
                expanded_dependencies_chain(file.dependency_chain, state)
              ])
            else
              parent_file(file, state, attrs)
            end
          end,
        title: "Recompile files"
      }
    end
  end

  defp parent_file(file, state, attrs) do
    icon = if state.expanding_file_id == file.id, do: "▼", else: "▶"
    color = if state.selected_file_id == {file.id, nil}, do: :dark_blue

    line style: [background_color: color, width: "100%", padding: {0, 1}] do
      icon <> " " <> Utils.compact_file_path(file.display_path, attrs[:width] - 2)
    end
  end

  defp expanded_dependencies_chain(chain, state) do
    Enum.with_index(chain)
    |> Enum.map(fn {{reason, _from, to}, children_index} ->
      color =
        case reason do
          :runtime -> :white
          :exports -> :white
          :compile -> :dark_red
        end

      background_color = if elem(state.selected_file_id, 1) == children_index, do: :dark_blue

      # Add left padding to create a cascade effect
      left_padding = 2 + children_index * 4

      rect style: [
             background_color: background_color,
             width: "100%",
             padding: {0, 0, 0, left_padding}
           ] do
        "│"

        line do
          "│ "

          span style: [color: color] do
            "(#{reason})"
          end
        end

        "│"
        "└─➤ #{to}"
      end
    end)
  end
end
