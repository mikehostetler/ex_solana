# JIDO_SENSOR_V2 Plan

## 0. TL;DR

Jido.Sensor v2 mirrors Agent2:

- **Pure core**: `Jido.Sensor` is a small, Zoi‑based data structure + minimal behaviour for turning external events into `Jido.Signal`s.
- **Separate process**: `Jido.SensorServer` is the generic GenServer that owns a `%Jido.Sensor{}` and runs the behaviour callbacks.
- **Signal/Effect split**:
  - Sensors **emit Signals** only.
  - Agents **emit Effects** (including sensor lifecycle Effects).
- **1:1 Ownership**: Each sensor is owned by exactly one AgentServer. Sensors live in the agent's process tree and die with their agent.

This keeps sensors simple, testable, and consistent with the Agent2 + Effects core thesis.

### Process Tree Model

```
AgentSupervisor (one_for_all or rest_for_one)
├── AgentServer (GenServer) ─────────────────── the "brain"
└── AgentSensorSupervisor (DynamicSupervisor) ─ owns all sensors
    ├── SensorServer (heartbeat)
    ├── SensorServer (webhook)
    └── SensorServer (pubsub subscription)
```

**Key invariant**: A v2 sensor has exactly **one target** (its owning AgentServer). If multiple agents need the same external data, each starts its own sensor instance.

---

## 1. Goals & Scope

### Goals

1. Align sensors with Agent2 and the core thesis:
   - Sensor = "eyes & ears" → external events → `Jido.Signal`.
   - Agent = "brain" → `(state, signal) → {:ok, new_state, [Effect.t()]}`.
2. Separate **pure config/data** from **OTP/GenServer**:
   - `%Jido.Sensor{}`: identity, config, target, meta.
   - `Jido.SensorServer`: process that runs callbacks and dispatches signals.
3. Integrate with the **Effect model**:
   - Agents start/stop/reconfigure sensors via Effects.
   - AgentServer interprets those Effects into sensor process operations.
4. Use **Zoi** for sensor schemas and compile‑time config (with transitional NimbleOptions support).
5. Minimize callback surface; retain conceptual continuity with v1 (`mount`, "deliver signal", `shutdown`).

### Non-goals (for v2 baseline)

- No global, cross‑agent sensor routing bus yet (can be layered on later via `Jido.SignalBus`).
- No multi-target sensors; each sensor reports to exactly one agent.
- No full rework of all existing sensors; v2 coexists with v1 and provides a migration path.

### Design Principles

1. **1:1 Ownership**: One sensor → one agent. No shared sensors in v2 baseline.
2. **Lifecycle coupling**: Sensor dies when its agent dies (same supervision tree).
3. **Simple routing**: `send(target, {:signal, signal})` — no subscription tables or fan-out.
4. **Effect-driven lifecycle**: Agents control sensors via `StartSensor`, `StopSensor`, `ConfigureSensor` Effects.
5. **Intentional duplication**: If multiple agents need the same data, each starts its own sensor. This is cheap for timers/pubsub and provides better isolation.

---

## 2. Current v1 Sensor Architecture (Quick Recap)

From main branch:

- Each sensor is a **GenServer module** implementing a behaviour with callbacks:
  - `mount/1` – startup, subscription, initial state.
  - `deliver_signal/1` – translate some external event to a `Jido.Signal` and send it back to the agent.
  - `shutdown/1` – cleanup on termination.
- Sensors are started as **children of agents**; they know their target agent (often via PID or registration) and send signals directly.
- Config is validated via **NimbleOptions**.
- Routing is **target‑based**: signals carry a `target` that tells the existing infra how to deliver them.

### Pain Points Relative to Agent2

| Issue | Description |
|-------|-------------|
| Mixed concerns | Sensor data, config, and process logic all in one module |
| No Effects integration | Starting/stopping sensors is ad‑hoc, agent‑specific |
| No signal‑driven story | Doesn't integrate with `handle_signal/2` + Effects model |
| Heavy boilerplate | Each sensor duplicates GenServer setup |

