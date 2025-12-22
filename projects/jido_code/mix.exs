defmodule JidoCode.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_code,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "JidoCode",
      description: "Agentic Coding Assistant TUI built on Jido",
      source_url: "https://github.com/agentjido/jido_code",

      # CQ-4: Coverage configuration
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JidoCode.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jido, "~> 1.2"},
      {:jido_ai, path: "../jido_ai"},
      {:term_ui, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},

      # Lua sandbox for tool execution
      {:luerl, "~> 1.2"},

      # Knowledge graph
      {:rdf, "~> 2.0"},
      {:libgraph, "~> 0.16"},

      # Web tools
      {:floki, "~> 0.36"},

      # Development dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # CQ-4: Test coverage
      {:excoveralls, "~> 0.18", only: :test},

      # HTTP mocking for web tool tests
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
