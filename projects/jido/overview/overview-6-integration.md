# Jido 2.0 - Integration Points

Jido integrates with the Elixir ecosystem, external systems, and companion packages in multiple ways.

## Jido Ecosystem Integration

### jido_action

Action definitions, validation, schemas, and AI tool integration.

```elixir
# jido_action provides the Action abstraction
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  def run(params, context) do
    {:ok, %{count: context.state[:count] + params.amount}}
  end
end
```

**Key Features:**
- Schema validation for action parameters
- Context injection for action execution
- AI tool metadata for LLM integration
- Composable action pipelines

### jido_signal

CloudEvents-style signals with routing and dispatch adapters.

```elixir
# Create a signal
signal = Jido.Signal.new!("user.created", %{user_id: 123})

# Dispatch via various adapters
Jido.Signal.Dispatch.dispatch(signal, [
  {:pubsub, topic: "user_events"},
  {:webhook, url: "https://api.example.com/hooks"}
])
```

**Dispatch Adapters:**

| Adapter | Description |
|---------|-------------|
| `:pubsub` | Phoenix.PubSub broadcast |
| `:bus` | In-cluster signal bus |
| `:http` / `:webhook` | HTTP POST to external endpoints |
| `:pid` | Direct send to process |
| `:named` | Send to named process |
| `:logger` | Log signal for debugging |
| `:console` | Print to console |

### jido_ai

AI/LLM powered behaviors for agents.

```elixir
# AI-powered strategy for agents
defmodule MyApp.AIAgent do
  use Jido.Agent,
    strategy: Jido.AI.Strategy.ReAct
end
```

**Features:**
- LLM-driven action selection
- Multi-step reasoning loops
- Tool calling integration
- Prompt management

### jido_chat

Conversational agent behaviors.

```elixir
# Chat-enabled agent
defmodule MyApp.ChatBot do
  use Jido.Agent,
    skills: [Jido.Chat.Skill]
end
```

### jido_memory

Long-lived agent memory.

```elixir
# Memory-enabled agent
defmodule MyApp.PersistentAgent do
  use Jido.Agent,
    skills: [Jido.Memory.Skill]
end
```

## OTP Integration

### Supervision Tree

Jido instances are standard OTP supervisors:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Jido instance as a child supervisor
      MyApp.Jido
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

### Process Architecture

```
MyApp.Jido (Supervisor)
├── Task.Supervisor (async work)
├── Registry (agent lookup)
├── DynamicSupervisor (agent processes)
│   ├── AgentServer (agent-1)
│   ├── AgentServer (agent-2)
│   └── ...
└── AgentPool (optional)
```

### GenServer Patterns

AgentServer is a standard GenServer:

```elixir
# Synchronous call
{:ok, result} = GenServer.call(pid, {:signal, signal})

# Asynchronous cast
GenServer.cast(pid, {:signal, signal})

# Via Jido.AgentServer API
{:ok, result} = Jido.AgentServer.call(pid, signal)
Jido.AgentServer.cast(pid, signal)
```

## Web & API Integration

### Phoenix Controller Example

```elixir
defmodule MyAppWeb.AgentController do
  use MyAppWeb, :controller
  
  def create(conn, %{"type" => type, "config" => config}) do
    {:ok, pid} = MyApp.Jido.start_agent(
      String.to_existing_atom(type),
      id: config["id"]
    )
    
    json(conn, %{status: "created", id: config["id"]})
  end
  
  def action(conn, %{"id" => id, "action" => action_params}) do
    case MyApp.Jido.whereis(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})
      
      pid ->
        signal = Jido.Signal.new!(action_params["type"], action_params["data"])
        {:ok, result} = Jido.AgentServer.call(pid, signal)
        json(conn, result)
    end
  end
  
  def wait(conn, %{"id" => id}) do
    case MyApp.Jido.whereis(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})
      
      pid ->
        {:ok, result} = Jido.Await.completion(pid, 30_000)
        json(conn, result)
    end
  end
end
```

### LiveView Integration

```elixir
defmodule MyAppWeb.AgentLive do
  use MyAppWeb, :live_view
  
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to agent updates via PubSub
      Phoenix.PubSub.subscribe(MyApp.PubSub, "agent:#{id}")
    end
    
    {:ok, assign(socket, agent_id: id, state: nil)}
  end
  
  def handle_info({:agent_update, state}, socket) do
    {:noreply, assign(socket, state: state)}
  end
end
```

## Message Queue Integration

### Publishing to External Queues

Use emit directives with HTTP adapters:

```elixir
%Directive.Emit{
  signal: Jido.Signal.new!("order.completed", order_data),
  adapters: [
    {:webhook, url: "https://queue.example.com/publish"}
  ]
}
```