---

## 3. Target Design: Jido.Sensor v2

### 3.1 Core Data Model (Zoi struct)

**Essence**: a Sensor is just **identity + target + config + runtime meta**. No GenServer/OTP concerns in the struct.

```elixir
defmodule Jido.Sensor do
  @moduledoc """
  Core Sensor data structure and pure utilities.

  Knows nothing about GenServer/OTP. Process concerns live in Jido.SensorServer.
  """

  alias Jido.Sensor

  @schema Zoi.struct(
            __MODULE__,
            %{
              id:
                Zoi.string(description: "Unique sensor identifier")
                |> Zoi.optional(),
              name:
                Zoi.string(description: "Sensor name")
                |> Zoi.optional(),
              description:
                Zoi.string(description: "What this sensor observes")
                |> Zoi.optional(),
              category:
                Zoi.atom(description: "Sensor category")
                |> Zoi.optional(),
              tags:
                Zoi.list(Zoi.string(), description: "Tags")
                |> Zoi.default([]),
              vsn:
                Zoi.string(description: "Version")
                |> Zoi.optional(),
              # Who this sensor is reporting to; usually an AgentServer
              target:
                Zoi.any(
                  description:
                    "Where signals should be sent (e.g., agent pid, {:agent, id}, etc.)"
                )
                |> Zoi.optional(),
              # Schema for runtime config (Zoi or NimbleOptions, like Agent2)
              config_schema:
                Zoi.any(
                  description:
                    "NimbleOptions or Zoi schema for validating the Sensor's config."
                )
                |> Zoi.default([]),
              # Runtime config (validated)
              config:
                Zoi.map(description: "Current sensor configuration/options")
                |> Zoi.default(%{}),
              status:
                Zoi.atom(description: "Runtime status")
                |> Zoi.default(:idle),
              meta:
                Zoi.map(description: "Opaque runtime metadata")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Sensor."
  def schema, do: @schema

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs \\ %{}) do
    Zoi.cast(@schema, attrs)
  end

  @spec set_config(t(), map() | keyword()) :: {:ok, t()} | {:error, term()}
  def set_config(%Sensor{config_schema: schema} = sensor, attrs) do
    with {:ok, config} <- Jido.Schema.validate(schema, attrs) do
      {:ok, %{sensor | config: config}}
    end
  end
end
```

Notes:

- `config_schema` uses `Zoi.any/1` to support both NimbleOptions and Zoi (transitional, mirroring Agent2).
- No GenServer state or references to processes; `%Sensor{}` is safe to construct and test in isolation.

### 3.2 Compile-time Config for `use Jido.Sensor`

Similar to Agent2, sensors get a small compile‑time config schema:

```elixir
@sensor_config_schema Zoi.object(%{
  name:
    Zoi.string(description: "Sensor name")
    |> Zoi.refine({Jido.Util, :validate_name, []}),
  description:
    Zoi.string(description: "What this sensor observes")
    |> Zoi.optional(),
  category:
    Zoi.atom(description: "Sensor category")
    |> Zoi.optional(),
  tags:
    Zoi.list(Zoi.string(), description: "Tags")
    |> Zoi.default([]),
  vsn:
    Zoi.string(description: "Version")
    |> Zoi.optional(),
  # Runtime config schema (Zoi or NimbleOptions)
  schema:
    Zoi.any(description: "Config schema for this sensor")
    |> Zoi.default([]),
  # Default target
  default_target:
    Zoi.any(description: "Default signal target for this sensor")
    |> Zoi.optional()
})
```

`use Jido.Sensor, ...` should:

1. Validate compile‑time options with `@sensor_config_schema`.
2. Store them in module attributes.
3. Provide helpers: `name/0`, `description/0`, `config_schema/0`, `default_target/0`.
4. Inject a `new/1` builder:

