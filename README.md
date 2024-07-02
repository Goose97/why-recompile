[![Package](https://img.shields.io/badge/-Package-important)](https://hex.pm/packages/why_recompile)

A tool helps you answering the question: why editing this file cause 127 other files to recompile?

## Installation

The package can be installed by adding `why_recompile` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [{:why_recompile, "~> 0.1", only: [:dev], runtime: false}]
end
```

## Basic Usage

The package provides some Mix tasks to explore the recompile depedency graph of your project. To see the full commands documentation:

```
mix why_recompile help
```

### mix why_recompile list

List all files in the project sorted by number of recompile dependencies. If A is a recompile depedency of B, when B is recompiled, A must be recompiled as well.

> [!NOTE]
> There are two kind of dependencies. Given two files A and B:
> 1. Hard dependencies: if A is a hard depedency of B, when B is recompiled, A MUST be recompiled
> 1. Soft dependencies: if A is a hard depedency of B, when B is recompiled, A MIGHT have to recompiled
>
> An example for soft dependencies: when A uses struct from B, if B is recompiled but doesn't change the struct definition, A won't need to be recompiled. Otherwise, A needs to be recompiled.

```elixir
# List all files in the project
mix why_recompile list

# List all files in the project, include files with no dependencies
mix why_recompile list --all

# Only list top 5 files
mix why_recompile list --limit 5
```

### mix why_recompile show

Show all the recompile dependencies of a file and the detailed explanation of such depedency.

```elixir
# Provide the file path
mix why_recompile show lib/A.ex
```

You can increase the verbosity to see more details about the depedency.

```elixir
# Print the whole dependency chain
mix why_recompile show lib/A.ex --verbose 1

# Print the whole dependency chain and code snippets that cause the dependency
mix why_recompile show lib/A.ex --verbose 2
```

To filter by dependency name (support partial match):

```elixir
mix why_recompile show lib/A.ex --filter C.ex
```

To include soft dependencies:

```elixir
mix why_recompile show lib/A.ex --include-soft
```
