defmodule WhyRecompile.Dependency do
  @moduledoc """
  Module contains API to answer queries based on the dependencies graph

  ## Recompile dependencies
  Given two files A and B, we state that A has a recompile dependency to B iff when B
  recompiles, A must recompiles as well.

  Recompile dependencies can be formed in these scenarios:
  1. A has a compile dependency to B
  2. A has a compile-then-runtime dependency to B (A has a compile dependency to A1 and A1
  has a runtime dependency to B)
  3. A has a exports dependency to B
  4. A has a exports-then-compile dependency to B (A has a exports dependency to A1 and A1
  has a compile dependency to B)

  There are two types of recompile dependencies, definite and indefinite.

  - Definite dependencies mean if the target file recompiles, the source file will DEFINITELY
  recompile. Scenario 1 and 2 above fell into this type.
  - Indefinite dependencies mean if the target file recompiles, the source file MAY or MAY NOT
  recompile. This is because exports dependencies depend on modules API, namely structs and
  public functions. So when a target file recompiles, but its struct definitions and public
  functions don't change, the source file won't recompile. Scenario 3 and 4 above fell into this type.
  """

  alias WhyRecompile.{SourceFile, Manifest, SourceParser}
  @type dependency_type :: :compile | :exports | :runtime
  @type dependency_reason :: :compile | :exports_then_compile | :exports | :compile_then_runtime

  @doc """
  Returns all files which have a recompile dependency to the target file
  """
  @spec recompile_dependencies(:digraph.graph(), WhyRecompile.file_path()) :: %{
          compile: [{WhyRecompile.file_path(), dependency_path}],
          exports_then_compile: [{WhyRecompile.file_path(), dependency_path}],
          exports: [{WhyRecompile.file_path(), dependency_path}],
          compile_then_runtime: [{WhyRecompile.file_path(), dependency_path}]
        }
  def recompile_dependencies(graph, target_file) do
    compile_sources = find_source_files(graph, target_file, :compile)

    exports_then_compile_sources =
      Enum.reduce(compile_sources, [], fn {file, path}, acc ->
        result =
          find_source_files(graph, file, :exports, direct_only?: true)
          |> Enum.map(fn {file1, path1} -> {file1, path1 ++ path} end)

        acc ++ result
      end)
      |> Enum.reject(&(elem(&1, 0) == target_file))

    exports_sources = find_source_files(graph, target_file, :exports, direct_only?: true)

    compile_then_runtime_sources =
      find_source_files(graph, target_file, :runtime)
      |> Enum.reduce([], fn {file, path}, acc ->
        result =
          find_source_files(graph, file, :compile)
          |> Enum.map(fn {file1, path1} -> {file1, path1 ++ path} end)

        acc ++ result
      end)
      |> Enum.reject(&(elem(&1, 0) == target_file))

    %{
      compile: compile_sources,
      exports_then_compile: exports_then_compile_sources,
      exports: exports_sources,
      compile_then_runtime: compile_then_runtime_sources
    }
  end

  @type dependency_path :: [{dependency_type, WhyRecompile.file_path()}]
  @spec find_source_files(:digraph.graph(), binary(), dependency_type, direct_only?: boolean) ::
          [{WhyRecompile.file_path(), dependency_path}]
  @doc """
  Given a sink file and a graph, find all source files which have a dependency_type on the sink file

  ## Options

    * `direct_only?`: whether to count only direct dependency or include transitive ones. Default: true
  """
  def find_source_files(graph, sink_file, dependency_type, opts \\ []) do
    find_source_files(graph, sink_file, dependency_type, {%{}, sink_file, []}, opts)
    |> Enum.to_list()
  end

  defp find_source_files(graph, sink_file, dependency_type, state, opts) do
    {result, initial_vertex, path} = state
    direct_only? = Keyword.get(opts, :direct_only?, false)

    source_files =
      :digraph.in_edges(graph, sink_file)
      |> Enum.flat_map(fn edge ->
        case :digraph.edge(graph, edge) do
          {_, source, _, ^dependency_type} ->
            # Ignore visited vertex and our inital vertex. Otherwise, we go into a infinite loop
            if Map.has_key?(result, source) or source == initial_vertex,
              do: [],
              else: [source]

          _ ->
            []
        end
      end)

    result =
      Enum.reduce(source_files, result, fn file, acc ->
        path = [{dependency_type, file} | path]
        Map.put(acc, file, path)
      end)

    if direct_only?,
      do: result,
      else:
        Enum.reduce(
          source_files,
          result,
          fn file, acc ->
            path = [{dependency_type, file} | path]
            find_source_files(graph, file, dependency_type, {acc, initial_vertex, path}, opts)
          end
        )
  end

  @type dependency_causes_params :: %{
          source_file: WhyRecompile.file_path(),
          sink_file: WhyRecompile.file_path(),
          manifest: binary(),
          dependency_type: WhyRecompile.dependency_type()
        }
  @spec dependency_causes(dependency_causes_params()) :: [
          __MODULE__.Cause.t()
        ]

  @doc """
  Given two files and their dependency type, return all the causes for such dependency

  Note that this function only accepts direct dependencies
  """
  # There are 3 sources of exports dependency causes: 1) import , 2) require and 3) struct usage
  def dependency_causes(%{dependency_type: :exports} = params) do
    %{
      source_file: source_file,
      sink_file: sink_file,
      manifest: manifest
    } = params

    absolute_source_file =
      if params[:root_folder],
        do: Path.join([params[:root_folder], source_file]),
        else: source_file

    absolute_sink_file =
      if params[:root_folder],
        do: Path.join([params[:root_folder], sink_file]),
        else: sink_file

    struct_defs =
      for {struct_name, _} <- SourceParser.struct_defs(absolute_sink_file), do: struct_name

    # It's possible that we can't find the struct expression. For example, when using macro
    # to generate struct expressions
    struct_usages =
      for struct_usage <- SourceParser.struct_expr(absolute_source_file, struct_defs) do
        %__MODULE__.Cause{
          name: :struct_usage,
          origin_file: source_file,
          lines_span: SourceParser.expr_lines_span(struct_usage)
        }
      end

    import_or_require =
      import_or_require_causes(manifest, source_file, sink_file, root_folder: params[:root_folder])

    import_or_require ++ struct_usages
  end

  # TODO: compile dependency because behavior
  def dependency_causes(%{dependency_type: :compile} = params) do
    %{
      source_file: source_file,
      sink_file: sink_file,
      manifest: manifest
    } = params

    file_lookup_table = WhyRecompile.SourceFile.build_lookup_table(manifest)
    %{modules: source_modules} = SourceFile.lookup!(file_lookup_table, source_file)

    absolute_source_file =
      if params[:root_folder],
        do: Path.join([params[:root_folder], source_file]),
        else: source_file

    require_list =
      Enum.flat_map(source_modules, fn module ->
        SourceParser.scan_module_exprs(absolute_source_file, module, :require)
        |> Enum.map(& &1.module)
      end)

    import_list =
      Enum.flat_map(source_modules, fn module ->
        SourceParser.scan_module_exprs(absolute_source_file, module, :import)
        |> Enum.map(& &1.module)
      end)

    # This is a minor optimization. We could check if our sink module gets import/require
    # If it's not, then we are sure that there're no macro usages
    %{modules: sink_modules} = SourceFile.lookup!(file_lookup_table, sink_file)

    macro_causes =
      Enum.filter(sink_modules, &(&1 in require_list or &1 in import_list))
      |> Enum.flat_map(fn module ->
        SourceParser.macro_exprs(absolute_source_file, module)
      end)
      |> Enum.map(fn expr ->
        %__MODULE__.Cause{
          name: :macro,
          origin_file: source_file,
          lines_span: SourceParser.expr_lines_span(expr)
        }
      end)

    compile_time_invocation_causes =
      Enum.flat_map(sink_modules, fn module ->
        SourceParser.compile_invocation_exprs(absolute_source_file, module)
      end)
      |> Enum.map(fn expr ->
        %__MODULE__.Cause{
          name: :compile_time_invocation,
          origin_file: source_file,
          lines_span: SourceParser.expr_lines_span(expr)
        }
      end)

    macro_causes ++ compile_time_invocation_causes
  end

  defp import_or_require_causes(manifest, source_file, sink_file, opts) do
    file_lookup_table = WhyRecompile.SourceFile.build_lookup_table(manifest)
    manifest_lookup_table = Manifest.build_lookup_table(manifest)

    %{modules: modules} = SourceFile.lookup!(file_lookup_table, source_file)

    absolute_source_file =
      if opts[:root_folder],
        do: Path.join([opts[:root_folder], source_file]),
        else: source_file

    import_or_require_exprs =
      Enum.flat_map(modules, fn module ->
        import_exprs =
          SourceParser.scan_module_exprs(absolute_source_file, module, :import)
          |> Enum.uniq_by(& &1.module)
          |> Enum.map(fn %{expr: expr, module: target_module} ->
            case Manifest.lookup_module(manifest_lookup_table, target_module) do
              {:ok, %{source_paths: source_paths}} ->
                {expr, source_paths}

              _ ->
                nil
            end
          end)

        require_exprs =
          SourceParser.scan_module_exprs(absolute_source_file, module, :require)
          |> Enum.uniq_by(& &1.module)
          |> Enum.map(fn %{expr: expr, module: target_module} ->
            case Manifest.lookup_module(manifest_lookup_table, target_module) do
              {:ok, %{source_paths: source_paths}} ->
                {expr, source_paths}

              _ ->
                nil
            end
          end)

        Enum.reject(import_exprs ++ require_exprs, &is_nil/1)
      end)

    Enum.flat_map(import_or_require_exprs, fn
      {expr, sink_files} ->
        if sink_file in sink_files,
          do: [
            %__MODULE__.Cause{
              name: :import,
              origin_file: source_file,
              lines_span: SourceParser.expr_lines_span(expr)
            }
          ],
          else: []

      _ ->
        []
    end)
  end
end
