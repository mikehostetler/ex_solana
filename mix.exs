defmodule JidoHub.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_hub,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {JidoHub.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  def coveralls do
    [
      minimum_coverage: 80,
      export: "test/coverage",
      treat_no_relevant_lines_as_covered: true
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling],
      list_unused_filters: true,
      ignore_warnings: ".dialyzer_ignore.exs",
      format: :short
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core Ash Framework
      {:ash, "~> 3.0"},
      {:ash_admin, "~> 0.13"},
      {:ash_ai, "~> 0.2"},
      {:ash_archival, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_cloak, "~> 0.1"},
      {:ash_json_api, "~> 1.0"},
      {:ash_oban, "~> 0.4"},
      {:ash_paper_trail, "~> 0.5"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_typescript, "~> 0.4"},

      # Phoenix Framework
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},

      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},

      # Background Jobs
      {:oban, "~> 2.0"},
      {:oban_web, "~> 2.0"},

      # Authentication & Security
      {:bcrypt_elixir, "~> 3.0"},
      {:cloak, "~> 1.0"},
      {:plug_attack, "~> 0.4"},
      {:ex_rated, "~> 2.0"},

      # HTTP & API
      {:req, "~> 0.5"},
      {:open_api_spex, "~> 3.0"},
      {:bandit, "~> 1.5"},

      # Email
      {:swoosh, "~> 1.16"},

      # Assets & Frontend
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:lucide_icons, "~> 2.0"},
      {:daisy_ui_components, "~> 0.9.2"},

      # Utilities
      {:jason, "~> 1.2"},
      {:gettext, "~> 0.26"},
      {:ex_cldr, "~> 2.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:picosat_elixir, "~> 0.2"},
      {:timex, "~> 3.7"},

      # Development Tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:live_debugger, "~> 0.4", only: [:dev]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:usage_rules, "~> 0.1", only: [:dev]},

      # Testing
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0"},
      {:phoenix_test_playwright, "~> 0.1", only: :test},
      {:phoenix_storybook, "~> 0.9.3", only: :dev},
      {:excoveralls, "~> 0.18", only: :test},
      {:faker, "~> 0.18", only: [:test, :dev]},

      # Code Generation & Tools
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:rename_project, "~> 0.1.0"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind jido_hub", "esbuild jido_hub"],
      "assets.deploy": [
        "tailwind jido_hub --minify",
        "esbuild jido_hub --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warning-as-errors",
        "deps.unlock --unused",
        "format",
        "test",
        "dialyzer",
        "sobelow --exit"
      ],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict",
        "sobelow --exit",
        "coveralls.html"
      ],
      q: ["quality"]
    ]
  end
end
