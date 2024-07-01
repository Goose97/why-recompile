defmodule WhyRecompile.ParserTest do
  use ExUnit.Case
  alias WhyRecompile.Parser

  describe "WhyRecompile.Parser.parse/3" do
    test "Emits :enter_module and :exit_module events" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule TrackModule do
          def x(), do: 1

          defmodule Nested do
            def y(), do: 2
          end
        end
        """)

      Parser.parse(ast, 0, fn
        {:enter_module, module_name}, _, state, 0 ->
          assert module_name == TrackModule
          assert Parser.current_module(state) == TrackModule
          {:cont, 1}

        {:enter_module, module_name}, _, state, 1 ->
          assert module_name == TrackModule.Nested
          assert Parser.current_module(state) == TrackModule.Nested
          {:cont, 2}

        {:exit_module, module_name}, _, state, 2 ->
          assert module_name == TrackModule.Nested
          assert Parser.current_module(state) == TrackModule.Nested
          {:cont, 3}

        {:exit_module, module_name}, _, state, 3 ->
          assert module_name == TrackModule
          assert Parser.current_module(state) == TrackModule
          {:cont, 4}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end

    test "Emits :enter_function and :exit_function events" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule TrackFunction do
          def x(), do: 1

          defmodule Nested do
            def y(), do: 2
          end
        end
        """)

      Parser.parse(ast, 0, fn
        :enter_function, expr, state, 0 ->
          assert {:def, _, [{:x, _, _}, _]} = expr
          assert Parser.current_module(state) == TrackFunction
          {:cont, 1}

        :enter_function, expr, state, 1 ->
          assert {:def, _, [{:y, _, _}, _]} = expr
          assert Parser.current_module(state) == TrackFunction.Nested
          {:cont, 2}

        :exit_function, expr, state, 2 ->
          assert {:def, _, [{:y, _, _}, _]} = expr
          assert Parser.current_module(state) == TrackFunction.Nested
          {:cont, 3}

        :exit_function, expr, state, 3 ->
          assert {:def, _, [{:x, _, _}, _]} = expr
          assert Parser.current_module(state) == TrackFunction
          {:cont, 4}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end

    test "Early return" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule EarlyReturn do
          def x(), do: 1

          defmodule Nested do
            def y(), do: 2
          end
        end
        """)

      acc =
        Parser.parse(ast, 0, fn
          {:enter_module, EarlyReturn}, _, _, 0 ->
            {:halt, 1}

          {:enter_module, EarlyReturn.Nested}, _, _, 1 ->
            {:cont, 2}

          _, _, _, acc ->
            {:cont, acc}
        end)

      assert acc == 1
    end

    test "Track import expressions" do
      {:ok, ast} =
        Code.string_to_quoted("""
        import A1

        defmodule Require do
          import A2

          def x(), do: 1

          import A3

          defmodule Nested do
            import A4

            def y(), do: 2
          end

          test = 222
        end

        test = 333
        """)

      Parser.parse(ast, 0, fn
        {:enter_module, Import}, _, state, 0 ->
          assert [A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 1}

        :enter_function, _, state, 1 ->
          assert [A2, A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 2}

        {:enter_module, Import.Nested}, _, state, 2 ->
          assert [A3, A2, A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 3}

        :enter_function, _, state, 3 ->
          assert [A4, A3, A2, A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 4}

        # test = 222
        :expression, {:=, _, [{:test, _, _}, 222]}, state, 4 ->
          assert [A3, A2, A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 5}

        # test = 333
        :expression, {:=, _, [{:test, _, _}, 333]}, state, 5 ->
          assert [A1] = Parser.current_imports(state) |> Enum.map(& &1.module)
          {:cont, 6}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end

    test "Track require expressions" do
      {:ok, ast} =
        Code.string_to_quoted("""
        require A1

        defmodule Require do
          require A2

          def x(), do: 1

          require A3

          defmodule Nested do
            require A4

            def y(), do: 2
          end

          test = 222
        end

        test = 333
        """)

      Parser.parse(ast, 0, fn
        {:enter_module, Require}, _, state, 0 ->
          assert [A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 1}

        :enter_function, _, state, 1 ->
          assert [A2, A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 2}

        {:enter_module, Require.Nested}, _, state, 2 ->
          assert [A3, A2, A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 3}

        :enter_function, _, state, 3 ->
          assert [A4, A3, A2, A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 4}

        # test = 222
        :expression, {:=, _, [{:test, _, _}, 222]}, state, 4 ->
          assert [A3, A2, A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 5}

        # test = 333
        :expression, {:=, _, [{:test, _, _}, 333]}, state, 5 ->
          assert [A1] = Parser.current_requires(state) |> Enum.map(& &1.module)
          {:cont, 6}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end

    test "Resolve __MODULE__ in module names" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule ResolveModule do
          def x(), do: 1

          defmodule Nested do
            def y(), do: 2

            __MODULE__.Again.y()
          end
        end
        """)

      Parser.parse(ast, fn
        # __MODULE__.y()
        :expression, {:., _, [module, :y]}, state, _ ->
          {:__aliases__, _, names} = module

          assert [:ResolveModule, :Nested, :Again] =
                   Parser.State.resolve_module_name(state, names)

          {:halt, nil}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end

    test "Resolve aliased module names" do
      {:ok, ast} =
        Code.string_to_quoted("""
        defmodule ResolveModule do
          alias A.B, as: C

          def x(), do: 1

          defmodule Nested do
            def y(), do: 2

            C.Again.y()
          end
        end
        """)

      Parser.parse(ast, fn
        # C.Again.y()
        :expression, {:., _, [module, :y]}, state, _ ->
          {:__aliases__, _, names} = module

          assert [:A, :B, :Again] = Parser.State.resolve_module_name(state, names)

          {:halt, nil}

        _, _, _, acc ->
          {:cont, acc}
      end)
    end
  end
end
