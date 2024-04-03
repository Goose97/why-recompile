defmodule Ui.FilesPanel do
  @behaviour Orange.Component

  import Orange.Macro
  alias Ui.Utils

  @impl true
  def init(_attrs) do
    :persistent_term.put({__MODULE__, :panel}, :files)
    %{state: %{panel: :files, scroll_offset: 0}, events_subscription: true}
  end

  @impl true
  def handle_event(event, state, attrs) do
    if state.panel == :files do
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
          :persistent_term.put({__MODULE__, :panel}, {:file_dependents, attrs[:selected_file_id]})

          %{state | panel: {:file_dependents, attrs[:selected_file_id]}}

        _ ->
          state
      end
    else
      state
    end
  end

  defp move_up(state, attrs) do
    files = attrs[:files]

    with(
      index when index != nil <- Enum.find_index(files, &(&1.id == attrs[:selected_file_id])),
      true <- index > 0,
      prev_file when prev_file != nil <- Enum.at(files, index - 1)
    ) do
      if attrs[:on_file_select], do: attrs[:on_file_select].(prev_file.id)

      if index - 1 < state.scroll_offset,
        do: %{state | scroll_offset: state.scroll_offset - 1},
        else: state
    else
      _ -> state
    end
  end

  defp move_down(state, attrs) do
    files = attrs[:files]

    with(
      index when index != nil <- Enum.find_index(files, &(&1.id == attrs[:selected_file_id])),
      next_file when next_file != nil <- Enum.at(files, index + 1)
    ) do
      if attrs[:on_file_select], do: attrs[:on_file_select].(next_file.id)

      {_terminal_width, terminal_height} = Orange.Terminal.terminal_size()
      max_file_in_viewport = terminal_height - 3

      if index + 1 >= state.scroll_offset + max_file_in_viewport,
        do: %{state | scroll_offset: state.scroll_offset + 1},
        else: state
    else
      _ -> state
    end
  end

  @impl true
  def render(state, attrs, update) do
    {terminal_width, terminal_height} = Orange.Terminal.terminal_size()
    # We need to now the width that we can occupy with the file path
    # This is a workaround as the framework does not provide a way to get the width of a component yet
    # It's very error prone and can break if the layout changes
    # panel_width = 50% width - border
    # panel_width = terminal_width / 2 - 2
    panel_width = terminal_width / 2 - 1
    # file_path_width = panel_width - padding - recomplie dependencies count width
    maximum_file_path_length = panel_width - 2 - 3

    case state.panel do
      :files ->
        rect style: [width: "1fr", height: "100%"] do
          if attrs[:loading?] do
            loading_panel(terminal_width, terminal_height)
          else
            {
              Orange.Component.VerticalScrollableRect,
              height: terminal_height - 1,
              content_height: length(attrs[:files]),
              scroll_offset: state.scroll_offset,
              children:
                for file <- attrs[:files] do
                  render_file(file, attrs, maximum_file_path_length)
                end,
              title: "Files (with recompile dependencies count)"
            }
          end

          {Ui.HelpModal, id: :help_modal, panel: state.panel}
        end

      {:file_dependents, file_id} ->
        %{recompile_dependencies: dependencies} = Enum.find(attrs[:files], &(&1.id == file_id))

        rect style: [width: "1fr", height: "100%"] do
          {
            Ui.FileDependentsList,
            id: :file_dependents_list,
            width: panel_width,
            height: terminal_height - 1,
            files:
              dependencies
              |> add_number_suffix_to_duplicated_files()
              |> Enum.sort_by(& &1.display_path),
            on_exit: fn -> exit_dependents_list(update) end,
            on_dependent_file_select: attrs[:on_dependent_file_select],
            on_viewing_dependency_link: attrs[:on_viewing_dependency_link]
          }

          {Ui.HelpModal, id: :help_modal, panel: state.panel}
        end
    end
  end

  defp add_number_suffix_to_duplicated_files(files) do
    {result, _} =
      Enum.reduce(files, {[], %{}}, fn file, {result, duplicated_count} ->
        duplicated_count = Map.update(duplicated_count, file.path, 1, &(&1 + 1))

        display_path =
          case Map.get(duplicated_count, file.path) do
            1 -> file.path
            count -> "#{file.path} (#{count - 1})"
          end

        file = Map.put(file, :display_path, display_path)
        {result ++ [file], duplicated_count}
      end)

    result
  end

  defp loading_panel(terminal_width, terminal_height) do
    text = "Analyzing source..."
    width = String.length(text) + 2

    padding_top = max(round(terminal_height / 2 - 4), 0)
    padding_left = max(round((terminal_width / 2 - 2 - width) / 2), 0)

    rect style: [
           width: "100%",
           height: "100%",
           border: true,
           # Hack to center a text inside a div. Missed CSS yet?
           padding: {padding_top, 0, 0, padding_left}
         ],
         title: "Files (with recompile dependencies count)" do
      line do
        Ui.LoadingIcon
        span(do: " #{text}")
      end
    end
  end

  defp exit_dependents_list(update) do
    update.(fn state -> %{state | panel: :files} end)
    :persistent_term.put({__MODULE__, :panel}, :files)
  end

  # This is a hack to query the internal state of the component
  def in_files_list_view?() do
    :persistent_term.get({__MODULE__, :panel}, :files) == :files
  end

  def render_file(file, attrs, max_length) do
    color = if attrs[:selected_file_id] == file.id, do: :dark_blue

    rect direction: :row,
         style: [width: "100%", padding: {0, 1}, background_color: color] do
      line style: [width: "calc(100% - 3)"] do
        Utils.compact_file_path(file.id, max_length)
      end

      span style: [color: :dark_yellow, width: 3, line_wrap: false] do
        file.recompile_dependencies_count
        |> to_string()
        |> String.pad_leading(3, " ")
      end
    end
  end
end
