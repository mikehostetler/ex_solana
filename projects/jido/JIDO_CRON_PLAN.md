# Jido Cron Scheduling Implementation Plan

## Overview

This document outlines the plan to bring cron-based scheduling into the Jido V2 architecture. The implementation leverages the existing `Jido.Scheduler` (Quantum wrapper) and extends the directive system with new `%Directive.Cron{}` and `%Directive.CronCancel{}` types.

**Estimated Scope:** M (1-3h) for basic implementation; additional time for advanced features.

---

## 1. Background

### Previous Jido Implementation (v1 main branch)

The previous version had:
- `Jido.Scheduler` - A Quantum wrapper for system-wide cron jobs
- `Jido.Sensors.Cron` - A GenServer sensor that registered cron jobs and emitted signals
- Signal dispatch to agents via `Jido.Signal.Dispatch`

### Current V2 Architecture

- `Jido.Agent` - Pure, immutable agents using `cmd/2` pattern
- `Jido.AgentServer` - GenServer runtime that handles directives
- `Jido.Agent.Directive` - Including `Schedule`, `Emit`, `Spawn`, etc.
- `Jido.AgentServer.SignalRouter` - Routes signals to actions
- Existing `Jido.Scheduler` module (Quantum wrapper) - **NOT started in Application.ex**
- Existing `Directive.Schedule` - One-time delayed messages via `Process.send_after`

---

## 2. Design Decisions

### Cron Library Choice: Quantum (Keep Existing)

**Recommendation:** Use the existing `Jido.Scheduler` (Quantum wrapper).

**Justification:**
- Already a dependency in `mix.exs` (`{:quantum, "~> 3.5"}`)
- Already wrapped in `lib/jido/scheduler.ex`
- Supports full cron expressions (`"* * * * *"`, `"@daily"`, `"*/5 * * * *"`)
- Dynamic job add/remove at runtime
- Pure Erlang/Elixir - no external services required
- No new dependencies needed

**Alternatives Considered:**
- `ecron` - Lightweight but less feature-rich
- `Periodic` (from Parent library) - Good but no cron syntax support
- `Oban.Plugins.Cron` - Requires database, not pure BEAM

### Architecture: System-wide Scheduler + Per-Agent Ownership

- **One system-wide `Jido.Scheduler`** process for efficiency
- **Logical ownership per-agent** via job naming: `jido_cron:<agent_id>:<job_id>`
- **New directives** (`%Cron{}`, `%CronCancel{}`) rather than sensors
- **Cleanup on agent termination** via `AgentServer.terminate/2`

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Jido.Application                         │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Jido.Registry│  │AgentSupervisor│  │ Jido.Scheduler   │   │
│  └──────────────┘  └──────────────┘  │ (Quantum)        │   │
│                           │          └────────┬─────────┘   │
│                           │                   │              │
│                    ┌──────┴──────┐            │              │
│                    │ AgentServer │◄───────────┘              │
│                    │ (my-agent)  │   cron tick signals       │
│                    └──────┬──────┘                           │
│                           │                                  │
│                    ┌──────┴──────┐                           │
│                    │ Agent.cmd/2 │                           │
│                    │ + Directives│                           │
│                    └─────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

### Signal Flow

1. Agent emits `%Directive.Cron{}` via `cmd/2`
2. `AgentServer` queues and executes directive via `DirectiveExec`
3. Executor registers job in `Jido.Scheduler` with callback that sends signal
4. When cron fires, `Jido.Scheduler` runs task → `AgentServer.cast/2`
5. `SignalRouter` routes signal to configured action
6. Action runs, may emit more directives

---

## 4. Implementation Details

### 4.1 Module Changes

| Module | Change |
|--------|--------|
| `Jido.Application` | Start `Jido.Scheduler` in supervision tree |
| `Jido.Agent.Directive` | Add `Cron` and `CronCancel` submodules |
| `Jido.AgentServer.State` | Add `cron_jobs` map for tracking |
| `directive_executors.ex` | Add executors for new directives |
| New: `Jido.AgentServer.Signal.CronTick` | Signal type for cron ticks |

### 4.2 New Directive: `%Directive.Cron{}`

```elixir
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
              cron:
                Zoi.any(description: "Cron expression (e.g. \"* * * * *\", \"@daily\")"),
              message:
                Zoi.any(description: "Signal or message to send on each tick"),
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
```

### 4.3 New Directive: `%Directive.CronCancel{}`