```elixir
def new(attrs \\ %{}) do
  Jido.Sensor.new(
    Map.merge(
      %{
        name: name(),
        description: description(),
        config_schema: config_schema()
      },
      Map.new(attrs)
    )
  )
end
```

---

### 3.3 Process Model: `Jido.SensorServer`

`Jido.SensorServer` is the one generic GenServer for all sensors, analogous to `Jido.AgentServer`.

**Responsibilities:**

- Owns a `%Jido.Sensor{}` value.
- Runs the sensor behaviour callbacks.
- Dispatches `Jido.Signal`s to the configured target.
- Supports lifecycle operations (start/stop/reconfigure) driven by Effects.

```elixir
defmodule Jido.SensorServer do
  use GenServer

  defstruct [:module, :sensor, :context]

  @type state :: %__MODULE__{
          module: module(),
          sensor: Jido.Sensor.t(),
          context: map()
        }

  ## Public API

  def start_link(module, init_opts) do
    GenServer.start_link(__MODULE__, {module, init_opts})
  end

  def reconfigure(server, config_patch) do
    GenServer.cast(server, {:reconfigure, config_patch})
  end

  ## GenServer callbacks

  @impl true
  def init({module, init_opts}) do
    {:ok, sensor} = module.new(init_opts)
    context = Map.get(init_opts, :context, %{})

    case maybe_mount(module, sensor, context) do
      {:ok, sensor, signals} ->
        dispatch_signals(sensor, signals)
        {:ok, %__MODULE__{module: module, sensor: sensor, context: context}}

      {:ok, sensor} ->
        {:ok, %__MODULE__{module: module, sensor: sensor, context: context}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:reconfigure, patch}, %{module: mod, sensor: sensor, context: ctx} = s) do
    case mod.handle_reconfigure(sensor, patch, ctx) do
      {:ok, sensor} -> {:noreply, %{s | sensor: sensor}}
      {:error, reason} -> {:stop, reason, s}
    end
  end

  @impl true
  def handle_info(msg, %{module: mod, sensor: sensor, context: ctx} = s) do
    case mod.dispatch_signal(sensor, msg, ctx) do
      {:ok, sensor, signals} ->
        dispatch_signals(sensor, signals)
        {:noreply, %{s | sensor: sensor}}

      {:noreply, sensor} ->
        {:noreply, %{s | sensor: sensor}}

      {:stop, reason, sensor} ->
        {:stop, reason, %{s | sensor: sensor}}
    end
  end

  @impl true
  def terminate(reason, %{module: mod, sensor: sensor, context: ctx}) do
    mod.shutdown(sensor, reason, ctx)
  end

  defp maybe_mount(mod, sensor, ctx) do
    if function_exported?(mod, :mount, 2) do
      mod.mount(sensor, ctx)
    else
      {:ok, sensor}
    end
  end

  defp dispatch_signals(%Jido.Sensor{target: target}, signals) do
    Jido.Signal.Router.dispatch(signals, target)
  end
end
```

Notes:

- `handle_info/2` is completely generic: all messages become **events** passed to `dispatch_signal/3` in the sensor module.
- `dispatch_signals/2` is pluggable – v2 baseline uses **simple direct sends** to an AgentServer PID.

---

### 3.4 Sensor Behaviour: Minimal Callback Set

To keep things small but expressive, v2 sensors get **3 process‑level callbacks** (plus 1 optional):

