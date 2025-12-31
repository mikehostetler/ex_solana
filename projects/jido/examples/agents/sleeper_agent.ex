defmodule Examples.SleeperAgent do
  @moduledoc """
  Example agent that demonstrates cron scheduling.

  This agent:
  - Registers heartbeat cron jobs
  - Handles cron tick signals
  - Tracks tick counts with a maximum limit
  - Can cancel cron jobs on demand
  """

  use Jido.Agent,
    name: "sleeper_agent",
    description: "An agent that demonstrates cron scheduling with tick limits",
    actions: [
      Examples.SleeperAgent.RegisterCronAction,
      Examples.SleeperAgent.CancelCronAction,
      Examples.SleeperAgent.HandleCronTickAction
    ],
    signals: [
      %{
        signal: "agent.register.cron",
        action: Examples.SleeperAgent.RegisterCronAction,
        description: "Register a new cron job"
      },
      %{
        signal: "agent.cancel.cron",
        action: Examples.SleeperAgent.CancelCronAction,
        description: "Cancel an existing cron job"
      },
      %{
        signal: "cron.tick",
        action: Examples.SleeperAgent.HandleCronTickAction,
        description: "Handle cron tick signals"
      }
    ],
    schema: [
      tick_count: [type: :integer, default: 0],
      max_ticks: [type: :integer, default: 5]
    ]

  defmodule RegisterCronAction do
    @moduledoc """
    Action to register a cron job.
    """
    use Jido.Action,
      name: "register_cron",
      description: "Register a cron job",
      schema: [
        job_id: [type: :atom, required: true],
        cron_expr: [type: :string, required: true]
      ]

    def run(params, context) do
      job_id = params.job_id
      cron_expr = params.cron_expr

      tick_signal =
        Jido.Signal.new!(
          "cron.tick",
          %{job_id: job_id, timestamp: DateTime.utc_now()},
          source: "/cron/#{job_id}"
        )

      cron_directive = Jido.Agent.Directive.cron(cron_expr, tick_signal, job_id: job_id)

      {:ok, %{job_id: job_id, cron: cron_expr}, context, [cron_directive]}
    end
  end

  defmodule CancelCronAction do
    @moduledoc """
    Action to cancel a previously registered cron job.
    """
    use Jido.Action,
      name: "cancel_cron",
      description: "Cancel a cron job",
      schema: [
        job_id: [type: :atom, required: true]
      ]

    def run(params, context) do
      job_id = params.job_id
      cancel_directive = Jido.Agent.Directive.cron_cancel(job_id)

      {:ok, %{cancelled: job_id}, context, [cancel_directive]}
    end
  end

  defmodule HandleCronTickAction do
    @moduledoc """
    Action that handles incoming cron tick signals.
    Automatically stops the cron job when max_ticks is reached.
    """
    use Jido.Action,
      name: "handle_cron_tick",
      description: "Handle cron tick signals with max limit"

    def run(params, context) do
      tick_count = Map.get(context.state, :tick_count, 0) + 1
      max_ticks = Map.get(context.state, :max_ticks, 5)
      job_id = Map.get(params, :job_id, :unknown)

      IO.puts("⏰ Tick ##{tick_count}/#{max_ticks} at #{DateTime.utc_now()}")

      new_state = Map.put(context.state, :tick_count, tick_count)
      new_context = Map.put(context, :state, new_state)

      directives =
        if tick_count >= max_ticks do
          IO.puts("✓ Max ticks reached - canceling job")
          [Jido.Agent.Directive.cron_cancel(job_id)]
        else
          []
        end

      {:ok, %{tick_count: tick_count, max_reached: tick_count >= max_ticks}, new_context,
       directives}
    end
  end
end
