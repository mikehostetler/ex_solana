defmodule JidoClaude.Actions.CancelSession do
  @moduledoc """
  Cancel a running Claude session.

  This action is called on the ClaudeSessionAgent itself to cancel
  its running session. For cancelling a child session from a parent
  agent, use `JidoClaude.Parent.CancelSession` instead.

  ## Parameters

    * `reason` - Optional. Reason for cancellation. Default: `:cancelled`

  ## Example

      cmd(agent, {CancelSession, %{reason: :timeout}})

  """

  use Jido.Action,
    name: "claude_cancel_session",
    description: "Cancel a running Claude session",
    schema: [
      reason: [type: :atom, default: :cancelled]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Signals

  @impl true
  def run(params, context) do
    agent = context[:agent]
    status = if agent, do: agent.state.status, else: :idle
    session_id = if agent, do: agent.state.session_id, else: nil

    if status == :running do
      state = %{
        status: :cancelled,
        error: %{type: :cancelled, reason: params.reason}
      }

      signal = Signals.session_error(session_id, :cancelled, %{reason: params.reason})

      directives = [
        Directive.emit_to_parent(agent, signal),
        Directive.stop(params.reason)
      ]

      {:ok, state, directives}
    else
      {:error, :session_not_running}
    end
  end
end
