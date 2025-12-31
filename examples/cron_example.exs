#!/usr/bin/env elixir

# Cron Scheduling Example
#
# This example demonstrates how to use cron-based scheduling in Jido agents.
# The agent will automatically stop after receiving a configured number of ticks.
#
# Usage:
#   mix run examples/cron_example.exs

Code.require_file("agents/sleeper_agent.ex", __DIR__)

defmodule CronExample do
  @moduledoc """
  Example demonstrating cron scheduling with Jido agents.

  Shows:
  - Creating an agent that uses cron scheduling
  - Registering cron jobs with schedules
  - Handling cron tick signals
  - Auto-canceling after max ticks
  - Manual cancellation
  - Agent cleanup on stop
  """

  alias Examples.SleeperAgent

  @max_ticks 5
  @tick_interval_seconds 2

  def run do
    IO.puts("\n╔═══════════════════════════════════════╗")
    IO.puts("║  Jido Cron Scheduling Demo           ║")
    IO.puts("║  Max ticks: #{@max_ticks}                          ║")
    IO.puts("║  Interval: #{@tick_interval_seconds}s (for demo)            ║")
    IO.puts("╚═══════════════════════════════════════╝\n")

    # Start a Jido instance for the example
    {:ok, _} = Jido.start_link(name: CronExample.Jido)

    # Ensure scheduler is started
    case Jido.Scheduler.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Step 1: Start agent under the Jido instance
    IO.puts("1️⃣  Starting SleeperAgent...")

    {:ok, _pid} =
      Jido.start_agent(CronExample.Jido, SleeperAgent,
        id: "sleeper-001",
        state: %{tick_count: 0, max_ticks: @max_ticks}
      )

    IO.puts("   ✓ Agent started: sleeper-001\n")

    # Step 2: Register cron job
    IO.puts("2️⃣  Registering cron job...")
    # Use a short interval for demo (every 2 seconds via manual trigger)
    # In production, use real cron expressions like "* * * * *"

    register_signal =
      Jido.Signal.new!(
        "agent.register.cron",
        %{job_id: :heartbeat, cron_expr: "* * * * *"},
        source: "/example"
      )

    :ok = Jido.cast(CronExample.Jido, "sleeper-001", register_signal)
    Process.sleep(100)
    IO.puts("   ✓ Cron job registered: :heartbeat\n")

    # Step 3: Simulate ticks (in production these happen automatically)
    IO.puts("3️⃣  Triggering cron ticks (simulated for demo)...\n")

    job_name = String.to_atom("jido_cron:sleeper-001:heartbeat")

    # Trigger ticks with delay to show progression
    Enum.reduce_while(1..@max_ticks, nil, fn tick, _acc ->
      IO.puts("   Triggering tick #{tick}...")
      Jido.Scheduler.run_job(job_name)
      Process.sleep(100)

      # Check state
      {:ok, state} = Jido.state(CronExample.Jido, "sleeper-001")
      tick_count = Map.get(state.agent.state, :tick_count, 0)

      if tick_count >= @max_ticks do
        IO.puts("\n   🛑 Max ticks reached - job auto-canceled\n")
        {:halt, nil}
      else
        if tick < @max_ticks do
          Process.sleep(@tick_interval_seconds * 1000)
        end

        {:cont, nil}
      end
    end)

    # Step 4: Verify cleanup
    IO.puts("4️⃣  Verifying job cleanup...")
    Process.sleep(100)

    jobs = Jido.Scheduler.jobs()

    if Enum.any?(jobs, fn {name, _} -> name == job_name end) do
      IO.puts("   ⚠ Job still exists (may not have been canceled)")
    else
      IO.puts("   ✓ Job successfully removed from scheduler\n")
    end

    # Step 5: Stop agent
    IO.puts("5️⃣  Stopping agent...")

    case Jido.whereis(CronExample.Jido, "sleeper-001") do
      nil ->
        IO.puts("   ⚠ Agent not running")

      pid ->
        GenServer.stop(pid)
        Process.sleep(100)
        IO.puts("   ✓ Agent stopped\n")
    end

    # Final verification
    IO.puts("6️⃣  Final cleanup verification...")
    jobs_after = Jido.Scheduler.jobs()

    if Enum.any?(jobs_after, fn {name, _} -> name == job_name end) do
      IO.puts("   ⚠ Job still exists after agent stop")
    else
      IO.puts("   ✓ All cron jobs cleaned up")
    end

    IO.puts("\n╔═══════════════════════════════════════╗")
    IO.puts("║  ✓ Demo completed successfully!      ║")
    IO.puts("╚═══════════════════════════════════════╝\n")

    :ok
  end
end

# Run the demo
CronExample.run()
