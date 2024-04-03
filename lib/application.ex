defmodule WhyRecompile.Application do
  use Application

  def start(_type, _args) do
    Task.start_link(fn ->
      # Will blocked here until users quit the application
      WhyRecompile.start()
      System.halt(0)
    end)
  end
end
