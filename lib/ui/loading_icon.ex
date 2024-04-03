defmodule Ui.LoadingIcon do
  @behaviour Orange.Component

  import Orange.Macro

  @frame_per_sec 6

  @impl true
  def init(_attrs) do
    state = %{
      frame: 0,
      timer_ref: nil
    }

    %{state: state, events_subscription: false}
  end

  @impl true
  def handle_event(_event, state, _attributes) do
    state
  end

  @impl true
  def after_mount(state, _attrs, update) do
    {:ok, ref} =
      :timer.apply_interval(round(1000 / @frame_per_sec), __MODULE__, :advance_frame, [update])

    update.(%{state | timer_ref: ref})
  end

  def advance_frame(update) do
    update.(fn state -> %{state | frame: rem(state.frame + 1, 8)} end)
  end

  @impl true
  def after_unmount(state, _attrs, _update) do
    :timer.cancel(state.timer_ref)
  end

  @impl true
  def render(state, _attrs, _update) do
    text =
      case state.frame do
        0 -> "⣷"
        1 -> "⣯"
        2 -> "⣟"
        3 -> "⡿"
        4 -> "⢿"
        5 -> "⣻"
        6 -> "⣽"
        7 -> "⣾"
      end

    span(do: text)
  end
end