```elixir
defmodule Jido.Agent.Directive.CronCancel do
  @moduledoc """
  Cancel a previously registered cron job for this agent by job_id.

  ## Fields

  - `job_id` - The logical job id to cancel

  ## Examples

      %CronCancel{job_id: :heartbeat}
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id: Zoi.any(description: "Logical cron job id within the agent")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end
```

### 4.4 Helper Constructors

Add to `Jido.Agent.Directive`:

```elixir
@doc """
Creates a Cron directive for recurring scheduled execution.

## Options

- `:job_id` - Logical id for the job (for upsert/cancel)
- `:timezone` - Timezone identifier

## Examples

    Directive.cron("* * * * *", tick_signal)
    Directive.cron("@daily", cleanup_signal, job_id: :daily_cleanup)
    Directive.cron("0 9 * * MON", weekly_signal, job_id: :monday_9am, timezone: "America/New_York")
"""
@spec cron(term(), term(), keyword()) :: Cron.t()
def cron(cron_expr, message, opts \\ []) do
  %Cron{
    cron: cron_expr,
    message: message,
    job_id: Keyword.get(opts, :job_id),
    timezone: Keyword.get(opts, :timezone)
  }
end

@doc """
Creates a CronCancel directive to stop a recurring job.

## Examples

    Directive.cron_cancel(:heartbeat)
    Directive.cron_cancel(:daily_cleanup)
"""
@spec cron_cancel(term()) :: CronCancel.t()
def cron_cancel(job_id) do
  %CronCancel{job_id: job_id}
end
```

### 4.5 Directive Executor for `%Cron{}`

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Cron do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.Signal.CronTick
  alias Jido.AgentServer.State

  def exec(%{cron: cron_expr, message: message, job_id: logical_id, timezone: tz}, _input_signal, state) do
    agent_id = state.id

    # Generate job_id if not provided
    logical_id = logical_id || make_ref()

    # Create unique job name scoped to agent
    job_name = job_name(agent_id, logical_id)

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

    # Build Quantum job
    job =
      Jido.Scheduler.new_job()
      |> Quantum.Job.set_name(String.to_atom(job_name))
      |> Quantum.Job.set_schedule(parse_cron!(cron_expr))
      |> maybe_set_timezone(tz)
      |> Quantum.Job.set_task(fn ->
        # Fire signal into the agent (fire-and-forget)
        _ = Jido.AgentServer.cast(agent_id, signal)
        :ok
      end)

    # Upsert: delete previous job with same name (if exists), then add
    _ = Jido.Scheduler.delete_job(String.to_atom(job_name))
    :ok = Jido.Scheduler.add_job(job)

    Logger.debug("AgentServer #{agent_id} registered cron job #{inspect(logical_id)}: #{cron_expr}")

    # Track in state for cleanup
    new_state = put_in(state.cron_jobs[logical_id], job_name)

    {:ok, new_state}
  end

  defp job_name(agent_id, job_id) do
    "jido_cron:#{agent_id}:#{inspect(job_id)}"
  end

  defp parse_cron!(expr) when is_binary(expr) do
    Crontab.CronExpression.Parser.parse!(expr, true)
  end

  defp parse_cron!(%Crontab.CronExpression{} = expr), do: expr

  defp maybe_set_timezone(job, nil), do: job
  defp maybe_set_timezone(job, tz), do: Quantum.Job.set_timezone(job, tz)
end
```

### 4.6 Directive Executor for `%CronCancel{}`

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.CronCancel do
  @moduledoc false

  require Logger

  def exec(%{job_id: logical_id}, _input_signal, state) do
    agent_id = state.id

    job_name =
      case Map.get(state.cron_jobs, logical_id) do
        nil -> "jido_cron:#{agent_id}:#{inspect(logical_id)}"
        name -> name
      end

    _ = Jido.Scheduler.delete_job(String.to_atom(job_name))

    Logger.debug("AgentServer #{agent_id} cancelled cron job #{inspect(logical_id)}")

    new_state = %{state | cron_jobs: Map.delete(state.cron_jobs, logical_id)}

    {:ok, new_state}
  end
end
```

### 4.7 CronTick Signal

```elixir
defmodule Jido.AgentServer.Signal.CronTick do
  @moduledoc """
  Signal emitted when a cron job fires.

  Used when the agent registered a cron job with a plain message
  rather than a pre-built Jido.Signal.
  """

  use Jido.Signal,
    name: "jido.agent.cron.tick",
    schema: [
      job_id: [type: :any, required: true, doc: "The logical job id"],
      message: [type: :any, required: true, doc: "The original message payload"]
    ]
end
```

