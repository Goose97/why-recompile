defmodule WhyRecompile.SourceParser do
  @moduledoc """
  Find expressions in module by scanning source code AST
  """

  alias WhyRecompile.Parser

  @doc """
  Given a source file and a module, returns all import expressions originate from that module
  """
  @spec scan_module_exprs(WhyRecompile.file_path(), atom(), :import | :require) :: [Macro.t()]
  def scan_module_exprs(source_file, module, expr) do
    with {:ok, bin} <- File.read(source_file),
         {:ok, quoted} <- Code.string_to_quoted(bin) do
      result =
        Parser.parse(quoted, fn
          {:exit_module, exit_module}, _, state, _ ->
            if exit_module == module do
              result =
                case expr do
                  :import -> Parser.current_imports(state)
                  :require -> Parser.current_requires(state)
                end

              {:halt, result}
            else
              {:cont, nil}
            end

          _, _, _, _ ->
            {:cont, nil}
        end)

      result || []
    else
      {:error, :enoent} ->
        raise RuntimeError,
          message: """
          #{__MODULE__}.scan_module_exprs: source file not found
          - source_file: #{source_file}
          """

      {:error, :not_found} ->
        # Some module are not explicitly defined in the source file
        # For example, when implementing a protocol, a module is implicitly created
        []
    end
  end

  @doc """
  Find all struct usages in a source file, supports selective filters
  """
  def struct_expr(source_file, filter_structs) when is_binary(source_file) do
    {:ok, bin} = File.read(source_file)
    {:ok, quoted} = Code.string_to_quoted(bin)

    Parser.parse(quoted, [], fn
      # We are looking for struct literal %A{a: 1, b: 2}
      :expression, {:%, _, [module, _content]} = expr, state, acc ->
        unalias_name =
          case module do
            {:__aliases__, _, names} ->
              Parser.State.resolve_module_name(state, names)
              |> Module.concat()

            _ ->
              module
          end

        acc = if unalias_name in filter_structs, do: acc ++ [expr], else: acc
        {:cont, acc}

      _, _, _, acc ->
        {:cont, acc}
    end)
  end

  @spec struct_defs(WhyRecompile.file_path()) :: [Macro.t()]
  @doc """
  Given a source file, return all struct defnitions in that file
  """
  def struct_defs(source_file) do
    {:ok, bin} = File.read(source_file)
    {:ok, quoted} = Code.string_to_quoted(bin)

    Parser.parse(quoted, [], fn
      :expression, {:defstruct, _, _} = expr, state, acc ->
        current_module = Parser.current_module(state)
        new_struct_def = {current_module, expr}
        {:cont, acc ++ [new_struct_def]}

      :expression, {:def, _, _}, _, acc ->
        {:skip, acc}

      :expression, {:defp, _, _}, _, acc ->
        {:skip, acc}

      _, _, _, acc ->
        {:cont, acc}
    end)
  end

  @spec macro_exprs(WhyRecompile.file_path(), atom()) :: [Macro.t()]
  @doc """
  Given a source file and a module contains macro definitions, return all macro expressions in
  the source file
  """
  def macro_exprs(source_file, macro_module) do
    {:ok, bin} = File.read(source_file)
    {:ok, quoted} = Code.string_to_quoted(bin)
    macros = macro_module.__info__(:macros)

    Parser.parse(quoted, [], fn
      # We are looking for dot construct like A.A1.macro()
      :expression, {{:., _, [module, accessor]}, _, args} = expr, state, acc ->
        unalias_name =
          case module do
            {:__aliases__, _, names} ->
              Parser.State.resolve_module_name(state, names)
              |> Module.concat()

            _ ->
              module
          end

        import_modules = Parser.current_imports(state) |> Enum.map(& &1.module)
        require_modules = Parser.current_requires(state) |> Enum.map(& &1.module)

        # We must ensure both the name and the arity of the macro match, also the module
        # must be require or import beforehand
        imported_or_required = macro_module in import_modules or macro_module in require_modules
        args_length = if args, do: length(args), else: 0

        acc =
          if imported_or_required and unalias_name == macro_module and
               {accessor, args_length} in macros,
             do: acc ++ [expr],
             else: acc

        {:cont, acc}

      # or directly invoke macro() (through import)
      :expression, {variable, _, args} = expr, state, acc when is_atom(variable) ->
        args_length = if args, do: length(args), else: 0
        import_modules = Parser.current_imports(state) |> Enum.map(& &1.module)

        acc =
          if macro_module in import_modules and {variable, args_length} in macros,
            do: acc ++ [expr],
            else: acc

        {:cont, acc}

      _, _, _, acc ->
        {:cont, acc}
    end)
  end

  @spec compile_invocation_exprs(WhyRecompile.file_path(), atom()) :: [Macro.t()]
  @doc """
  Given a source file and a module, return all invocation of module functions during compile-time in
  the source file
  """
  def compile_invocation_exprs(source_file, sink_module) do
    {:ok, bin} = File.read(source_file)
    {:ok, quoted} = Code.string_to_quoted(bin)
    functions = sink_module.__info__(:functions)

    Parser.parse(quoted, [], fn
      # We are looking for dot construct like A.A1.function()
      :expression, {{:., _, [module, accessor]}, _, args} = expr, state, acc ->
        unalias_name =
          case module do
            {:__aliases__, _, names} ->
              Parser.State.resolve_module_name(state, names)
              |> Module.concat()

            _ ->
              module
          end

        args_length = if args, do: length(args), else: 0

        acc =
          if unalias_name == sink_module and {accessor, args_length} in functions,
            do: acc ++ [expr],
            else: acc

        {:cont, acc}

      # or directly invoke function() (through import)
      :expression, {variable, _, args} = expr, state, acc when is_atom(variable) ->
        args_length = if args, do: length(args), else: 0
        import_modules = Parser.current_imports(state) |> Enum.map(& &1.module)

        acc =
          if sink_module in import_modules and {variable, args_length} in functions,
            do: acc ++ [expr],
            else: acc

        {:cont, acc}

      # Once we enter a function, we skip the rest of the function body since
      # it's not compile-time anymore
      :enter_function, _, _, acc ->
        {:skip, acc}

      _, _, _, acc ->
        {:cont, acc}
    end)
  end

  @doc """
  Returns the lines span in the source file of a given expression
  """
  @spec expr_lines_span(Macro.t()) :: {non_neg_integer(), non_neg_integer()}
  def expr_lines_span({:import, context, _}) do
    start = context[:line]
    {start, start}
  end

  # Struct expression
  def expr_lines_span({:%, context, _}) do
    start = context[:line]
    {start, start}
  end

  # Functions/macros invocations or property accesses
  def expr_lines_span({{:., _, _}, context, _}) do
    start = context[:line]
    {start, start}
  end

  def expr_lines_span({variable, context, _}) when is_atom(variable) do
    start = context[:line]
    {start, start}
  end
end
