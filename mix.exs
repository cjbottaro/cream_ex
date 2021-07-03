defmodule Cream.Mixfile do
  use Mix.Project

  def project do
    [app: :cream,
     version: "0.2.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     elixirc_paths: elixirc_paths(Mix.env),
     deps: deps(),

      # Hex
      description: "Dalli compatible memcached client with cluster support.",
      package: [
        maintainers: ["Christopher J. Bottaro"],
        licenses: ["GNU General Public License v3.0"],
        links: %{"GitHub" => "https://github.com/cjbottaro/cream_ex"},
      ],

     docs: [
       main: "readme",
       extras: [
         "README.md": [title: "README"],
         "CHANGELOG.md": [title: "CHANGELOG"]
       ]
     ]
   ]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
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
      extra_applications: [:logger, :crypto],
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
      {:telemetry, "~> 0.4.2"},
      {:connection, "~> 1.0"},
      {:nimble_pool, "~> 0.0"},
      {:jason, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.0", only: :dev},
    ]
  end
end
