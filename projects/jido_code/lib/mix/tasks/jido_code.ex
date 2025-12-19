defmodule Mix.Tasks.JidoCode do
  @moduledoc """
  Starts the JidoCode TUI application.

  ## Usage

      mix jido_code

  This starts the interactive terminal interface for JidoCode.
  Press Ctrl+C to exit.

  ## Configuration

  Before running, ensure you have configured a provider and model.
  Create `~/.jido_code/settings.json` with:

      {
        "provider": "anthropic",
        "model": "claude-sonnet-4-20250514"
      }

  Or use the `/provider` and `/model` commands within the TUI.
  """

  use Mix.Task

  @shortdoc "Starts the JidoCode TUI"

  @impl Mix.Task
  def run(_args) do
    # Ensure the application is started
    Mix.Task.run("app.start")

    # Ensure Jido discovery cache is initialized before TUI starts
    Jido.Discovery.init()

    # Try to start the LLM agent if configured
    # If not configured, TUI will show configuration screen
    maybe_start_agent()

    # Run the TUI (blocks until quit)
    JidoCode.TUI.run()
  end

  defp maybe_start_agent do
    case JidoCode.AgentSupervisor.start_agent(%{
           name: :llm_agent,
           module: JidoCode.Agents.LLMAgent,
           args: []
         }) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Mix.shell().info("""
        Note: LLM agent not started - #{inspect(reason)}
        Configure provider/model in the TUI using /provider and /model commands.
        """)

        :ok
    end
  end
end
