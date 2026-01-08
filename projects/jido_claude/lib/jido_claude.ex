defmodule JidoClaude do
  @moduledoc """
  Claude Code integration for the Jido Agent framework.

  JidoClaude provides a two-agent pattern for running Claude Code sessions:

  - **ClaudeSessionAgent** - Manages a single Claude session lifecycle, emits signals per turn
  - **Parent Agent** - Business logic, manages multiple concurrent Claude sessions

  ## Architecture

  ```
  ┌─────────────────────────────────────────┐
  │  Parent Agent (Orchestrator)            │
  │  - Spawns ClaudeSessionAgent children   │
  │  - Receives signals from all sessions   │
  │  - Tracks status in sessions registry   │
  └─────────────────────────────────────────┘
            │ SpawnAgent
            ▼
  ┌─────────────────────────────────────────┐
  │  ClaudeSessionAgent                     │
  │  - Owns single Claude session           │
  │  - Runs SDK in background Task          │
  │  - Emits turn signals to parent         │
  └─────────────────────────────────────────┘
            │ Task
            ▼
  ┌─────────────────────────────────────────┐
  │  StreamRunner                           │
  │  - Calls ClaudeAgentSDK.query/3         │
  │  - Dispatches messages as signals       │
  └─────────────────────────────────────────┘
  ```

  ## Usage

  ### Single Session (ClaudeSessionAgent)

      # Start a session agent
      {:ok, pid} = Jido.Agent.Server.start_link(
        agent: JidoClaude.ClaudeSessionAgent,
        name: {:via, Registry, {MyRegistry, "claude-1"}}
      )

      # Run a prompt
      Jido.Agent.Server.cmd(pid, {JidoClaude.Actions.StartSession, %{
        prompt: "Analyze this codebase",
        model: "sonnet",
        max_turns: 25
      }})

  ### Multi-Session (Parent Agent)

      # In your parent agent
      {agent, _} = cmd(agent, {JidoClaude.Parent.SpawnSession, %{
        session_id: "review-pr-123",
        prompt: "Review PR #123 for security issues"
      }})

  ## Signal Types

  | Signal | Description |
  |--------|-------------|
  | `claude.session.started` | Session initialized with model info |
  | `claude.turn.text` | Claude's text response |
  | `claude.turn.tool_use` | Claude is calling a tool |
  | `claude.turn.tool_result` | Tool execution result |
  | `claude.session.success` | Session completed successfully |
  | `claude.session.error` | Session failed |

  """

  @doc """
  Returns the version of the JidoClaude library.
  """
  def version, do: "0.1.0"
end
