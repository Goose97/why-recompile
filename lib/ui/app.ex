defmodule Ui.App do
  @behaviour Orange.Component

  import Orange.Macro

  @impl true
  def init(_attrs) do
    state = %{
      graph: nil,
      selected_file_id: nil,
      viewing_dependency_link: nil,
      dependency_causes: %{},
      snippets: nil,
      in_search_mode: false,
      search_query: nil
    }

    %{state: state, events_subscription: true}
  end

  @impl true
  def handle_event(event, state, _attributes) do
    case event do
      %Orange.Terminal.KeyEvent{code: {:char, "q"}} ->
        if not state.in_search_mode, do: Orange.stop()
        state

      %Orange.Terminal.KeyEvent{code: {:char, "/"}} ->
        %{state | in_search_mode: true}

      %Orange.Terminal.KeyEvent{code: :esc} ->
        # Since esc can be used to exit file dependents list as well,
        # we need to make sure we are in the files list view
        if state.in_search_mode && Ui.FilesPanel.in_files_list_view?(),
          do: %{state | in_search_mode: false, search_query: nil},
          else: state

      _ ->
        state
    end
  end

  @impl true
  def after_mount(_state, _attrs, update) do
    # Load data asynchronously
    Task.start(fn ->
      graph =
        WhyRecompile.get_graph()
        |> Enum.sort_by(& &1.recompile_dependencies_count, :desc)

      update.(fn state ->
        selected_file_id = if graph != [], do: hd(graph).id

        %{state | graph: graph, selected_file_id: selected_file_id}
      end)
    end)
  end

  @impl true
  def render(state, _attrs, update) do
    files = if state.graph != nil, do: display_files(state), else: []

    selected_file_id =
      cond do
        state.graph == nil -> nil
        Enum.find(files, &(&1.id == state.selected_file_id)) -> state.selected_file_id
        # If the selected file is not in the list, fallback to the first file
        true -> if files != [], do: hd(files).id
      end

    rect direction: :column do
      rect direction: :row, style: [height: "calc(100% - 1)"] do
        {
          Ui.FilesPanel,
          id: :files_panel,
          loading?: state.graph == nil,
          files: files,
          selected_file_id: selected_file_id,
          on_file_select: fn file_id -> update.(%{state | selected_file_id: file_id}) end,
          on_dependent_file_select: &maybe_get_dependency_causes(&1, state, update),
          on_viewing_dependency_link: &on_viewing_dependency_link(&1, state, update)
        }

        {Ui.DependencyCausesPanel,
         snippets: unless(Ui.FilesPanel.in_files_list_view?(), do: state.snippets)}
      end

      if state.in_search_mode do
        {
          Ui.SearchBar,
          on_search_submit: fn query ->
            update.(%{state | search_query: query})
          end,
          on_search_cancel: fn ->
            update.(%{state | in_search_mode: false, search_query: nil})
          end
        }
      else
        line style: [color: :dark_yellow] do
          "j/k: Move; <enter>: Select; ?: Help"
        end
      end
    end
  end

  defp display_files(state) do
    if state.search_query do
      Enum.filter(state.graph, &String.contains?(&1.id, state.search_query))
    else
      state.graph
    end
  end

  defp maybe_get_dependency_causes(dependency_id, state, update_state_cb) do
    if !Map.has_key?(state.dependency_causes, {state.selected_file_id, dependency_id}) do
      file = Enum.find(state.graph, &(&1.id == state.selected_file_id))
      dependency = Enum.find(file.recompile_dependencies, &(&1.id == dependency_id))

      causes =
        WhyRecompile.get_recompile_dependency_causes(
          dependency.id,
          state.selected_file_id,
          dependency.reason
        )

      state
      |> put_in([:dependency_causes, {state.selected_file_id, dependency_id}], causes)
      |> update_state_cb.()
    end
  end

  # Stop viewing dependency link
  defp on_viewing_dependency_link(nil, state, update_state_cb),
    do: update_state_cb.(%{state | snippets: nil})

  defp on_viewing_dependency_link({dependency_id, dependency_link}, state, update_state_cb) do
    links = Map.get(state.dependency_causes, {state.selected_file_id, dependency_id})
    %{snippets: snippets} = Enum.find(links, &({&1.type, &1.source, &1.sink} == dependency_link))

    update_state_cb.(%{state | snippets: snippets})
  end
end
