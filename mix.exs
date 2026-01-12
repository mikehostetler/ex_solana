defmodule ExSolana.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/mikehostetler/ex_solana"
  @description "Solana library for Elixir - Core package with RPC, WebSocket, IDL, and transaction support"

  def vsn do
    @version
  end

  def project do
    [
      app: :ex_solana,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),

      # Docs
      name: "ExSolana",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),

      # Coverage
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 80],
        export: "cov"
      ],

      # Dialyzer
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.lcov": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "LICENSE",
        "guides/getting-started.md",
        "guides/migration.md"
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ],
      groups_for_modules: [
        Core: [
          ExSolana,
          ExSolana.Key,
          ExSolana.Account,
          ExSolana.Transaction,
          ExSolana.Signature,
          ExSolana.Block
        ],
        RPC: [
          ExSolana.RPC,
          ExSolana.RPC.Client,
          ExSolana.RPC.Request
        ],
        WebSocket: [
          ExSolana.WebSocket
        ],
        IDL: [
          ExSolana.IDL,
          ExSolana.IDL.Parser,
          ExSolana.IDL.Generator
        ],
        Instructions: [
          ExSolana.Ix,
          ExSolana.Ix.Transfer,
          ExSolana.Ix.JupiterSwap
        ],
        Decoder: [
          ExSolana.Decoder,
          ExSolana.Decoder.Transaction,
          ExSolana.Decoder.Instruction
        ],
        Errors: [
          ExSolana.Error,
          ExSolana.Error.InvalidKeyError,
          ExSolana.Error.RPCError,
          ExSolana.Error.TransactionError
        ]
      ]
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Mike Hostetler"],
      licenses: ["MIT"],
      links: %{
        "Documentation" => "https://hexdocs.pm/ex_solana",
        "GitHub" => @source_url,
        "Changelog" => "https://github.com/mikehostetler/ex_solana/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Core Dependencies - Modern Jido Ecosystem Stack
      {:zoi, "~> 0.10"},
      {:splode, "~> 0.2.5"},
      {:req, "~> 0.5.16"},

      # JSON
      {:jason, "~> 1.4"},

      # Cryptography
      {:basefiftyeight, "~> 0.1.0"},
      {:ed25519, "~> 1.3"},
      {:mnemonic, "~> 0.3.1"},
      {:block_keys, "~> 1.0"},

      # JSON-RPC
      {:phx_json_rpc, "~> 0.7"},
      {:ex_json_schema, "~> 0.11.1", override: true},

      # WebSocket
      {:websockex, "~> 0.4.3"},

      # GRPC (for future Geyser support)
      {:grpc, "~> 0.9"},
      {:protobuf, "~> 0.15.0"},

      # Development & Test Dependencies
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.3", only: [:dev, :test]},
      {:mimic, "~> 2.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      test: "test --exclude flaky",
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end
end