### 4.8 Application Changes

Update `lib/jido/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    Jido.Telemetry,
    {Task.Supervisor, name: Jido.TaskSupervisor, max_children: 1000},
    {Registry, keys: :unique, name: Jido.Registry},
    {DynamicSupervisor,
     name: Jido.AgentSupervisor, strategy: :one_for_one, max_restarts: 1000, max_seconds: 5},
    
    # Cron scheduler (Quantum-based)
    Jido.Scheduler
  ]

  register_signal_extensions()
  Task.start(fn -> Jido.Discovery.init() end)

  Supervisor.start_link(children, strategy: :one_for_one, name: Jido.Supervisor)
end
```

### 4.9 State Changes

Update `Jido.AgentServer.State` to include cron job tracking:

```elixir
defstruct [
  # ... existing fields ...
  cron_jobs: %{}  # %{logical_id => job_name}
]
```

### 4.10 Cleanup on Agent Termination

Add to `Jido.AgentServer.terminate/2`:

```elixir
@impl true
def terminate(_reason, %State{cron_jobs: cron_jobs, id: agent_id} = _state) do
  # Clean up all cron jobs owned by this agent
  Enum.each(cron_jobs, fn {logical_id, job_name} ->
    _ = Jido.Scheduler.delete_job(String.to_atom(job_name))
    Logger.debug("AgentServer #{agent_id} cleaned up cron job #{inspect(logical_id)}")
  end)

  :ok
end
```

---

## 5. Example: Agent with Cron Scheduling

### 5.1 Agent Module Definition

```elixir
defmodule MyApp.HeartbeatAgent do
  @moduledoc """
  An agent that demonstrates cron-based scheduling.
  
  On startup (via "agent.start" signal), registers a cron job that ticks every minute.
  On each tick, performs periodic work (e.g., health check, metrics flush).
  """

  use Jido.Agent,
    name: "heartbeat_agent",
    description: "Agent with periodic heartbeat via cron",
    schema: [
      tick_count: [type: :integer, default: 0],
      status: [type: :atom, default: :idle]
    ]

  @doc """
  Define signal routes for this agent.
  """
  def signal_routes do
    [
      {"agent.start", MyApp.HeartbeatAgent.StartAction},
      {"agent.stop.cron", MyApp.HeartbeatAgent.StopCronAction},
      {"heartbeat.tick", MyApp.HeartbeatAgent.TickAction}
    ]
  end
end
```

### 5.2 Start Action - Registers Cron Job

```elixir
defmodule MyApp.HeartbeatAgent.StartAction do
  @moduledoc """
  Action that starts the heartbeat cron job.
  """

  use Jido.Action,
    name: "heartbeat.start",
    description: "Start periodic heartbeat",
    schema: []

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(_params, context) do
    agent = context.agent
    agent_id = agent.id

    # Create the signal that will be sent on each tick
    tick_signal = Signal.new!(
      "heartbeat.tick",
      %{triggered_at: nil},  # Will be set at runtime
      source: "/agent/#{agent_id}/cron"
    )

    # Register a cron job to tick every minute
    cron_directive = Directive.cron(
      "* * * * *",           # Every minute
      tick_signal,
      job_id: :heartbeat     # Logical ID for this job
    )

    # Update agent state to indicate we're running
    {:ok, updated_agent} = MyApp.HeartbeatAgent.set(agent, %{status: :running})

    {:ok, updated_agent, [cron_directive]}
  end
end
```

### 5.3 Tick Action - Handles Each Cron Tick

```elixir
defmodule MyApp.HeartbeatAgent.TickAction do
  @moduledoc """
  Action that runs on each heartbeat tick.
  """

  use Jido.Action,
    name: "heartbeat.tick",
    description: "Handle periodic tick",
    schema: []

  require Logger

  def run(_params, context) do
    agent = context.agent
    current_count = agent.state.tick_count

    Logger.info("Heartbeat tick ##{current_count + 1} for agent #{agent.id}")

    # Perform periodic work here:
    # - Flush metrics
    # - Health check
    # - Cleanup stale data
    # - etc.

    # Update tick count
    {:ok, updated_agent} = MyApp.HeartbeatAgent.set(agent, %{
      tick_count: current_count + 1
    })

    {:ok, updated_agent, []}
  end
end
```

