defmodule Mix.Tasks.WhyRecompileTest do
  use ExUnit.Case

  @project_name "why_recompile_tasks_test"

  setup_all do
    File.rm_rf!(@project_name)
    on_exit(fn -> File.rm_rf!(@project_name) end)

    ExUnit.CaptureIO.capture_io(fn -> Mix.Task.run("new", [@project_name]) end)
    Path.join([@project_name, "lib", "#{@project_name}.ex"]) |> File.rm!()

    File.write!("#{@project_name}/mix.exs", """
      defmodule WhyRecompileTest.MixProject do
        use Mix.Project

        def project do
          [
            app: :#{@project_name},
            version: "0.1.0",
            elixir: "~> 1.11",
            start_permanent: Mix.env() == :prod,
            deps: deps()
          ]
        end

        defp deps do
          [
            {:why_recompile, path: "../"}
          ]
        end
      end
    """)

    source_file("A.ex", """
      defmodule A do
        defmacro x do
          1
        end
      end
    """)

    source_file("B.ex", """
      defmodule B do
        require A

        def y do
          A.x()
        end
      end
    """)

    source_file("C.ex", """
      defmodule C do
        require A

        def y do
          A.x()
        end

        def z do
          1
        end
      end
    """)

    source_file("D.ex", """
      defmodule D do
        C.z()
      end
    """)
  end

  defp source_file(name, content), do: File.write!("#{@project_name}/lib/#{name}", content)

  describe "mix why_recompile list" do
    test "Plain command" do
      result = :os.cmd('cd #{@project_name} && mix why_recompile list')

      table = """
      ------------+-----------------------------+----------------------------------
       File path  | Number of recompile files   | Number of MAYBE recompile files  
      ------------+-----------------------------+----------------------------------
       lib/A.ex   | 3                           | 2                                
       lib/C.ex   | 1                           | 0                                
      ------------+-----------------------------+----------------------------------\
      """

      assert to_string(result) |> String.contains?(table)
    end

    test "Command with --all/-a option" do
      result1 = :os.cmd('cd #{@project_name} && mix why_recompile list --all')
      result2 = :os.cmd('cd #{@project_name} && mix why_recompile list -a')

      table = """
      ------------+-----------------------------+----------------------------------
       File path  | Number of recompile files   | Number of MAYBE recompile files  
      ------------+-----------------------------+----------------------------------
       lib/A.ex   | 3                           | 2                                
       lib/C.ex   | 1                           | 0                                
       lib/D.ex   | 0                           | 0                                
       lib/B.ex   | 0                           | 0                                
      ------------+-----------------------------+----------------------------------\
      """

      assert to_string(result1) |> String.contains?(table)
      assert to_string(result2) |> String.contains?(table)
    end

    test "Command with --limit/-l option" do
      result1 = :os.cmd('cd #{@project_name} && mix why_recompile list --limit 1')
      result2 = :os.cmd('cd #{@project_name} && mix why_recompile list -l 1')

      table = """
      ------------+-----------------------------+----------------------------------
       File path  | Number of recompile files   | Number of MAYBE recompile files  
      ------------+-----------------------------+----------------------------------
       lib/A.ex   | 3                           | 2                                
      ------------+-----------------------------+----------------------------------\
      """

      assert to_string(result1) |> String.contains?(table)
      assert to_string(result2) |> String.contains?(table)
    end
  end

  describe "mix why_recompile show" do
    test "Plain command" do
      result = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex')

      output = """
      lib/B.ex
      lib/C.ex
      lib/D.ex\
      """

      assert to_string(result) |> strip_ansi_code() |> String.contains?(output)
    end

    test "Command with --include-soft option" do
      result = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex --include-soft')

      output = """
      Hard dependencies:
      lib/B.ex
      lib/C.ex
      lib/D.ex

      Soft dependencies:
      lib/B.ex
      lib/C.ex\
      """

      assert to_string(result) |> strip_ansi_code() |> String.contains?(output)
    end

    test "Command with --filter/-f option" do
      result1 = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex --filter C.ex')
      result2 = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex -f C.ex')

      check_result = fn result ->
        result = result |> to_string() |> strip_ansi_code()
        assert String.contains?(result, "lib/C.ex")
        refute String.contains?(result, "lib/B.ex")
        refute String.contains?(result, "lib/D.ex")
      end

      check_result.(result1)
      check_result.(result2)
    end

    test "Command with --verbose/-v=1 option" do
      result1 =
        :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex -f C.ex --verbose=1')

      result2 = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex -f C.ex -v=1')

      output = """
      lib/C.ex
        │
        │ compile
        │
        └─➤ lib/A.ex
      """

      assert to_string(result1) |> strip_ansi_code() |> String.contains?(output)
      assert to_string(result2) |> strip_ansi_code() |> String.contains?(output)
    end

    test "Command with --verbose/-v=2 option" do
      result1 =
        :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex -f C.ex --verbose=2')

      result2 = :os.cmd('cd #{@project_name} && mix why_recompile show lib/A.ex -f C.ex -v=2')

      output = """
      lib/C.ex
        │
        │ compile
        │
        └─➤ lib/A.ex

        1. lib/C.ex ────➤ lib/A.ex (compile)
          -- lib/C.ex
          1     defmodule C do
          2       require A
          3   
          4       def y do
          5         A.x()
          6       end
          7   
          8       def z do
          9         1
          10      end
      """

      assert to_string(result1) |> strip_ansi_code() |> String.contains?(output)
      assert to_string(result2) |> strip_ansi_code() |> String.contains?(output)

      # Assert on the highlighted lines
      assert to_string(result1) |> String.contains?("#{IO.ANSI.green()}5         A.x()")
      assert to_string(result2) |> String.contains?("#{IO.ANSI.green()}5         A.x()")
    end

    test "File not found" do
      result = :os.cmd('cd #{@project_name} && mix why_recompile show lib/NotFound.ex')

      output = "File not found: lib/NotFound.ex"

      assert to_string(result) |> strip_ansi_code() |> String.contains?(output)
    end
  end

  defp strip_ansi_code(string) do
    # A make-shift way to strip ANSI codes from a string
    # ANSI sequence is much more complex than this, but this is good enough for our use case
    ansi_regex = ~r/(\x9B|\x1B\[)[0-?]*[ -\/]*[@-~]/
    Regex.replace(ansi_regex, string, "")
  end
end
