# Jido Sensor Plan for 2.0

## Executive Summary

Sensors are **sidecar GenServers** that bridge external events (webhooks, PubSub, timers, file watchers, etc.) into Jido Signals and inject them into Agents. They are the "eyes and ears" of agent-based applications.

**Core Principle**: Agents remain pure (via `cmd/2`). Sensors are part of the IO/runtime layer that feeds signals to agents.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    External World                            │
│  (Phoenix PubSub, Webhooks, File System, Timers, etc.)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Jido.Sensor                             │
│  GenServer that observes events and emits Jido.Signal        │
│  - mount/1: subscribe to sources                            │
│  - handle_event/3: translate events → signals               │
│  - shutdown/2: cleanup                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ AgentServer.cast(signal)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Jido.AgentServer                          │
│  - Receives signal                                          │
│  - Routes to agent's handle_signal/2                        │
│  - Executes resulting directives                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Pure Agent                              │
│  cmd/2 → {agent, directives}                                │
│  handle_signal/2 → {agent, directives}                      │
└─────────────────────────────────────────────────────────────┘
```

## Design Decisions

### 1. Sensors as Separate GenServers

**Decision**: Keep Sensors as standalone GenServer processes, not integrated into Agent structs.

**Rationale**:
- Maintains agent purity (agents remain pure `cmd/2` functions)
- Clear separation: Agents "think", Sensors "perceive"
- Sensors can be shared across multiple agents
- Sensors can be supervised independently
- Matches Jido 2.0's directive-based IO model

### 2. Signal Injection via `AgentServer.cast/2`

**Decision**: Sensors inject signals into agents by calling `AgentServer.cast(target, signal)`.

**Rationale**:
- Uses existing infrastructure (no new injection mechanisms)
- Works with agent IDs, PIDs, or via-tuples
- Consistent with how external systems send signals to agents
- Sensors don't need to know about agent internals

### 3. Use Existing `%Directive.Spawn{}` for Sensor Spawning

**Decision**: No new `SpawnSensor` directive. Use `%Directive.Spawn{}` with a helper function.

**Rationale**:
- Sensors are just processes, not agents needing parent-child semantics
- Keeps directive set minimal
- Can add `SpawnSensor` later if more lifecycle control is needed
- Fire-and-forget spawning is sufficient for v1

### 4. Configuration via Zoi Schemas

**Decision**: Use Zoi schemas (consistent with Jido 2.0) instead of NimbleOptions.

**Rationale**:
- Consistent with rest of codebase
- Single source of truth for fields, types, and validation
- Better error messages

## API Design

### `use Jido.Sensor` Macro

```elixir
defmodule Jido.Sensor do
  @moduledoc """
  Behavior for implementing sensors that bridge external events into Jido Signals.
  
  Sensors are GenServers that:
  1. Observe external events (timers, PubSub, file changes, etc.)
  2. Translate events into Jido Signals
  3. Emit signals to a configured target (agent, bus, pubsub)
  """

  @type state :: term()

  defmodule Context do
    @moduledoc "Runtime context for a sensor instance"
    
    @type t :: %__MODULE__{
      id: String.t(),
      name: String.t(),
      config: map(),
      target: target(),
      meta: map()
    }
    
    @type target ::
      pid()
      | String.t()                    # agent ID
      | {:agent, String.t()}          # explicit agent
      | {:via, module(), term()}      # via-tuple
      | {:pubsub, keyword()}          # PubSub dispatch
      | {:bus, keyword()}             # Bus dispatch

    defstruct [:id, :name, :config, :target, meta: %{}]
  end

  @doc "Initialize sensor state and set up event subscriptions"
  @callback mount(Context.t()) ::
    {:ok, state()}
    | {:ok, state(), [Jido.Signal.t()]}
    | {:error, term()}

  @doc "Handle an external event and optionally emit signals"
  @callback handle_event(event :: term(), state(), Context.t()) ::
    {:noreply, state()}
    | {:noreply, state(), [Jido.Signal.t()]}

  @doc "Cleanup when sensor stops"
  @callback shutdown(state(), Context.t()) :: :ok

  @optional_callbacks shutdown: 2
