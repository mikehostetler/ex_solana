defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Cron do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.Signal.CronTick

  def exec(
        %{cron: cron_expr, message: message, job_id: logical_id, timezone: tz},
        _input_signal,
        state
      ) do
    agent_id = state.id

    # Generate job_id if not provided
    logical_id = logical_id || make_ref()

    # Build signal from message
    signal =
      case message do
        %Jido.Signal{} = s ->
          s

        other ->
          CronTick.new!(
            %{job_id: logical_id, message: other},
            source: "/agent/#{agent_id}"
          )
      end

    # Cancel existing job with same logical_id if it exists
    case Map.get(state.cron_jobs, logical_id) do
      nil -> :ok
      existing_pid when is_pid(existing_pid) -> Jido.Scheduler.cancel(existing_pid)
      _ -> :ok
    end

    # Start SchedEx cron job
    opts = if tz, do: [timezone: tz], else: []

    result =
      Jido.Scheduler.run_every(
        fn ->
          # Fire signal into the agent (fire-and-forget)
          _ = Jido.AgentServer.cast(agent_id, signal)
          :ok
        end,
        cron_expr,
        opts
      )

    case result do
      {:ok, pid} ->
        Logger.debug(
          "AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}"
        )

        # Track pid in state for cleanup/cancel
        new_state = put_in(state.cron_jobs[logical_id], pid)
        {:ok, new_state}

      {:error, reason} ->
        Logger.error(
          "AgentServer #{agent_id} failed to register cron job #{inspect(logical_id)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
