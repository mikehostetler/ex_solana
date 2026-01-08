defmodule JidoClaude.Parent.HandleSessionEvent do
  @moduledoc """
  Process signals from child Claude sessions.

  This action is used by parent/orchestrator agents to handle signals
  emitted by their child ClaudeSessionAgent instances. It updates the
  session registry with status, turn counts, results, and errors.

  ## Parameters

    * `session_id` - Required. The session identifier.
    * `event_type` - Required. The signal type (e.g., "claude.session.started").
    * `data` - Optional. Event-specific data.

  ## Handled Events

    * `claude.session.started` - Session initialized
    * `claude.turn.*` - Turn progress (text, tool_use, tool_result)
    * `claude.session.success` - Session completed successfully
    * `claude.session.error` - Session failed

  ## Usage

  Add to your parent agent's signal_routes:

      def signal_routes do
        [
          {"claude.session.started", {HandleSessionEvent, &extract_params/1}},
          {"claude.turn.text", {HandleSessionEvent, &extract_params/1}},
          {"claude.session.success", {HandleSessionEvent, &extract_params/1}},
          {"claude.session.error", {HandleSessionEvent, &extract_params/1}}
        ]
      end

      defp extract_params(signal) do
        %{
          session_id: signal.data.session_id,
          event_type: signal.type,
          data: signal.data
        }
      end

  """

  use Jido.Action,
    name: "claude_handle_session_event",
    description: "Process signals from child Claude sessions",
    schema: [
      session_id: [type: :string, required: true],
      event_type: [type: :string, required: true],
      data: [type: :map, default: %{}]
    ]

  alias JidoClaude.Parent.SessionRegistry

  @impl true
  def run(params, context) do
    session_id = params.session_id
    event_type = params.event_type
    data = params.data

    agent = context[:agent]
    state = if agent, do: agent.state, else: %{sessions: %{}}

    unless SessionRegistry.get_session(state, session_id) do
      {:ok, %{}, []}
    else
      handle_event(event_type, session_id, data, state)
    end
  end

  defp handle_event("claude.session.started", session_id, data, state) do
    update =
      SessionRegistry.update_session(state, session_id, %{
        status: :running,
        sdk_session_id: data[:session_id],
        model: data[:model]
      })

    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.turn." <> _turn_type, session_id, _data, state) do
    session = SessionRegistry.get_session(state, session_id)

    update =
      SessionRegistry.update_session(state, session_id, %{
        turns: (session[:turns] || 0) + 1
      })

    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.session.success", session_id, data, state) do
    update =
      SessionRegistry.update_session(state, session_id, %{
        status: :success,
        result: data[:result],
        cost_usd: data[:cost_usd],
        completed_at: DateTime.utc_now()
      })

    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("claude.session.error", session_id, data, state) do
    update =
      SessionRegistry.update_session(state, session_id, %{
        status: :failure,
        error: data,
        completed_at: DateTime.utc_now()
      })

    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("jido.agent.child.started", session_id, data, state) do
    update =
      SessionRegistry.update_session(state, session_id, %{
        child_pid: data[:pid]
      })

    {:ok, Map.take(update, [:sessions]), []}
  end

  defp handle_event("jido.agent.child.exit", session_id, data, state) do
    session = SessionRegistry.get_session(state, session_id)

    if session[:status] in [:starting, :running] do
      update =
        SessionRegistry.update_session(state, session_id, %{
          status: :failure,
          error: %{type: :child_exit, reason: data[:reason]},
          completed_at: DateTime.utc_now()
        })

      {:ok, Map.take(update, [:sessions]), []}
    else
      {:ok, %{}, []}
    end
  end

  defp handle_event(_unknown, _session_id, _data, _state) do
    {:ok, %{}, []}
  end
end
