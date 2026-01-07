defmodule Mix.Tasks.Claude.Test do
  use Mix.Task

  @shortdoc "Test Claude Code SDK integration"

  @moduledoc """
  Sends a simple prompt to Claude Code using claude_code_sdk and prints
  the streamed messages. Assumes Claude Code is already configured locally.
  """

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Starting Claude Code SDK test...")

    prompt = "/cost"

    prompt
    |> ClaudeCodeSDK.query()
    |> Enum.each(fn message ->
      IO.inspect(message, label: "Claude message")
    end)

    Mix.shell().info("Claude Code SDK test finished.")
  end
end
