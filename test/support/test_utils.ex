defmodule WhyRecompile.TestUtils do
  @manifest "compile.elixir"
  @fixture_lib "test/fixtures"

  def write_source(source, path) do
    path = fixtures_path(path)
    Path.dirname(path) |> File.mkdir_p!()
    File.write!(path, source)
  end

  def fixtures_path(path), do: Path.join([@fixture_lib, path])

  defp fixtures_path, do: Path.join([File.cwd!(), "test", "fixtures"])

  def compile_fixtures() do
    ref = make_ref()

    exit_code =
      Mix.Shell.cmd("mix elixir.compile", [cd: fixtures_path()], fn output ->
        send(self(), {ref, output})
      end)

    if exit_code == 0, do: :ok, else: {:error, receive_stream_response(ref)}
  end

  def clear_fixtures() do
    with :ok <- clear_source_folder(),
         :ok <- clear_build_artifacts() do
      :ok
    end
  end

  defp clear_source_folder() do
    lib_folder = Path.join([@fixture_lib, "lib"])

    with {:ok, _} <- File.rm_rf(lib_folder),
         :ok <- File.mkdir_p(lib_folder) do
      :ok
    end
  end

  defp clear_build_artifacts() do
    ref = make_ref()

    exit_code =
      Mix.Shell.cmd("mix clean", [cd: fixtures_path()], fn output ->
        send(self(), {ref, output})
      end)

    if exit_code == 0, do: :ok, else: {:error, receive_stream_response(ref)}
  end

  def add_load_path() do
    case run_mix_shell(~s/mix run -e "Mix.Project.compile_path() |> Mix.Shell.IO.info()"/) do
      {:ok, output} ->
        compile_path =
          output
          |> String.trim_trailing()
          |> String.split("\n")
          |> List.last()

        :code.add_path(String.to_charlist(compile_path))
        :ok

      {:error, output} ->
        {:error, output}
    end
  end

  def fixtures_manifest() do
    case run_mix_shell(~s/mix run -e "Mix.Project.manifest_path() |> Mix.Shell.IO.info()"/) do
      {:ok, output} ->
        manifest_path =
          output
          |> String.trim_trailing()
          |> String.split("\n")
          |> List.last()

        {:ok, Path.join([manifest_path, @manifest])}

      {:error, output} ->
        {:error, output}
    end
  end

  defp run_mix_shell(command) do
    ref = make_ref()

    exit_code =
      Mix.Shell.cmd(
        command,
        [cd: fixtures_path()],
        fn output -> send(self(), {ref, output}) end
      )

    output = receive_stream_response(ref)
    if exit_code == 0, do: {:ok, output}, else: {:error, output}
  end

  defp receive_stream_response(ref, buffer \\ []) do
    receive do
      {^ref, output} -> receive_stream_response(ref, [buffer | output])
    after
      0 -> IO.iodata_to_binary(buffer)
    end
  end
end
