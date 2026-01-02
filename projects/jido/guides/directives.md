# Directives

Directives are **pure descriptions of external effects**. Agents emit them from `cmd/2` callbacks; the runtime (`AgentServer`) executes them.

**Key principle**: Directives never modify agent state — state changes happen in the returned agent struct.

```elixir
def cmd({:notify_user, message}, agent, _context) do
  signal = Jido.Signal.new!(type: "notification.sent", data: %{message: message})
  
  {:ok, agent, [Directive.emit(signal)]}
end
```

## Core Directives

| Directive | Purpose | Tracking |
|-----------|---------|----------|
| `Emit` | Dispatch a signal via configured adapters | — |
| `Error` | Signal an error from cmd/2 | — |
| `Spawn` | Spawn generic BEAM child process | None (fire-and-forget) |
| `SpawnAgent` | Spawn child Jido agent with hierarchy | Full (monitoring, exit signals) |
| `StopChild` | Gracefully stop a tracked child agent | Uses children map |
| `Schedule` | Schedule a delayed message | — |
| `Stop` | Stop the agent process (self) | — |
| `Cron` | Recurring scheduled execution | — |
| `CronCancel` | Cancel a cron job | — |

## Helper Constructors

```elixir
alias Jido.Agent.Directive

# Emit signals
Directive.emit(signal)
Directive.emit(signal, {:pubsub, topic: "events"})
Directive.emit_to_pid(signal, pid)
Directive.emit_to_parent(agent, signal)

# Spawn processes
Directive.spawn(child_spec)
Directive.spawn_agent(MyWorkerAgent, :worker_1)
Directive.spawn_agent(MyWorkerAgent, :processor, opts: %{initial_state: %{batch_size: 100}})

# Stop processes
Directive.stop_child(:worker_1)
Directive.stop()
Directive.stop(:shutdown)

# Scheduling
Directive.schedule(5000, :timeout)
Directive.cron("*/5 * * * *", :tick, job_id: :heartbeat)
Directive.cron_cancel(:heartbeat)

# Errors
Directive.error(Jido.Error.validation_error("Invalid input"))
```

## Spawn vs SpawnAgent

| `Spawn` | `SpawnAgent` |
|---------|--------------|
| Generic Tasks/GenServers | Child Jido agents |
| Fire-and-forget | Full hierarchy tracking |
| No monitoring | Monitors child, receives exit signals |
| — | Enables `emit_to_parent/3` |

```elixir
# Fire-and-forget task
Directive.spawn({Task, :start_link, [fn -> send_webhook(url) end]})

# Tracked child agent
Directive.spawn_agent(WorkerAgent, :worker_1, opts: %{initial_state: state})
```

## Custom Directives

External packages can define their own directives:

```elixir
defmodule MyApp.Directive.CallLLM do
  defstruct [:model, :prompt, :tag]
end
```

The runtime dispatches on struct type — no core changes needed. Implement a custom `AgentServer` or middleware to handle your directive types.

---

See `Jido.Agent.Directive` moduledoc for the complete API reference.
