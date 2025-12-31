defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.CronCancel do
  @moduledoc false

  require Logger

  def exec(%{job_id: logical_id}, _input_signal, state) do
    agent_id = state.id

    case Map.get(state.cron_jobs, logical_id) do
      nil ->
        Logger.debug(
          "AgentServer #{agent_id} cron job #{inspect(logical_id)} not found, nothing to cancel"
        )

        {:ok, state}

      pid when is_pid(pid) ->
        Jido.Scheduler.cancel(pid)
        Logger.debug("AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}")
        new_state = %{state | cron_jobs: Map.delete(state.cron_jobs, logical_id)}
        {:ok, new_state}

      _other ->
        # Legacy: job_name string from old Quantum-based implementation
        Logger.debug(
          "AgentServer #{agent_id} cron job #{inspect(logical_id)} has legacy format, removing from state"
        )

        new_state = %{state | cron_jobs: Map.delete(state.cron_jobs, logical_id)}
        {:ok, new_state}
    end
  end
end
