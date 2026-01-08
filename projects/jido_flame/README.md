# JidoFlame

[![Hex.pm](https://img.shields.io/hexpm/v/jido_flame.svg)](https://hex.pm/packages/jido_flame)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/jido_flame)

FLAME integration for Jido agents — spawn remote agents on Fly.io machines with full parent-child hierarchy support.

## Overview

JidoFlame bridges [FLAME](https://github.com/phoenixframework/flame) (Fleeting Lambda Application for Modular Execution) with Jido's directive-based agent architecture. This enables:

- **Remote agent spawning** — Spawn child agents on FLAME runners (Fly.io machines)
- **Remote function execution** — Execute functions on remote nodes
- **Parent-child hierarchy** — Track remote children like local ones
- **Signal communication** — `emit_to_parent/3` works across distributed nodes

## Installation

Add `jido_flame` to your dependencies:

```elixir
def deps do
  [
    {:jido_flame, "~> 0.1.0"},
    {:flame, "~> 0.5"}
  ]
end
```

## Quick Start

### 1. Configure FLAME

```elixir
# config/config.exs
config :jido_flame,
  default_pool: MyApp.FlamePool

# config/runtime.exs
config :flame,
  backend: 
    if System.get_env("FLY_APP_NAME") do
      {FLAME.FlyBackend, 
       token: System.get_env("FLY_API_TOKEN"),
       app: System.get_env("FLY_APP_NAME")}
    else
      FLAME.LocalBackend
    end
```

### 2. Add to Supervision Tree

```elixir
def start(_type, _args) do
  children = 
    case FLAME.Parent.get() do
      nil ->
        # Main node: full stack
        [
          JidoFlame.AgentRegistry,
          JidoFlame.ChildRegistry,
          {DynamicSupervisor, name: JidoFlame.OwnerSupervisor, strategy: :one_for_one},
          {Jido, name: MyApp.Jido},
          {FLAME.Pool,
           name: MyApp.FlamePool,
           backend: Application.get_env(:flame, :backend, FLAME.LocalBackend),
           min: 0,
           max: 10,
           max_concurrency: 5,
           idle_shutdown_after: :timer.seconds(30)}
        ]

      _parent ->
        # FLAME runner: lean stack
        [{Jido, name: MyApp.Jido}]
    end

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### 3. Use in Your Agent

```elixir
defmodule MyApp.ParentAgent do
  use Jido.Agent,
    name: "parent_agent",
    skills: [JidoFlame.Skill]

  def cmd(agent, %{type: "work.distribute"} = signal) do
    directive = %JidoFlame.Directive.SpawnRemoteAgent{
      pool: MyApp.FlamePool,
      agent: MyApp.WorkerAgent,
      tag: :worker_1,
      meta: %{task: signal.data}
    }

    {agent, [directive]}
  end
end
```

## Directives

JidoFlame provides these directives:

| Directive | Description |
|-----------|-------------|
| `RemoteCall` | Execute a function on a remote runner (sync) |
| `RemoteCast` | Fire-and-forget remote execution |
| `SpawnRemoteAgent` | Spawn a child agent on a remote runner |
| `PlaceRemoteChild` | Place any child process remotely |
| `StopRemoteAgent` | Stop a remote child agent |

## Owner Pattern

JidoFlame uses the **Owner Pattern** to decouple agent lifetime from FLAME links:

```
┌─────────────────────────────────────────────┐
│ Main Node                                   │
│  ├── Jido Agent (may restart)              │
│  │    └── logical_agent_id: "agent-123"    │
│  │                                          │
│  ├── JidoFlame.Owner (per remote child)    │
│  │    ├── owns FLAME link                  │
│  │    └── forwards signals                 │
│  │                                          │
│  └── Registries                            │
│       ├── AgentRegistry (id → pid)         │
│       └── ChildRegistry ({id,tag} → owner) │
└─────────────────────────────────────────────┘
                    │
                    ▼ FLAME.place_child/3
┌─────────────────────────────────────────────┐
│ Remote FLAME Runner                         │
│  └── Child Agent                           │
│       └── emit_to_parent → Owner → Agent   │
└─────────────────────────────────────────────┘
```

## Actions

Use actions for convenience:

```elixir
# In agent cmd/2
action = {JidoFlame.Actions.SpawnRemoteAgent, %{
  pool: MyApp.FlamePool,
  agent: WorkerAgent,
  tag: :worker_1
}}

{agent, [%Jido.Directive.Execute{action: action}]}
```

## Remote Child Communication

Remote children can signal their parent:

```elixir
# In remote child
JidoFlame.Remote.emit_to_parent(parent_ref, "work.completed", %{result: data})
```

The parent receives:

```elixir
def handle_info({:remote_child_signal, tag, signal}, state) do
  # Handle signal from remote child with given tag
end
```

## Diagnostics

Run the doctor task to verify your setup:

```bash
$ mix jido.flame.doctor

JidoFlame Doctor
========================================

Checking configuration...
✔ Default pool configured: MyApp.FlamePool
✔ FLAME backend: FLAME.LocalBackend

Testing RemoteCall...
✔ RemoteCall succeeded
  - Executed on node: :"myapp@127.0.0.1"
  - Round-trip time: 12ms

Testing SpawnRemoteAgent...
✔ SpawnRemoteAgent succeeded
  - Child PID: #PID<0.245.0>
  - Child responds to ping: :pong
  - emit_to_parent verified: received signal

✔ Doctor checks complete!
```

## Configuration

| Config | Description | Default |
|--------|-------------|---------|
| `:jido_flame, :default_pool` | Default FLAME pool name | `nil` |
| `:flame, :backend` | FLAME backend module | `FLAME.LocalBackend` |

### Environment Variables

For Fly.io deployment:

```bash
FLY_APP_NAME=your-app
FLY_API_TOKEN=your-token
```

## License

Apache-2.0 — see [LICENSE](LICENSE)
