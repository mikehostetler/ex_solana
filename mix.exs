defmodule ExSolana.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_solana,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Solana library for Elixir",
      package: package()
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:jason, "~> 1.4"},
      {:typed_struct, "~> 0.3.0"},  # Changed from typedstruct to avoid duplicates
      {:basefiftyeight, "~> 0.1.0"},
      {:decimal, "~> 2.1"},
      {:ed25519, "~> 1.3"},
      {:mnemonic, "~> 0.3.1"},
      {:block_keys, "~> 1.0"},
      # Protobuf - removed google_protos as protobuf already includes Google.Protobuf.* modules
      {:protobuf, "~> 0.14.0"},
      {:protobuf_generate, "~> 0.1.0"},
      {:grpc, "~> 0.9"},

      # Http
      {:mint, "~> 1.6"},
      {:ex_rated, "~> 2.1"},
      {:phx_json_rpc, "~> 0.7"},
      {:ex_json_schema, "~> 0.11.1", override: true},

      # Broadway
      {:broadway, "~> 1.1"},
      {:tesla, "~> 1.9", override: true},
      {:finch, "~> 0.14"},
      {:httpoison, "~> 2.0"},
      {:multipart, "~> 0.4.0"},
      {:remote_ip, "~> 1.2"},
      {:websockex, "~> 0.4.3"},

      # Dev & Test Dependencies
      {:mimic, "~> 1.7.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Mike Hostetler"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mikehostetler/ex_solana"},
      files: ~w(lib mix.exs README* LICENSE*)
    ]
  end
end
