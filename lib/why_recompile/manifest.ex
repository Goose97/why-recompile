defmodule WhyRecompile.Manifest do
  @moduledoc """
  Module contains utilities to quickly query the manifest file
  """

  @spec parse(WhyRecompile.file_path()) ::
          {%{atom() => WhyRecompile.Module.t()}, %{binary() => WhyRecompile.SourceFile.t()}}
  def parse(manifest) do
    {modules, sources} = read_manifest(manifest)
    {to_modules_map(modules), to_source_files_map(sources)}
  end

  version = System.version()
  regex = ~r/^(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)/
  %{"major" => major, "minor" => minor, "patch" => patch} = Regex.named_captures(regex, version)
  version_triplet = {String.to_integer(major), String.to_integer(minor), String.to_integer(patch)}

  if version_triplet >= {1, 16, 0} do
    require Mix.Compilers.Elixir

    defp to_modules_map(records) do
      for {module, record} <- records, into: %{} do
        Mix.Compilers.Elixir.module(sources: sources) = record

        struct = %WhyRecompile.Module{
          module: module,
          source_paths: sources
        }

        {module, struct}
      end
    end

    defp to_source_files_map(records) do
      for {path, record} <- records, into: %{} do
        Mix.Compilers.Elixir.source(
          modules: modules,
          compile_references: compile_references,
          export_references: export_references,
          runtime_references: runtime_references
        ) = record

        struct = %WhyRecompile.SourceFile{
          path: path,
          modules: modules,
          compile_references: compile_references,
          export_references: export_references,
          runtime_references: runtime_references
        }

        {path, struct}
      end
    end
  else
    require Mix.Compilers.Elixir

    defp to_modules_map(records) do
      for record <- records, into: %{} do
        Mix.Compilers.Elixir.module(module: module, sources: sources) = record

        struct = %WhyRecompile.Module{
          module: module,
          source_paths: sources
        }

        {module, struct}
      end
    end

    defp to_source_files_map(records) do
      for record <- records, into: %{} do
        Mix.Compilers.Elixir.source(
          source: path,
          modules: modules,
          compile_references: compile_references,
          export_references: export_references,
          runtime_references: runtime_references
        ) = record

        struct = %WhyRecompile.SourceFile{
          path: path,
          modules: modules,
          compile_references: compile_references,
          export_references: export_references,
          runtime_references: runtime_references
        }

        {path, struct}
      end
    end
  end

  # Copy from Mix.Compilers.Elixir module
  def read_manifest(manifest) do
    result = manifest |> File.read!() |> :erlang.binary_to_term()
    {elem(result, 1), elem(result, 2)}
  end
end