### 5.4 Stop Cron Action - Cancels the Job

```elixir
defmodule MyApp.HeartbeatAgent.StopCronAction do
  @moduledoc """
  Action that stops the heartbeat cron job.
  """

  use Jido.Action,
    name: "heartbeat.stop",
    description: "Stop periodic heartbeat",
    schema: []

  alias Jido.Agent.Directive

  def run(_params, context) do
    agent = context.agent

    # Cancel the cron job by its logical ID
    cancel_directive = Directive.cron_cancel(:heartbeat)

    # Update state to indicate we've stopped
    {:ok, updated_agent} = MyApp.HeartbeatAgent.set(agent, %{status: :stopped})

    {:ok, updated_agent, [cancel_directive]}
  end
end
```

### 5.5 Usage in Application

```elixir
# Start the agent
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.HeartbeatAgent, id: "heartbeat-1")

# Send signal to start the cron job
start_signal = Jido.Signal.new!("agent.start", %{}, source: "/client")
:ok = Jido.AgentServer.cast("heartbeat-1", start_signal)

# Agent will now receive "heartbeat.tick" signals every minute
# Each tick will log and increment the tick_count

# Later, stop the cron job
stop_signal = Jido.Signal.new!("agent.stop.cron", %{}, source: "/client")
:ok = Jido.AgentServer.cast("heartbeat-1", stop_signal)

# Or just stop the agent (cron jobs auto-cleanup)
GenServer.stop(pid)
```

---

## 6. Example: Cron Sensor Awakening an Agent

This example shows how a cron job can "wake up" an agent that was started but waiting for scheduled work.

### 6.1 The "Sleeper" Agent

```elixir
defmodule MyApp.SleeperAgent do
  @moduledoc """
  An agent that sleeps until awakened by a cron signal.
  
  Demonstrates:
  - Agent starting in idle/sleeping state
  - External signal (from cron) triggers work
  - Agent processing work and going back to sleep
  """

  use Jido.Agent,
    name: "sleeper_agent",
    description: "Agent awakened by cron",
    schema: [
      status: [type: :atom, default: :sleeping],
      work_count: [type: :integer, default: 0],
      last_wake_time: [type: :any, default: nil]
    ]

  def signal_routes do
    [
      # Initial setup - registers the wake-up schedule
      {"sleeper.configure", MyApp.SleeperAgent.ConfigureAction},
      
      # The wake-up signal (sent by cron)
      {"sleeper.wake", MyApp.SleeperAgent.WakeAction},
      
      # Manual trigger to do work now
      {"sleeper.work.now", MyApp.SleeperAgent.DoWorkAction}
    ]
  end
end
```

### 6.2 Configure Action - Sets Up Wake Schedule

```elixir
defmodule MyApp.SleeperAgent.ConfigureAction do
  @moduledoc """
  Configures when the agent should wake up.
  
  Accepts a cron expression in the signal data.
  """

  use Jido.Action,
    name: "sleeper.configure",
    description: "Configure wake schedule",
    schema: [
      schedule: [type: :string, required: true, doc: "Cron expression for wake schedule"]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{schedule: schedule}, context) do
    agent = context.agent
    
    # Create the wake signal
    wake_signal = Signal.new!(
      "sleeper.wake",
      %{scheduled: true},
      source: "/agent/#{agent.id}/cron"
    )

    # Register cron job with the provided schedule
    cron_directive = Directive.cron(
      schedule,
      wake_signal,
      job_id: :wake_schedule
    )

    {:ok, agent, [cron_directive]}
  end
end
```

### 6.3 Wake Action - Triggered by Cron

