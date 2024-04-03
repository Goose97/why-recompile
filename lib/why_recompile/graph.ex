defmodule WhyRecompile.Graph do
  @moduledoc """
  Represents dependencies between source files as a labeled directed graph
  """

  alias WhyRecompile.Manifest

  @type dependency_type :: :compile | :exports | :runtime
  @type edge :: %{
          from: WhyRecompile.file_path(),
          to: WhyRecompile.file_path(),
          dependency_type: dependency_type
        }

  @spec build(manifest :: binary()) :: :digraph.graph()
  def build(manifest) do
    graph = :digraph.new()
    manifest_lookup = Manifest.build_lookup_table(manifest)
    sourceFiles = Manifest.all_source_files(manifest_lookup)

    Enum.each(sourceFiles, fn sourceFile ->
      :digraph.add_vertex(graph, sourceFile.path)
    end)

    Enum.each(sourceFiles, fn sourceFile ->
      :digraph.add_vertex(graph, sourceFile.path)

      Enum.each(
        sourceFile.compile_references,
        fn module ->
          with {:ok, %{source_paths: source_paths}} <-
                 Manifest.lookup_module(manifest_lookup, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, sourceFile.path, &1, :compile))
          end
        end
      )

      Enum.each(
        sourceFile.export_references,
        fn module ->
          with {:ok, %{source_paths: source_paths}} <-
                 Manifest.lookup_module(manifest_lookup, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, sourceFile.path, &1, :exports))
          end
        end
      )

      Enum.each(
        sourceFile.runtime_references,
        fn module ->
          with {:ok, %{source_paths: source_paths}} <-
                 Manifest.lookup_module(manifest_lookup, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, sourceFile.path, &1, :runtime))
          end
        end
      )
    end)

    graph
  end

  @spec summarize(:digraph.graph()) :: [%{id: WhyRecompile.file_path(), edges: [edge]}]
  def summarize(graph) do
    :digraph.vertices(graph)
    |> Enum.map(fn vertex ->
      edges =
        for e <- :digraph.out_edges(graph, vertex) do
          {_, from_vertex, to_vertex, label} = :digraph.edge(graph, e)
          %{from: from_vertex, to: to_vertex, dependency_type: label}
        end

      %{id: vertex, edges: edges}
    end)
  end
end