```elixir
defmodule Jido.SensorBehaviour do
  @moduledoc """
  Behaviour for Sensor v2 modules.
  """

  alias Jido.{Sensor, Signal}

  @doc """
  Called when the sensor starts. Use to subscribe to external sources,
  set up timers, etc. May return initial signals to emit.
  """
  @callback mount(sensor :: Sensor.t(), context :: map()) ::
              {:ok, Sensor.t()}
              | {:ok, Sensor.t(), [Signal.t()]}
              | {:error, term()}

  @doc """
  Dispatch signals in response to an external event.
  Receives a message/event, translates it into zero or more Signals to dispatch to the agent.
  """
  @callback dispatch_signal(sensor :: Sensor.t(), event :: term(), context :: map()) ::
              {:ok, Sensor.t(), [Signal.t()]}
              | {:noreply, Sensor.t()}
              | {:stop, reason :: term(), Sensor.t()}

  @doc """
  Handle runtime reconfiguration of the sensor.
  """
  @callback handle_reconfigure(sensor :: Sensor.t(), patch :: map(), context :: map()) ::
              {:ok, Sensor.t()} | {:error, term()}

  @doc """
  Called on shutdown. Use to unsubscribe, clean up resources.
  """
  @callback shutdown(sensor :: Sensor.t(), reason :: term(), context :: map()) :: :ok

  @optional_callbacks mount: 2, handle_reconfigure: 3, shutdown: 3
end
```

### Callback Mapping: v1 → v2

| v1 Callback | v2 Callback | Changes |
|-------------|-------------|---------|
| `mount/1` | `mount/2` | Add `context` param; can return initial signals |
| `deliver_signal/1` | `dispatch_signal/3` | Same verb; receives events, returns signals to dispatch |
| `shutdown/1` | `shutdown/3` | Add `reason` and `context` params |
| — | `handle_reconfigure/3` | New: runtime config updates |

---

### 3.5 Routing: How Sensors Talk to Agents

**Baseline (simple):**

Each sensor has a `target` field (often an AgentServer PID). Signals are dispatched directly:

```elixir
defmodule Jido.Signal.Router do
  alias Jido.Signal

  @spec dispatch([Signal.t()], pid() | nil) :: :ok
  def dispatch(_signals, nil), do: :ok

  def dispatch(signals, pid) when is_pid(pid) do
    Enum.each(signals, fn signal ->
      send(pid, {:signal, signal})
    end)
  end

  # Future: support {:agent, id}, topics, etc.
end
```

`AgentServer` implements `handle_info({:signal, signal}, state)` to invoke the agent module's `handle_signal/2`.

**Future‑ready:**

- `Signal.target` can carry richer routing (`{:agent, id}`, topic, etc.)
- `Signal.Router` can evolve into a multi‑tenant bus without changing sensor APIs.

---

### 3.6 Integration with Agent2, handle_signal/2, and Effects

The intended loop:

```
┌────────────────────────────────────────────────────────────────────┐
│ External World                                                       │
│ (webhooks, timers, message queues, etc.)                            │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ events
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│ SensorServer                                                         │
│ handle_info → module.dispatch_signal → [Signal.t()]                 │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ dispatch to target
                               ▼
┌────────────────────────────────────────────────────────────────────┐
│ AgentServer                                                          │
│ handle_info({:signal, signal})                                      │
│   → module.handle_signal(agent, signal)                             │
│   → {:ok, new_agent, [Effect.t()]}                                  │
│   → execute effects (run actions, start/stop sensors, etc.)         │
└────────────────────────────────────────────────────────────────────┘
```

### Sensor Lifecycle Effects

New Effect types for sensor lifecycle:

```elixir
defmodule Jido.Effect.StartSensor do
  @moduledoc "Effect to start a sensor under the AgentServer"
  defstruct [:id, :module, :config, :target]
end

defmodule Jido.Effect.StopSensor do
  @moduledoc "Effect to stop a running sensor"
  defstruct [:id]
end

defmodule Jido.Effect.ConfigureSensor do
  @moduledoc "Effect to reconfigure a running sensor"
  defstruct [:id, :config_patch]
end
```

In `AgentServer`'s effect executor:

- `%Effect.StartSensor{}`:
  - Starts a `Jido.SensorServer` child under an agent‑local DynamicSupervisor.
  - Passes `target: self()` (the AgentServer pid) by default.
  - Stores `id -> pid` mapping in AgentServer state.
- `%Effect.StopSensor{}`:
  - Looks up pid by id and stops the child.
- `%Effect.ConfigureSensor{}`:
  - Looks up pid and sends `Jido.SensorServer.reconfigure/2`.