```elixir
defmodule MyApp.SleeperAgent.WakeAction do
  @moduledoc """
  Handles the wake signal from cron.
  
  Transitions agent from sleeping to working, does work, then sleeps again.
  """

  use Jido.Action,
    name: "sleeper.wake",
    description: "Wake up and do work",
    schema: [
      scheduled: [type: :boolean, default: false, doc: "Whether triggered by scheduler"]
    ]

  require Logger

  def run(params, context) do
    agent = context.agent
    
    Logger.info("""
    Agent #{agent.id} waking up!
    - Triggered by scheduler: #{params.scheduled}
    - Previous status: #{agent.state.status}
    - Work count so far: #{agent.state.work_count}
    """)

    # Transition to working state
    {:ok, working_agent} = MyApp.SleeperAgent.set(agent, %{
      status: :working,
      last_wake_time: DateTime.utc_now()
    })

    # Simulate doing work
    do_scheduled_work(working_agent)

    # Transition back to sleeping
    {:ok, sleeping_agent} = MyApp.SleeperAgent.set(working_agent, %{
      status: :sleeping,
      work_count: agent.state.work_count + 1
    })

    Logger.info("Agent #{agent.id} going back to sleep. Total work cycles: #{sleeping_agent.state.work_count}")

    {:ok, sleeping_agent, []}
  end

  defp do_scheduled_work(agent) do
    # This is where you'd do actual scheduled work:
    # - Fetch data from APIs
    # - Process queued items
    # - Generate reports
    # - Send notifications
    # - Sync with external systems
    
    Logger.info("Agent #{agent.id} performing scheduled work...")
    Process.sleep(100)  # Simulate work
    :ok
  end
end
```

### 6.4 Complete Usage Example

```elixir
defmodule MyApp.CronExample do
  @moduledoc """
  Example showing full cron workflow with agents.
  """

  alias Jido.Signal
  alias Jido.AgentServer

  def run_example do
    IO.puts("=== Jido Cron Scheduling Example ===\n")

    # 1. Start the sleeper agent
    {:ok, _pid} = AgentServer.start(
      agent: MyApp.SleeperAgent,
      id: "sleeper-001"
    )
    IO.puts("✓ Started SleeperAgent with id 'sleeper-001'")

    # 2. Configure it to wake every minute
    configure_signal = Signal.new!(
      "sleeper.configure",
      %{schedule: "* * * * *"},  # Every minute
      source: "/example"
    )
    :ok = AgentServer.cast("sleeper-001", configure_signal)
    IO.puts("✓ Configured wake schedule: every minute")

    # 3. Check state
    {:ok, state} = AgentServer.state("sleeper-001")
    IO.puts("✓ Agent status: #{state.agent.state.status}")
    IO.puts("✓ Registered cron jobs: #{inspect(Map.keys(state.cron_jobs))}")

    IO.puts("\nAgent will now wake up every minute automatically.")
    IO.puts("Watch the logs for 'Agent sleeper-001 waking up!' messages.\n")

    # 4. After some time, you can stop the cron (or just stop the agent)
    # stop_cron_signal = Signal.new!("sleeper.stop.cron", %{}, source: "/example")
    # :ok = AgentServer.cast("sleeper-001", stop_cron_signal)

    :ok
  end

  def stop_example do
    # Stopping the agent automatically cleans up its cron jobs
    case AgentServer.whereis("sleeper-001") do
      nil ->
        IO.puts("Agent not running")

      pid ->
        GenServer.stop(pid)
        IO.puts("✓ Stopped agent and cleaned up cron jobs")
    end
  end
end
```

---

## 7. Lifecycle Management

### 7.1 Job Registration

- Jobs are registered in system-wide `Jido.Scheduler` (Quantum)
- Job names are scoped: `jido_cron:<agent_id>:<job_id>`
- Logical ownership tracked in `AgentServer.State.cron_jobs`

### 7.2 Job Upsert

- Same `job_id` replaces existing job (upsert semantics)
- Useful for changing schedules dynamically

### 7.3 Cleanup Scenarios

| Scenario | Behavior |
|----------|----------|
| Normal stop (`Directive.Stop` or supervisor) | `terminate/2` deletes all agent's cron jobs |
| Crash + restart (supervised) | Jobs continue working (bound to `id` not `pid`) |
| Permanent removal (no restart) | Jobs fire but `AgentServer.cast/2` returns `{:error, :not_found}` (no-op) |

### 7.4 Zombie Job Prevention

For production systems, consider adding a background sweeper:

```elixir
defmodule Jido.Cron.Reaper do
  @moduledoc """
  Optional background process that cleans up orphaned cron jobs.
  
  Periodically scans Jido.Scheduler jobs and removes any whose
  agent_id no longer exists in Jido.Registry.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval, :timer.minutes(5))
    schedule_sweep(interval)
    {:ok, %{interval: interval}}
  end

  def handle_info(:sweep, state) do
    sweep_orphaned_jobs()
    schedule_sweep(state.interval)
    {:noreply, state}
  end

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp sweep_orphaned_jobs do
    Jido.Scheduler.jobs()
    |> Enum.filter(&orphaned_job?/1)
    |> Enum.each(fn {name, _job} ->
      Jido.Scheduler.delete_job(name)
    end)
  end

  defp orphaned_job?({name, _job}) do
    case parse_job_name(name) do
      {:ok, agent_id, _job_id} ->
        Jido.AgentServer.whereis(agent_id) == nil

      :error ->
        false  # Not a Jido cron job
    end
  end

  defp parse_job_name(name) do
    case Atom.to_string(name) do
      "jido_cron:" <> rest ->
        [agent_id | _] = String.split(rest, ":", parts: 2)
        {:ok, agent_id, rest}

      _ ->
        :error
    end
  end
end
```

