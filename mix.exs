defmodule JidoWorkspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_workspace,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      config_path: "config/workspace.exs"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:table_rex, "~> 4.0"},
      {:git_cli, "~> 0.3"},
      {:yaml_elixir, "~> 2.10"},
      {:ymlr, "~> 5.0"},
      {:jason, "~> 1.4"},
      {:req_fly, "~> 1.0"},
      {:req_llm, "~> 1.0.0-rc"},
      {:dotenv, "~> 3.1", only: :dev},
      {:claude_agent_sdk, "~> 0.7"},
      {:sprites, github: "superfly/sprites-ex"}
    ]
  end

  defp aliases do
    [
      # High-level shortcuts
      morning: ["ws.git.pull", "compile"],
      sync: ["ws.git.pull", "ws test"],

      # Convenient shortcuts for new commands
      "ws.pull": ["ws.git.pull"],
      "ws.push": ["ws.git.push"],
      "ws.status": ["ws.git.status"],
      "ws.report": ["ws.status.detailed"],
      "ws.test": ["ws test"],
      "ws.deps.get": ["ws deps.get"],
      "ws.deps.upgrade": ["ws.upgrade.deps"],

      # Slidev commands
      "slidev.dev": ["slidev.dev"],
      "slidev.build": ["slidev.build"],
      "slidev.install": ["slidev.install"],
      "slidev.new": ["slidev.new"],

      # Hex publishing commands
      "hex.publish.all": ["hex_publish"],
      "version.check": ["version.check"],

      # Roadmap workflow commands
      "roadmap.status": ["roadmap.workflow.status"]
    ]
  end
end