end
```

### Sensor Implementation Pattern

```elixir
defmodule MyApp.Sensors.Heartbeat do
  @moduledoc "Emits periodic heartbeat signals to an agent"
  
  use Jido.Sensor,
    name: "heartbeat",
    description: "Periodic heartbeat signal emitter",
    schema: %{
      interval_ms: Zoi.integer() |> Zoi.min(100) |> Zoi.default(5_000),
      message: Zoi.string() |> Zoi.default("heartbeat")
    }

  @impl Jido.Sensor
  def mount(%Context{config: config} = ctx) do
    schedule_tick(config.interval_ms)
    {:ok, %{count: 0, message: config.message}}
  end

  @impl Jido.Sensor
  def handle_event(:tick, state, %Context{} = ctx) do
    signal = Jido.Signal.new!(
      "sensor.heartbeat",
      %{count: state.count + 1, message: state.message},
      source: "/sensor/#{ctx.name}:#{ctx.id}"
    )
    
    schedule_tick(ctx.config.interval_ms)
    {:noreply, %{state | count: state.count + 1}, [signal]}
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end
end
```

### Sensor Dispatch Helper

```elixir
defmodule Jido.Sensor.Dispatch do
  @moduledoc "Handles signal emission from sensors to targets"

  alias Jido.AgentServer
  alias Jido.Signal

  @spec emit(Signal.t() | [Signal.t()] | nil, Jido.Sensor.Context.t()) :: :ok
  def emit(nil, _ctx), do: :ok
  def emit([], _ctx), do: :ok
  def emit(%Signal{} = sig, ctx), do: emit([sig], ctx)

  def emit(signals, %Jido.Sensor.Context{target: target}) when is_list(signals) do
    Enum.each(signals, &deliver(&1, target))
    :ok
  end

  defp deliver(signal, target) when is_pid(target) do
    AgentServer.cast(target, signal)
  end

  defp deliver(signal, target) when is_binary(target) do
    AgentServer.cast(target, signal)
  end

  defp deliver(signal, {:agent, id}) when is_binary(id) do
    AgentServer.cast(id, signal)
  end

  defp deliver(signal, {:via, _, _} = via) do
    AgentServer.cast(via, signal)
  end

  defp deliver(signal, {:pubsub, opts}) do
    Jido.Signal.Dispatch.dispatch(signal, {:pubsub, opts})
  end

  defp deliver(signal, {:bus, opts}) do
    Jido.Signal.Dispatch.dispatch(signal, {:bus, opts})
  end

  defp deliver(_signal, _target), do: :ok
end
```

### Directive Helper for Spawning Sensors

```elixir
# In Jido.Agent.Directive

@doc """
Creates a Spawn directive for a Jido Sensor.

## Examples

    Directive.spawn_sensor(MyApp.Sensors.Heartbeat, :heartbeat,
      target: {:agent, agent.id},
      interval_ms: 5_000
    )
"""
@spec spawn_sensor(module(), term(), keyword()) :: Spawn.t()
def spawn_sensor(sensor_mod, tag, opts \\ []) do
  child_spec = sensor_mod.child_spec(opts)
  %Spawn{child_spec: child_spec, tag: tag}
end
```

## Common Patterns

### 1. Timer/Heartbeat Sensor

See `MyApp.Sensors.Heartbeat` above.

### 2. Phoenix PubSub Bridge

```elixir
defmodule MyApp.Sensors.PubSubBridge do
  use Jido.Sensor,
    name: "pubsub_bridge",
    description: "Bridges Phoenix PubSub messages to agent signals",
    schema: %{
      pubsub: Zoi.atom() |> Zoi.required(),
      topic: Zoi.string() |> Zoi.required()
    }

  @impl Jido.Sensor
  def mount(%Context{config: config} = ctx) do
    :ok = Phoenix.PubSub.subscribe(config.pubsub, config.topic)
    {:ok, %{topic: config.topic}}
  end

  @impl Jido.Sensor
  def handle_event(message, state, %Context{} = ctx) do
    signal = Jido.Signal.new!(
      "pubsub.message",
      %{topic: state.topic, payload: message},
      source: "/sensor/#{ctx.name}:#{ctx.id}"
    )
    {:noreply, state, [signal]}
  end
end
```

### 3. Webhook (No Long-Lived Sensor)

For webhooks, you typically don't need a sensor process. Just emit signals directly:

```elixir
defmodule MyApp.WebhookController do
  use Phoenix.Controller
  alias Jido.AgentServer
  alias Jido.Signal

  def github(conn, params) do
    event_type = get_req_header(conn, "x-github-event") |> List.first()
    
    signal = Signal.new!(
      "webhook.github",
      %{event: event_type, payload: params},
      source: "/webhook/github"
    )
    
    :ok = AgentServer.cast("my-agent-id", signal)
    send_resp(conn, 202, "accepted")
  end
end
```

Or use a lightweight helper:

```elixir
defmodule Jido.Sensor.Webhook do
  @moduledoc "Helper for emitting webhook events as signals"

  alias Jido.Signal
  alias Jido.AgentServer

  @spec emit(AgentServer.server(), String.t(), map(), keyword()) :: :ok | {:error, term()}
  def emit(target, type, data, opts \\ []) do
    source = Keyword.get(opts, :source, "/webhook")
    signal = Signal.new!(type, data, source: source)
    AgentServer.cast(target, signal)
  end
end

