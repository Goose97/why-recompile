defmodule Ui.SearchBar do
  @behaviour Orange.Component

  import Orange.Macro

  @impl true
  def init(_attrs), do: %{state: %{input: "", is_searching: false}}

  @impl true
  def render(state, attrs, update) do
    rect direction: :row do
      {
        Orange.Component.Input,
        on_submit: fn input ->
          attrs[:on_search_submit].(input)
          update.(%{state | is_searching: true})
        end,
        on_exit: attrs[:on_search_cancel],
        id: :search_bar,
        auto_focus: true,
        prefix: "Search:",
        style: [color: :dark_cyan]
      }

      if state.is_searching do
        span style: [color: :dark_yellow] do
          " | <esc> to exit search"
        end
      end
    end
  end
end
