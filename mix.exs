defmodule WhyRecompile.MixProject do
  use Mix.Project

  def project do
    [
      app: :why_recompile,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Terminal UI application to explore module dependencies graph",
      package: [
        exclude_patterns: ["lib/fixtures"],
        licenses: ["Apache-2.0"],
        links: %{"Github" => "https://github.com/Goose97/why-recompile"}
      ],
      releases: releases(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {WhyRecompile.Application, []},
      extra_applications: [:logger, :cowboy]
    ]
  end

  defp releases() do
    [
      why_recompile: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            # macos_intel: [os: :darwin, cpu: :x86_64],
            macos_arm: [os: :darwin, cpu: :aarch64],
            # linux: [os: :linux, cpu: :x86_64],
            # windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp aliases do
    [
      test: ["test --no-start"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "test/fixtures/lib"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cowboy, "~> 2.0"},
      {:plug, "~> 1.14"},
      {:plug_cowboy, "~> 2.4"},
      {:jason, "~> 1.0"},
      # {:orange, "~> 0.4.0"},
      {:orange, path: "../orange"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:burrito, "~> 1.0"}
    ]
  end
end
