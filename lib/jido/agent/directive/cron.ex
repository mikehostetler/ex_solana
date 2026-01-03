defmodule Jido.Agent.Directive.Cron do
  @moduledoc """
  Register or update a recurring cron job for this agent.

  The job is owned by the agent's `id` and identified within that agent
  by `job_id`. On each tick, the scheduler sends `message` (or `signal`)
  back to the agent via `Jido.AgentServer.cast/2`.

  ## Fields

  - `job_id` - Logical id within the agent (for upsert/cancel). Auto-generated if nil.
  - `cron` - Cron expression string (e.g., "* * * * *", "@daily", "*/5 * * * *")
  - `message` - Signal or message to send on each tick
  - `timezone` - Optional timezone identifier (default: UTC)

  ## Examples

      # Every minute, send a tick signal
      %Cron{cron: "* * * * *", message: tick_signal, job_id: :heartbeat}

      # Daily at midnight, send a cleanup signal
      %Cron{cron: "@daily", message: cleanup_signal, job_id: :daily_cleanup}

      # Every 5 minutes with timezone
      %Cron{cron: "*/5 * * * *", message: check_signal, job_id: :check, timezone: "America/New_York"}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id:
                Zoi.any(description: "Logical cron job id within the agent")
                |> Zoi.optional(),
              cron: Zoi.any(description: "Cron expression (e.g. \"* * * * *\", \"@daily\")"),
              message: Zoi.any(description: "Signal or message to send on each tick"),
              timezone:
                Zoi.any(description: "Timezone identifier (optional)")
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

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

    logical_id = logical_id || make_ref()

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

    case Map.get(state.cron_jobs, logical_id) do
      nil -> :ok
      existing_pid when is_pid(existing_pid) -> Jido.Scheduler.cancel(existing_pid)
      _ -> :ok
    end

    opts = if tz, do: [timezone: tz], else: []

    result =
      Jido.Scheduler.run_every(
        fn ->
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