### Consuming from External Queues

Create a consumer that forwards to agents:

```elixir
defmodule MyApp.QueueConsumer do
  use Broadway
  
  def handle_message(_, message, _) do
    signal = Jido.Signal.new!(message.data["type"], message.data["payload"])
    
    case MyApp.Jido.whereis(message.data["agent_id"]) do
      nil -> :ok
      pid -> Jido.AgentServer.cast(pid, signal)
    end
    
    message
  end
end
```

## PubSub Integration

### Agent-to-Agent Communication

```elixir
# Agent A emits a signal
%Directive.Emit{
  signal: Jido.Signal.new!("task.completed", %{result: result}),
  adapters: [{:pubsub, topic: "tasks"}]
}

# Agent B subscribes to the topic
# (via skill or custom sensor)
```

### Broadcasting State Changes

```elixir
defmodule MyApp.BroadcastSkill do
  use Jido.Skill,
    name: "broadcast"
  
  @impl true
  def transform_result(agent, action, result) do
    # Add broadcast directive after every action
    broadcast = %Directive.Emit{
      signal: Jido.Signal.new!("state.changed", agent.state),
      adapters: [{:pubsub, topic: "agent:#{agent.id}"}]
    }
    
    {agent, result, [broadcast]}
  end
end
```

## Scheduling Integration

### One-Time Delayed Execution

```elixir
%Directive.Schedule{
  delay: 5_000,  # 5 seconds
  signal: Jido.Signal.new!("reminder", %{})
}
```

### Cron-Based Scheduling

```elixir
# Schedule a recurring job
%Directive.Cron{
  schedule: "*/5 * * * *",  # Every 5 minutes
  signal: Jido.Signal.new!("heartbeat", %{}),
  job_name: :heartbeat_job
}

# Cancel the job
%Directive.CronCancel{job_name: :heartbeat_job}
```

## Observability Integration

### Telemetry Events

Jido emits standard telemetry events:

```elixir
# Attach handlers in your application
:telemetry.attach_many(
  "my-app-jido-handlers",
  [
    [:jido, :agent, :cmd, :start],
    [:jido, :agent, :cmd, :stop],
    [:jido, :agent, :cmd, :exception],
    [:jido, :action, :run, :start],
    [:jido, :action, :run, :stop]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

### OpenTelemetry Integration

```elixir
defmodule MyApp.OpenTelemetryTracer do
  @behaviour Jido.Observe.Tracer
  
  def span(name, metadata, fun) do
    OpenTelemetry.Tracer.with_span name, %{attributes: metadata} do
      fun.()
    end
  end
end

# Configure Jido to use the tracer
config :jido, tracer: MyApp.OpenTelemetryTracer
```

### Logging

```elixir
# Jido uses Logger throughout
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:agent_id, :action, :signal_type]
```

## Database Integration

### Persisting Agent State

```elixir
defmodule MyApp.PersistenceSkill do
  use Jido.Skill,
    name: "persistence"
  
  @impl true
  def transform_result(agent, _action, result) do
    # Persist after each action
    MyApp.Repo.insert_or_update!(
      AgentState.changeset(%AgentState{}, %{
        agent_id: agent.id,
        state: agent.state
      })
    )
    
    {agent, result, []}
  end
end
```

### Loading Agent State on Startup

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
  
  def start_agent(module, opts) do
    # Load persisted state if exists
    opts = case MyApp.Repo.get(AgentState, opts[:id]) do
      nil -> opts
      record -> Keyword.put(opts, :initial_state, record.state)
    end
    
    super(module, opts)
  end
end
```

## Integration Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     External Systems                             │
├─────────────┬─────────────┬─────────────┬─────────────┬─────────┤
│ HTTP/REST   │ WebSocket   │ Message Q   │ PubSub      │ Cron    │
└──────┬──────┴──────┬──────┴──────┬──────┴──────┬──────┴────┬────┘
       │             │             │             │            │
       ▼             ▼             ▼             ▼            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Jido Integration Layer                        │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐│
│  │ Phoenix   │ │ Broadway  │ │ PubSub    │ │ Scheduler         ││
│  │ Plugs     │ │ Consumers │ │ Adapters  │ │ (SchedEx)         ││
│  └───────────┘ └───────────┘ └───────────┘ └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Jido Core                                     │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐│
│  │ Agents    │ │ Actions   │ │ Skills    │ │ Strategies        ││
│  └───────────┘ └───────────┘ └───────────┘ └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Jido Ecosystem                                │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐│
│  │ jido_ai   │ │ jido_chat │ │jido_memory│ │ jido_signal       ││
│  └───────────┘ └───────────┘ └───────────┘ └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```
