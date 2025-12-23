defmodule Jido.Character.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_character"

  def project do
    [
      app: :jido_character,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Package
      name: "Jido Character",
      description: description(),
      package: package(),

      # Documentation
      source_url: @source_url,
      homepage_url: "https://agentjido.xyz",
      docs: docs(),

      # Test coverage
      test_coverage: [tool: ExCoveralls, summary: [threshold: 90]],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  defp description do
    "Extensible character definition and context rendering for AI agents in the Jido ecosystem."
  end

  defp package do
    [
      name: "jido_character",
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/jido_character/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/jido_character",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md AGENTS.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Overview"},
        "CHANGELOG.md",
        "CONTRIBUTING.md"
      ],
      groups_for_modules: [
        Core: [
          Jido.Character,
          Jido.Character.Definition
        ],
        Schemas: [
          Jido.Character.Schema,
          Jido.Character.Schema.Identity,
          Jido.Character.Schema.Personality,
          Jido.Character.Schema.Voice,
          Jido.Character.Schema.Memory,
          Jido.Character.Schema.MemoryEntry,
          Jido.Character.Schema.KnowledgeItem,
          Jido.Character.Schema.Trait
        ],
        Rendering: [
          Jido.Character.Renderer,
          Jido.Character.Context.Renderer
        ],
        Persistence: [
          Jido.Character.Persistence.Adapter,
          Jido.Character.Persistence.Memory
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime dependencies
      {:zoi, "~> 0.14"},
      {:jason, "~> 1.4"},
      {:req_llm, "~> 1.2"},
      {:uniq, "~> 0.6"},

      # Dev/Test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "git_hooks.install"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ],
      q: ["quality"]
    ]
  end
end