---

## 4. Lifecycle: Start / Stop / Reconfigure

### 4.1 Starting a Sensor from handle_signal/2

```elixir
def handle_signal(agent, %Signal{type: "user.subscribed", data: %{user_id: user_id}}) do
  effects = [
    %Jido.Effect.StartSensor{
      id: "user_#{user_id}_stream",
      module: MyApp.UserStreamSensor,
      config: %{user_id: user_id},
      target: :self  # AgentServer will resolve to its own pid
    }
  ]

  {:ok, agent, effects}
end
```

### 4.2 Stopping a Sensor

```elixir
def handle_signal(agent, %Signal{type: "user.unsubscribed", data: %{user_id: user_id}}) do
  effects = [
    %Jido.Effect.StopSensor{id: "user_#{user_id}_stream"}
  ]

  {:ok, agent, effects}
end
```

### 4.3 Reconfiguring a Sensor

```elixir
def handle_signal(agent, %Signal{type: "config.updated"}) do
  effects = [
    %Jido.Effect.ConfigureSensor{
      id: "user_123_stream",
      config_patch: %{poll_interval_ms: 1_000}
    }
  ]

  {:ok, agent, effects}
end
```

---

## 5. Example Sensors

### 5.1 Heartbeat Sensor (Timer-based)

```elixir
defmodule MyApp.Sensors.Heartbeat do
  use Jido.Sensor,
    name: "heartbeat",
    description: "Emits periodic heartbeat signals",
    schema: [
      interval_ms: [type: :pos_integer, default: 5_000],
      message: [type: :string, default: "heartbeat"]
    ]

  @impl true
  def mount(sensor, _context) do
    schedule_tick(sensor.config.interval_ms)
    {:ok, sensor}
  end

  @impl true
  def dispatch_signal(sensor, :tick, _context) do
    signal = Jido.Signal.new!(
      source: {:sensor, sensor.id},
      type: "heartbeat",
      data: %{
        message: sensor.config.message,
        timestamp: DateTime.utc_now()
      }
    )

    schedule_tick(sensor.config.interval_ms)
    {:ok, sensor, [signal]}
  end

  def dispatch_signal(sensor, _other, _context) do
    {:noreply, sensor}
  end

  @impl true
  def handle_reconfigure(sensor, patch, _context) do
    Jido.Sensor.set_config(sensor, Map.merge(sensor.config, patch))
  end

  defp schedule_tick(interval_ms) do
    Process.send_after(self(), :tick, interval_ms)
  end
end
```

### 5.2 Webhook Sensor (HTTP-triggered)

```elixir
defmodule MyApp.Sensors.Webhook do
  use Jido.Sensor,
    name: "webhook",
    description: "Receives webhook payloads and emits signals",
    schema: [
      allowed_types: [type: {:list, :string}, default: []]
    ]

  # Phoenix/Plug controller calls this:
  def receive_webhook(sensor_pid, payload) do
    send(sensor_pid, {:webhook, payload})
  end

  @impl true
  def dispatch_signal(sensor, {:webhook, payload}, _context) do
    if allowed?(sensor, payload) do
      signal = Jido.Signal.new!(
        source: {:sensor, sensor.id},
        type: "webhook.received",
        data: payload
      )
      {:ok, sensor, [signal]}
    else
      {:noreply, sensor}
    end
  end

  defp allowed?(sensor, %{"type" => type}) do
    sensor.config.allowed_types == [] or type in sensor.config.allowed_types
  end
  defp allowed?(_sensor, _payload), do: true
end
```

### 5.3 PubSub Sensor (Message Bus Subscription)

