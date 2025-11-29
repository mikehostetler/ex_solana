defmodule Kaizen.MixProject do
  use Mix.Project

  def project do
    [
      app: :kaizen,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Kaizen.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:nimble_options, "~> 1.1"},
      {:typed_struct, "~> 0.3.0"},
      {:splode, "~> 0.2.3"},
      {:telemetry, "~> 1.0"},

      # Dev/test dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:quokka, "~> 2.11", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer",
        "credo --strict"
      ],
      q: ["quality"],
      "demo.hello_world": ["run -e Kaizen.Examples.HelloWorld.demo()"],
      "demo.knapsack": ["run -e Kaizen.Examples.Knapsack.run()"],
      "demo.tsp": ["run -e Kaizen.Examples.TravelingSalesman.demo()"],
      "demo.hyperparameters": ["run -e Kaizen.Examples.HyperparameterTuning.demo()"]
    ]
  end
end
