defmodule Cream.Mixfile do
  use Mix.Project

  def project do
    [app: :cream,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps()]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(:dev) do
    ["lib", "test/support/schemas"]
  end

  defp elixirc_paths(_) do
    ["lib"]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [
      # Specify extra applications you'll use from Erlang/Elixir
      extra_applications: [:logger],
      mod: {Cream.Application, []}
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:ecto, ">= 2.0.0"},
      {:postgrex, "~> 0.12"},
      {:memcachex, "~> 0.2.1"},
      {:uuid, "~> 1.1"},
      {:poison, "~> 2.0"},
      {:jiffy, "~> 0.14.0"}
    ]
  end
end