# Usage in controller:
Jido.Sensor.Webhook.emit("agent-id", "webhook.github", params, source: "/webhook/github")
```

### 4. File Watcher

```elixir
defmodule MyApp.Sensors.FileWatcher do
  use Jido.Sensor,
    name: "file_watcher",
    description: "Monitors file system changes",
    schema: %{
      path: Zoi.string() |> Zoi.required(),
      events: Zoi.list(Zoi.atom()) |> Zoi.default([:modified, :created, :deleted])
    }

  @impl Jido.Sensor
  def mount(%Context{config: config} = _ctx) do
    {:ok, pid} = FileSystem.start_link(dirs: [config.path])
    FileSystem.subscribe(pid)
    {:ok, %{watcher_pid: pid, path: config.path}}
  end

  @impl Jido.Sensor
  def handle_event({:file_event, _pid, {path, events}}, state, %Context{} = ctx) do
    signal = Jido.Signal.new!(
      "file.changed",
      %{path: path, events: events},
      source: "/sensor/#{ctx.name}:#{ctx.id}"
    )
    {:noreply, state, [signal]}
  end

  def handle_event(_other, state, _ctx), do: {:noreply, state}

  @impl Jido.Sensor
  def shutdown(state, _ctx) do
    if state.watcher_pid, do: GenServer.stop(state.watcher_pid)
    :ok
  end
end
```

## Attaching Sensors to Agents

### Option 1: Spawn via Action

```elixir
defmodule MyApp.Agent.Actions.StartMonitoring do
  use Jido.Action, name: "start_monitoring", schema: []

  alias Jido.Agent.Directive

  def run(_params, %{agent: agent}) do
    directives = [
      Directive.spawn_sensor(MyApp.Sensors.Heartbeat, :heartbeat,
        target: {:agent, agent.id},
        interval_ms: 10_000
      ),
      Directive.spawn_sensor(MyApp.Sensors.FileWatcher, :file_watcher,
        target: {:agent, agent.id},
        path: "/var/log/app.log"
      )
    ]
    
    {:ok, %{}, directives}
  end
end
```

### Option 2: Start Alongside Agent (Supervisor)

```elixir
defmodule MyApp.AgentSupervisor do
  use Supervisor

  def start_link(agent_opts) do
    Supervisor.start_link(__MODULE__, agent_opts)
  end

  def init(agent_opts) do
    agent_id = agent_opts[:id] || Jido.Util.generate_id()
    
    children = [
      {Jido.AgentServer, Keyword.put(agent_opts, :id, agent_id)},
      {MyApp.Sensors.Heartbeat, [
        id: "heartbeat_#{agent_id}",
        target: {:agent, agent_id},
        interval_ms: 5_000
      ]}
    ]
    
    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

### Option 3: Direct Start (Testing/Dev)

```elixir
# Start agent
{:ok, agent_pid} = Jido.AgentServer.start(agent: MyAgent, id: "test-agent")

# Start sensor pointing at agent
{:ok, _sensor} = MyApp.Sensors.Heartbeat.start_link(
  id: "heartbeat-1",
  target: agent_pid,  # or {:agent, "test-agent"}
  interval_ms: 1_000
)
```

## Implementation Plan

### Phase 1: Core Infrastructure (Priority: High)

1. **`Jido.Sensor` behaviour module**
   - Define callbacks: `mount/1`, `handle_event/3`, `shutdown/2`
   - `use Jido.Sensor` macro generating GenServer boilerplate
   - `Jido.Sensor.Context` struct

2. **`Jido.Sensor.Dispatch` module**
   - Signal emission to various targets
   - Integration with `Jido.AgentServer.cast/2`

3. **`Jido.Agent.Directive.spawn_sensor/3` helper**
   - Convenience for spawning sensors via directives

### Phase 2: Built-in Sensors (Priority: Medium)

1. **`Jido.Sensors.Heartbeat`**
   - Periodic heartbeat signals
   - Configurable interval and message

2. **`Jido.Sensors.Cron`**
   - Cron expression-based scheduling
   - Job management (add/remove/list)

3. **`Jido.Sensor.Webhook` helper**
   - Lightweight helper for webhook → signal conversion
   - No long-lived process needed

### Phase 3: Documentation & Examples (Priority: Medium)

1. Update `guides/sensors/overview.md`
2. Create example: `examples/sensor_demo.exs`
3. Add tests: `test/jido/sensor_test.exs`

### Phase 4: Advanced Features (Priority: Low, Future)

1. **Sensor Registry**
   - List active sensors per agent
   - Dynamic introspection

2. **Shared Sensors**
   - One sensor feeding multiple agents
   - Routing configuration

3. **Lifecycle Management**
   - `StopSensor` directive
   - Dynamic reconfiguration

## File Structure

```
lib/jido/
├── sensor.ex                    # Behaviour + use macro
├── sensor/
│   ├── context.ex              # Jido.Sensor.Context struct
│   └── dispatch.ex             # Signal emission helper
├── sensors/                     # Built-in sensors
│   ├── heartbeat.ex
│   └── cron.ex
├── agent/
│   └── directive.ex            # Add spawn_sensor/3 helper
```

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Target misconfiguration (signals disappear) | Validate target at mount time, log warnings |
| Unbounded sensor spawning | Document best practices, provide examples |
| Noisy sensors overwhelming agents | Encourage throttling in handle_event, document backpressure patterns |
| Sensor lifecycle coordination | Rely on supervisor tree for v1, add explicit stop later if needed |

## Example: Complete Sensor Demo

See `examples/sensor_demo.exs` for a working example demonstrating:
- Custom sensor implementation
- Sensor → Agent signal flow
- Agent reacting to sensor signals
- Sensor spawning via directive
