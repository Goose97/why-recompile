defmodule WhyRecompile.Parser do
  @moduledoc """
  Utilities to parse Elixir source files. During the parse phase, it will emit some pre-configured events.
  """

  defmodule State do
    # aliases, imports, requires are module scoped. We model them as a stack with each
    # stack frame representing the current module being processed. We add a new frame
    # when we enter a new module and pop the frame when we leave the module.
    #
    # :user_acc is the user defined accumulator that can be used to store any additional
    # information during the parse phase. This will be returned to the user at the end.
    defstruct [:user_acc, current_module: [], imports: [[]], requires: [[]], aliases: [%{}]]

    def append_module(state, module) do
      %{state | current_module: state.current_module ++ [module]}
    end

    def pop_module(state) do
      %{state | current_module: List.delete_at(state.current_module, -1)}
    end

    def current_module(state) do
      List.flatten(state.current_module) |> Module.concat()
    end

    def append_new_frame(state) do
      %{
        state
        | aliases: [%{} | state.aliases],
          imports: [[] | state.imports],
          requires: [[] | state.requires]
      }
    end

    def pop_frame(state) do
      %{
        state
        | aliases: tl(state.aliases),
          imports: tl(state.imports),
          requires: tl(state.requires)
      }
    end

    def add_aliases(state, aliases) do
      [head | tail] = state.aliases
      %{state | aliases: [Map.merge(head, aliases) | tail]}
    end

    def add_import(state, import_expr, module_name) do
      imports =
        List.update_at(state.imports, 0, fn imports ->
          new = %{expr: import_expr, module: Module.concat(module_name)}
          [new | imports]
        end)

      %{state | imports: imports}
    end

    def add_require(state, require_expr, module_name) do
      requires =
        List.update_at(state.requires, 0, fn requires ->
          new = %{expr: require_expr, module: Module.concat(module_name)}
          [new | requires]
        end)

      %{state | requires: requires}
    end

    # - Expand __MODULE__ macro
    # - Expand aliases
    def resolve_module_name(state, module_name) do
      case module_name do
        [{:__MODULE__, _, nil} | tail] -> List.flatten(state.current_module) ++ tail
        _ -> module_name
      end
      |> expand_alias(state.aliases)
    end

    defp expand_alias(names, aliases) do
      case all_aliases(aliases) |> Map.get(hd(names)) do
        # No alias
        nil -> names
        aliases -> aliases ++ tl(names)
      end
    end

    defp all_aliases(aliases) do
      Enum.reduce(aliases, %{}, fn item, acc -> Map.merge(acc, item) end)
    end
  end

  def parse(ast, user_init_acc \\ nil, event_handler) do
    emit_event = fn event, expr, state ->
      case event_handler.(event, expr, state, state.user_acc) do
        {:cont, user_acc} ->
          {expr, %{state | user_acc: user_acc}}

        {:skip, user_acc} ->
          # nil overrides the content of the current node. This means we gonna skip
          # recursing into the children of the current node.
          {nil, %{state | user_acc: user_acc}}

        {:halt, user_acc} ->
          throw({:halt, user_acc})
      end
    end

    pre = fn
      # Enter module
      {:defmodule, _, [{:__aliases__, _, names}, _]} = expr, state ->
        state =
          state
          |> State.append_module(names)
          |> State.append_new_frame()

        emit_event.({:enter_module, State.current_module(state)}, expr, state)

      {atom, _, [_, [do: _function_body]]} = expr, state when atom in [:def, :defp] ->
        emit_event.(:enter_function, expr, state)

      # A variable name alias
      {:alias, _, nil} = expr, state ->
        emit_event.(:expression, expr, state)

      # alias A
      # alias A, as: B
      # alias A.{B, C}
      {:alias, _, args} = expr, state ->
        alias_pairs =
          case args do
            # Single alias
            [{:__aliases__, _, from}] ->
              [{List.last(from), from}]

            # Single alias with rename
            [{:__aliases__, _, from}, [as: {:__aliases__, _, [to]}]] ->
              [{to, from}]

            # Multiple aliases
            [{{:., _, [{:__aliases__, _, root} | _]}, _, aliases}] ->
              for {:__aliases__, _, module_name} <- aliases,
                  do: {List.last(module_name), root ++ module_name}

            [{:__MODULE__, _, _}] ->
              [{List.last(state.current_module), state.current_module}]
          end

        new_aliases =
          for {to, from} <- alias_pairs,
              into: %{},
              do: {to, State.resolve_module_name(state, from)}

        state = State.add_aliases(state, new_aliases)
        emit_event.({:alias, new_aliases}, expr, state)
        {expr, state}

      # import A
      # import A, only: [foo: 1, bar: 2]
      {:import, _, [{:__aliases__, _, names} | _]} = expr, state ->
        unalias_name = State.resolve_module_name(state, names)
        state = State.add_import(state, expr, unalias_name)
        emit_event.({:import, unalias_name}, expr, state)

      # require A
      # require A, only: [foo: 1, bar: 2]
      {:require, _, [{:__aliases__, _, names} | _]} = expr, state ->
        unalias_name = State.resolve_module_name(state, names)
        state = State.add_require(state, expr, unalias_name)
        emit_event.({:require, unalias_name}, expr, state)

      # Other expressions
      expr, state ->
        emit_event.(:expression, expr, state)
    end

    post = fn
      # Exit module
      {:defmodule, _, [{:__aliases__, _, _names}, _]} = expr, state ->
        current_module = State.current_module(state)
        {next_expr, state} = emit_event.({:exit_module, current_module}, expr, state)
        state = state |> State.pop_module() |> State.pop_frame()

        {next_expr, state}

      {atom, _, [_, [do: _function_body]]} = expr, state when atom in [:def, :defp] ->
        emit_event.(:exit_function, expr, state)

      # Other expressions
      expr, state ->
        {expr, state}
    end

    {_, state} = Macro.traverse(ast, %State{user_acc: user_init_acc}, pre, post)

    state.user_acc
  catch
    # Early return
    {:halt, user_acc} -> user_acc
  end

  def current_imports(state), do: Enum.flat_map(state.imports, & &1)
  def current_requires(state), do: Enum.flat_map(state.requires, & &1)
  defdelegate current_module(state), to: State
end
