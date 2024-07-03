defmodule WhyRecompile.MixProject do
  use Mix.Project

  @source_url "https://github.com/Goose97/why-recompile"

  def project do
    [
      app: :why_recompile,
      version: "0.1.2",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Mix tasks to explore module dependencies graph",
      package: [
        exclude_patterns: ["lib/fixtures"],
        licenses: ["Apache-2.0"],
        links: %{"Github" => "https://github.com/Goose97/why-recompile"}
      ],
      aliases: aliases(),
      package: package()
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/fixtures/lib"]
  defp elixirc_paths(_), do: ["lib"]

  defp package() do
    [
      maintainers: ["Nguyễn Văn Đức"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
