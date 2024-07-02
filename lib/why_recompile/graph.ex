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

  def build(manifest) do
    graph = :digraph.new()
    {modules_map, source_files_map} = Manifest.parse(manifest)

    Enum.each(source_files_map, fn {_, source_file} ->
      :digraph.add_vertex(graph, source_file.path)
    end)

    Enum.each(source_files_map, fn {_, source_file} ->
      :digraph.add_vertex(graph, source_file.path)

      Enum.each(
        source_file.compile_references,
        fn module ->
          with %{source_paths: source_paths} <- Map.get(modules_map, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, source_file.path, &1, :compile))
          end
        end
      )

      Enum.each(
        source_file.export_references,
        fn module ->
          with %{source_paths: source_paths} <- Map.get(modules_map, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, source_file.path, &1, :exports))
          end
        end
      )

      Enum.each(
        source_file.runtime_references,
        fn module ->
          with %{source_paths: source_paths} <- Map.get(modules_map, module) do
            Enum.each(source_paths, &:digraph.add_edge(graph, source_file.path, &1, :runtime))
          end
        end
      )
    end)

    %{
      graph: graph,
      modules_map: modules_map,
      source_files_map: source_files_map
    }
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