---

## 8. Testing

### 8.1 Unit Test for Cron Directive

```elixir
defmodule Jido.Agent.Directive.CronTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.Cron

  test "creates cron directive with required fields" do
    directive = Directive.cron("* * * * *", :tick_message)

    assert %Cron{} = directive
    assert directive.cron == "* * * * *"
    assert directive.message == :tick_message
    assert directive.job_id == nil
  end

  test "creates cron directive with job_id and timezone" do
    directive = Directive.cron(
      "@daily",
      :daily_task,
      job_id: :cleanup,
      timezone: "America/New_York"
    )

    assert directive.job_id == :cleanup
    assert directive.timezone == "America/New_York"
  end
end
```

### 8.2 Integration Test

```elixir
defmodule Jido.AgentServer.CronIntegrationTest do
  use ExUnit.Case

  alias Jido.AgentServer
  alias Jido.Signal

  setup do
    # Ensure scheduler is running
    start_supervised!(Jido.Scheduler)
    :ok
  end

  test "agent can register and receive cron signals" do
    # Start test agent
    {:ok, pid} = AgentServer.start(agent: TestCronAgent, id: "test-cron-1")

    # Register a cron job (use very short interval for testing)
    # Note: For real tests, mock the scheduler or use :run_job/1
    register_signal = Signal.new!("test.register.cron", %{}, source: "/test")
    :ok = AgentServer.cast("test-cron-1", register_signal)

    # Verify job was registered
    {:ok, state} = AgentServer.state("test-cron-1")
    assert Map.has_key?(state.cron_jobs, :test_job)

    # Clean up
    GenServer.stop(pid)

    # Verify job was removed
    jobs = Jido.Scheduler.jobs()
    refute Enum.any?(jobs, fn {name, _} ->
      String.contains?(Atom.to_string(name), "test-cron-1")
    end)
  end
end
```

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Job leaks if terminate not called | Always track jobs in state; add optional Reaper |
| Heavy work in cron tasks | Keep task minimal (just `cast/2`); work happens in agent |
| Invalid cron expressions | Validate in executor; return `%Directive.Error{}` on parse failure |
| Job name collisions | Always include `agent_id` in job name |
| Timezone issues | Use standard IANA timezone names; require `tzdata` for non-UTC |

---

## 10. Future Enhancements

### 10.1 Introspection API

```elixir
# List all cron jobs for an agent
Jido.AgentServer.list_cron_jobs("my-agent")

# Get next run time
Jido.AgentServer.cron_next_run("my-agent", :heartbeat)
```

### 10.2 Pause/Resume

```elixir
Directive.cron_pause(:heartbeat)
Directive.cron_resume(:heartbeat)
```

### 10.3 Telemetry

```elixir
:telemetry.execute(
  [:jido, :cron, :fire],
  %{count: 1},
  %{agent_id: "my-agent", job_id: :heartbeat}
)
```

### 10.4 Clustering

For multi-node deployments, consider:
- Using Quantum's clustering support
- Or using a distributed scheduler like `Oban` with `Oban.Plugins.Cron`

---

## 11. Implementation Checklist

- [ ] Start `Jido.Scheduler` in `Application.ex`
- [ ] Add `cron_jobs` field to `AgentServer.State`
- [ ] Create `Jido.Agent.Directive.Cron` module
- [ ] Create `Jido.Agent.Directive.CronCancel` module
- [ ] Add helper constructors (`cron/3`, `cron_cancel/1`)
- [ ] Implement `DirectiveExec` for `Cron`
- [ ] Implement `DirectiveExec` for `CronCancel`
- [ ] Create `Jido.AgentServer.Signal.CronTick` signal
- [ ] Add cleanup in `AgentServer.terminate/2`
- [ ] Write unit tests
- [ ] Write integration tests
- [ ] Update documentation
- [ ] Add example to `examples/` directory
