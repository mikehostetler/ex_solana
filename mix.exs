defmodule Karo.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/karo"

  def project do
    [
      app: :karo,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Package
      name: "Karo",
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
    "A persistent AI agent for Elixir applications with Discord integration, conversation memory, and scheduled actions."
  end

  defp package do
    [
      name: "karo",
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Changelog" => "https://hexdocs.pm/karo/changelog.html",
        "Discord" => "https://agentjido.xyz/discord",
        "Documentation" => "https://hexdocs.pm/karo",
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
          Karo,
          Karo.Governor,
          Karo.ChatSession
        ],
        Persistence: [
          Karo.Repo,
          Karo.ChatDomain,
          Karo.Resources.Conversation,
          Karo.Resources.Message,
          Karo.Resources.ScheduledAction
        ],
        Integrations: [
          Karo.Character,
          Karo.LLM
        ],
        Transports: [
          Karo.Discord.Gateway,
          Karo.Discord.Handler,
          Karo.Transports.Tui
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
      extra_applications: [:logger],
      mod: {Karo.Application, []},
      included_applications: if(Mix.env() == :test, do: [:nostrum], else: [])
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Runtime - Jido ecosystem
      jido_dep(:jido, "../jido", "~> 1.3.0"),
      jido_dep(:jido_character, "../jido_character", "~> 1.0.0"),
      jido_dep(:req_llm, "../req_llm", "~> 1.2.0"),

      # Runtime - Persistence
      {:ash, "~> 3.0"},
      {:ash_sqlite, "~> 0.2"},

      # Runtime - Discord
      {:nostrum, "~> 0.10"},

      # Runtime - Utilities
      {:jason, "~> 1.4"},

      # Dev/Test - TUI
      {:owl, "~> 0.12", only: [:dev, :test]},

      # Dev/Test - Quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mimic, "~> 2.0", only: :test}
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

  defp jido_dep(app, rel_path, hex_req, extra_opts \\ []) do
    path = Path.expand(rel_path, __DIR__)

    if File.dir?(path) and File.exists?(Path.join(path, "mix.exs")) do
      {app, Keyword.merge([path: rel_path, override: true], extra_opts)}
    else
      {app, hex_req, extra_opts}
    end
    |> case do
      {app, opts} when is_list(opts) -> {app, opts}
      {app, req, opts} -> {app, req, opts}
    end
  end
end