```elixir
defmodule MyApp.Sensors.PubSubSensor do
  use Jido.Sensor,
    name: "pubsub",
    description: "Subscribes to Phoenix.PubSub topics",
    schema: [
      pubsub: [type: :atom, required: true],
      topic: [type: :string, required: true]
    ]

  @impl true
  def mount(sensor, _context) do
    Phoenix.PubSub.subscribe(sensor.config.pubsub, sensor.config.topic)
    {:ok, sensor}
  end

  @impl true
  def dispatch_signal(sensor, {event_type, payload}, _context) do
    signal = Jido.Signal.new!(
      source: {:sensor, sensor.id},
      type: "pubsub.#{event_type}",
      data: payload
    )
    {:ok, sensor, [signal]}
  end

  @impl true
  def shutdown(sensor, _reason, _context) do
    Phoenix.PubSub.unsubscribe(sensor.config.pubsub, sensor.config.topic)
    :ok
  end
end
```

---

## 6. Migration from v1 Sensors

### 6.1 Step-by-Step Migration

1. **Change `use Jido.Sensor` to v2 style** (once v2 macro is ready)
2. **Update `mount/1` → `mount/2`**: Add `context` parameter
3. **Replace `deliver_signal/1` with `dispatch_signal/3`**:
   - Same verb, but now receives events and returns signals to dispatch
4. **Update `shutdown/1` → `shutdown/3`**: Add `reason` and `context`
5. **Update agent startup**: Use `Effect.StartSensor` in `handle_signal/2` instead of direct supervision

### 6.2 Transitional Coexistence

During migration, v1 and v2 sensors can coexist:

- v1 sensors: Continue using existing `Jido.Sensor` module
- v2 sensors: Use new `Jido.Sensor2` (or replace once ready)

### 6.3 Config Schema Compatibility

Existing NimbleOptions schemas work unchanged in `config_schema`:

```elixir
use Jido.Sensor,
  name: "my_sensor",
  schema: [
    # NimbleOptions schema - works as-is
    interval: [type: :pos_integer, default: 5000],
    enabled: [type: :boolean, default: true]
  ]
```

---

## 7. Effort Summary

| Phase | Description | Effort |
|-------|-------------|--------|
| Phase 1 | Zoi struct + config schema for `Jido.Sensor` | M (1 day) |
| Phase 2 | `Jido.SensorServer` GenServer wrapper | M (1 day) |
| Phase 3 | `use Jido.Sensor` macro with behaviour | M (1 day) |
| Phase 4 | Effect types (`StartSensor`, `StopSensor`, `ConfigureSensor`) | S (0.5 day) |
| Phase 5 | AgentServer integration (effect execution) | M (1 day) |
| Phase 6 | Migrate example sensors (Heartbeat, Cron) | M (1 day) |
| Phase 7 | Documentation + deprecation notices | S (0.5 day) |

**Total**: ~6 days focused work

---

## 8. Risks and Guardrails

### Risks

1. **Dual sensor models during migration**
   - Mitigation: Keep v1 working; introduce v2 as recommended path with clear docs
2. **Routing confusion** (sensors emit Signals, agents emit Effects)
   - Mitigation: Strict documentation rule: "Sensors never emit Effects; Agents never emit Signals"
3. **Perceived inefficiency from sensor duplication**
   - Mitigation: Document that timers/pubsub are cheap; provide sensor templates to reduce boilerplate
4. **Ad-hoc "homegrown bus" patterns**
   - Mitigation: Provide canonical "router agent" example for fan-out use cases; point to SignalBus as future path

### Guardrails

- `%Jido.Sensor{}` has a **single `target` field** (not a list) — no multi-target
- Keep `%Jido.Sensor{}` free of process references (target is set at runtime by SensorServer)
- `Jido.SensorServer` is the **only** GenServer wrapper for v2 sensors
- No subscription management APIs on `Jido.Sensor` or `Jido.SensorServer`
- Write comprehensive tests for the signal→agent→effect loop
- Create canonical example sensors before migrating all existing sensors

### Why 1:1 Ownership?

| Concern | 1:1 Advantage |
|---------|---------------|
| **Lifecycle** | Trivial: sensor dies with agent, no reference counting |
| **Routing** | Simple `send(target, {:signal, signal})` — no subscription tables |
| **Effect model** | Clean: Effects are local ("start MY sensor") |
| **Isolation** | Each agent's sensors can have different configs |
| **Debugging** | Clear ownership makes tracing straightforward |

