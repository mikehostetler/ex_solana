# Jido

[![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido/)
[![CI](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml/badge.svg)](https://github.com/agentjido/jido/actions/workflows/elixir-ci.yml)
[![License](https://img.shields.io/hexpm/l/jido.svg)](https://github.com/agentjido/jido/blob/main/LICENSE)
[![Coverage Status](https://coveralls.io/repos/github/agentjido/jido/badge.svg?branch=main)](https://coveralls.io/github/agentjido/jido?branch=main)

> **Autonomous Agent Framework for Elixir**

_The name "Jido" (自動) comes from the Japanese word meaning "automatic" or "automated", where 自 (ji) means "self" and 動 (dō) means "movement"._

_Learn more about Jido at [agentjido.xyz](https://agentjido.xyz)._

## Overview

Jido is a toolkit for building autonomous, distributed agent systems in Elixir. It provides the foundation for creating agents that can plan, execute, and adapt their behavior in distributed applications.

This package is designed for agent builders. It contains the core building blocks for creating advanced agentic systems without AI baked into the framework itself. AI capabilities are provided through companion packages in the Jido ecosystem.

Whether you're building workflow automation, multi-agent coordination systems, or AI-powered applications, Jido provides the foundation for robust, observable, and scalable agent-driven architecture.

## The Jido Ecosystem

Jido is the core framework in a family of packages designed to work together:

| Package | Description |
|---------|-------------|
| [jido](https://github.com/agentjido/jido) | Core agent framework with state management, directives, and runtime |
| [jido_action](https://github.com/agentjido/jido_action) | Composable, validated actions with AI tool integration |
| [jido_signal](https://github.com/agentjido/jido_signal) | CloudEvents-based signal routing and pub/sub messaging |
| [jido_ai](https://github.com/agentjido/jido_ai) | AI/LLM integration for agents |
| [jido_chat](https://github.com/agentjido/jido_chat) | Conversational agent capabilities |
| [jido_memory](https://github.com/agentjido/jido_memory) | Persistent memory and context for agents |

For demos and examples, see the [Jido Workbench](https://github.com/agentjido/jido_workbench).

## Key Features

### Immutable Agent Architecture
- Pure functional agent design inspired by Elm/Redux
- `cmd/2` as the core operation: actions in, updated agent + directives out
- Schema-validated state with NimbleOptions or Zoi

### Directive-Based Effects
- Actions transform state; directives describe external effects
- Built-in directives: Emit, Spawn, SpawnAgent, StopChild, Schedule, Stop
- Protocol-based extensibility for custom directives

### OTP Runtime Integration
- GenServer-based AgentServer for production deployment
- Parent-child agent hierarchies with lifecycle management
- Signal routing with configurable strategies
- Instance-scoped supervision for multi-tenant deployments

### Composable Skills
- Reusable behavior modules that extend agents
- State isolation per skill with automatic schema merging
- Lifecycle hooks for initialization and signal handling

### Execution Strategies
- Direct execution for simple workflows
- FSM (Finite State Machine) strategy for state-driven workflows
- Extensible strategy protocol for custom execution patterns

## Installation

Add `jido` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 2.0"}
  ]
end
```

Then define a Jido instance module and add it to your supervision tree:

```elixir
# In lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
# In config/config.exs
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

```elixir
# In your application.ex
children = [
  MyApp.Jido
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Quick Start

### 1. Define an Agent

```elixir
defmodule MyApp.CounterAgent do
  use Jido.Agent,
    name: "counter",
    description: "A simple counter agent",
    schema: [
      count: [type: :integer, default: 0]
    ]
end
```

### 2. Define an Action

```elixir
defmodule MyApp.Actions.Increment do
  use Jido.Action,
    name: "increment",
    description: "Increments the counter by a given amount",
    schema: [
      amount: [type: :integer, default: 1]
    ]

  def run(params, context) do
    current = context.state[:count] || 0
    {:ok, %{count: current + params.amount}}
  end
end
```

### 3. Execute Commands

```elixir
# Create an agent
agent = MyApp.CounterAgent.new()

# Execute an action - returns updated agent + directives
{agent, directives} = MyApp.CounterAgent.cmd(agent, {MyApp.Actions.Increment, %{amount: 5}})

# Check the state
agent.state.count
# => 5
```

### 4. Run with AgentServer

```elixir
# Start the agent server
{:ok, pid} = MyApp.Jido.start_agent(MyApp.CounterAgent, id: "counter-1")

# Send signals to the running agent
Jido.AgentServer.signal(pid, Jido.Signal.new!("increment", %{amount: 10}))

# Look up the agent by ID
pid = MyApp.Jido.whereis("counter-1")

# List all running agents
agents = MyApp.Jido.list_agents()
```

## Core Concepts

### The `cmd/2` Contract

The fundamental operation in Jido:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

Key invariants:
- The returned `agent` is always complete - no "apply directives" step needed
- `directives` describe external effects only - they never modify agent state
- `cmd/2` is a pure function - same inputs always produce same outputs

### Actions vs Directives

| Actions | Directives |
|---------|------------|
| Describe state transformations | Describe external effects |
| Executed by `cmd/2`, update `agent.state` | Bare structs emitted by agents |
| Never perform side effects | Runtime (AgentServer) interprets them |

### Directive Types

| Directive | Purpose |
|-----------|---------|
| `Emit` | Dispatch a signal via configured adapters |
| `Error` | Signal an error from cmd/2 |
| `Spawn` | Spawn a generic BEAM child process |
| `SpawnAgent` | Spawn a child Jido agent with hierarchy tracking |
| `StopChild` | Gracefully stop a tracked child agent |
| `Schedule` | Schedule a delayed message |
| `Stop` | Stop the agent process |

## Documentation

- [Getting Started Guide](guides/getting-started.livemd)
- [Core Concepts](guides/core-concepts.md)
- [Building Agents](guides/agents.md)
- [Agent Directives](guides/directives.md)
- [Runtime and AgentServer](guides/runtime.md)
- [Skills](guides/skills.md)
- [Strategies](guides/strategies.md)

## Development

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 26+

### Running Tests

```bash
mix test
```

### Quality Checks

```bash
mix quality  # Runs formatter, dialyzer, and credo
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Setting up your development environment
- Running tests and quality checks
- Submitting pull requests
- Code style guidelines

## License

Copyright 2024-2025 Mike Hostetler

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

## Links

- **Documentation**: [https://hexdocs.pm/jido](https://hexdocs.pm/jido)
- **GitHub**: [https://github.com/agentjido/jido](https://github.com/agentjido/jido)
- **AgentJido**: [https://agentjido.xyz](https://agentjido.xyz)
- **Jido Workbench**: [https://github.com/agentjido/jido_workbench](https://github.com/agentjido/jido_workbench)
