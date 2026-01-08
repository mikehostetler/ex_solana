defmodule JidoClaude.Parent.CancelSession do
  @moduledoc """
  Cancel a running Claude session from the parent agent.

  This action is used by parent/orchestrator agents to cancel a child
  ClaudeSessionAgent. It updates the session registry and emits a
  StopChild directive.

  ## Parameters

    * `session_id` - Required. The session identifier to cancel.
    * `reason` - Optional. Reason for cancellation. Default: `:cancelled`

  ## Example

      {agent, _} = cmd(agent, {CancelSession, %{
        session_id: "review-pr-123",
        reason: :timeout
      }})

  """

  use Jido.Action,
    name: "claude_parent_cancel_session",
    description: "Cancel a running Claude session",
    schema: [
      session_id: [type: :string, required: true],
      reason: [type: :atom, default: :cancelled]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params.session_id
    agent = context[:agent]
    state = if agent, do: agent.state, else: %{sessions: %{}}

    session = SessionRegistry.get_session(state, session_id)

    cond do
      is_nil(session) ->
        {:error, :session_not_found}

      session.status not in [:starting, :running] ->
        {:error, :session_not_active}

      true ->
        update =
          SessionRegistry.update_session(state, session_id, %{
            status: :cancelled,
            completed_at: DateTime.utc_now()
          })

        directive = Directive.stop_child(session_id, params.reason)

        {:ok, Map.take(update, [:sessions]), [directive]}
    end
  end
end
