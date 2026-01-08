defmodule JidoClaude.ClaudeSessionAgent do
  @moduledoc """
  Agent that manages a single Claude Code session lifecycle.

  The ClaudeSessionAgent owns a single Claude session and emits signals
  for each turn. It is designed to be spawned as a child of a parent
  orchestrator agent.

  ## State

  The agent maintains the following state:

    * `status` - Current session status (`:idle`, `:running`, `:success`, `:failure`)
    * `session_id` - Unique identifier for this session
    * `prompt` - The original prompt sent to Claude
    * `options` - SDK options used for the session
    * `model` - Model name (populated after session init)
    * `turns` - Number of turns completed
    * `transcript` - List of messages exchanged
    * `result` - Final result text (on success)
    * `cost_usd` - Total cost in USD (on completion)
    * `error` - Error details (on failure)

  ## Signal Routes

  The agent routes internal messages from the StreamRunner:

    * `claude.internal.message` → HandleMessage action

  ## Usage

      # Start as child of parent agent
      Directive.spawn_agent(
        ClaudeSessionAgent,
        "session-123",
        opts: %{
          initial_state: %{
            session_id: "session-123",
            prompt: "Analyze this codebase"
          }
        }
      )

  """

  use Jido.Agent,
    name: "claude_session",
    description: "Manages a single Claude Code session",
    schema: [
      status: [type: :atom, default: :idle],
      prompt: [type: :string, default: nil],
      options: [type: :any, default: nil],
      session_id: [type: :string, default: nil],
      model: [type: :string, default: nil],
      turns: [type: :integer, default: 0],
      transcript: [type: {:list, :any}, default: []],
      result: [type: :string, default: nil],
      cost_usd: [type: :float, default: nil],
      error: [type: :any, default: nil]
    ]

  @impl Jido.Agent
  def signal_routes do
    [
      {"claude.internal.message", {JidoClaude.Actions.HandleMessage, %{}}}
    ]
  end

  def actions do
    [
      JidoClaude.Actions.StartSession,
      JidoClaude.Actions.HandleMessage,
      JidoClaude.Actions.CancelSession
    ]
  end
end