---

## 9. When to Consider the Advanced Path

Revisit this design and consider shared/global sensors when:

1. **Expensive external connections** where duplication is truly unacceptable (e.g., licensed API with per-consumer billing)
2. **Work queues / partitioned streams** where multiple consumers would compete for the same messages
3. **Cross-node routing** needed (sensors on node A, agents on node B)
4. **Persistent sensors** required (state in DB, restart from snapshot)

**The right evolution is NOT multi-target sensors** — instead, introduce a `Jido.SignalBus`:
- Shared sensor → single target (the bus)
- Bus maintains subscriptions and fans out to agents
- Agents subscribe via `Effect.SubscribeSignal{topic, filter}`

---

## 10. Optional Advanced Path (Outline Only)

### 10.1 Signal Bus / Router (for Shared Sensors)

When you need fan-out, introduce `Jido.SignalBus` as a **separate layer**:

```
┌─────────────────────────────────────────────────────────────┐
│ Global Sensor (e.g., Kafka consumer, expensive API)          │
│ target: Jido.SignalBus                                       │
└──────────────────────────────┬──────────────────────────────┘
                               │ emits signals
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Jido.SignalBus                                               │
│ - Maintains subscriptions: topic → [agent targets]           │
│ - Filters and fans out signals                               │
└──────────────────────────────┬──────────────────────────────┘
                               │ routes to subscribers
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
      AgentServer A      AgentServer B      AgentServer C
```

- Global sensors have `target: Jido.SignalBus` (still single target!)
- Agents subscribe via `Effect.SubscribeSignal{topic, filter}`
- The bus handles fan-out — sensors remain simple

### 10.2 Persistent / Distributed Sensors

- `Jido.SensorStore` behaviour to persist config and meta
- `Jido.SensorServer` periodically checkpoints state
- Supervisors restore sensors after crash or deploy across nodes

### 10.3 Sensor Templates and Composition

- `Jido.Sensor.Template` for common patterns (interval polling, HTTP webhook, queue consumer)
- Agents request sensors by template name + params via Effects
- Reduces boilerplate when many agents need similar sensors

---

## 11. Quick Reference: v2 Sensor API

```elixir
# Core struct
%Jido.Sensor{
  id: "heartbeat_1",
  name: "heartbeat",
  target: agent_server_pid,
  config_schema: [...],
  config: %{interval_ms: 5000},
  status: :running,
  meta: %{}
}

# Define a sensor module
defmodule MySensor do
  use Jido.Sensor,
    name: "my_sensor",
    description: "Does something useful",
    schema: [
      interval: [type: :pos_integer, default: 5000]
    ]

  @impl true
  def mount(sensor, context), do: {:ok, sensor}

  @impl true
  def dispatch_signal(sensor, event, context) do
    signal = build_signal(sensor, event)
    {:ok, sensor, [signal]}
  end

  @impl true
  def shutdown(sensor, reason, context), do: :ok
end

# Start from agent's handle_signal
def handle_signal(agent, signal) do
  effects = [
    %Effect.StartSensor{
      id: "my_sensor_1",
      module: MySensor,
      config: %{interval: 10_000}
    }
  ]
  {:ok, agent, effects}
end

# Callbacks (minimal set)
@callback mount(sensor, context) :: {:ok, sensor} | {:ok, sensor, [Signal.t()]} | {:error, term()}
@callback dispatch_signal(sensor, event, context) :: {:ok, sensor, [Signal.t()]} | {:noreply, sensor} | {:stop, reason, sensor}
@callback handle_reconfigure(sensor, patch, context) :: {:ok, sensor} | {:error, term()}  # optional
@callback shutdown(sensor, reason, context) :: :ok  # optional
```

---

*Document Version: 1.0.0*
*Created: December 2024*
