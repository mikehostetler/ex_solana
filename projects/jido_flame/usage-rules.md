# JidoFlame Usage Rules for LLMs

## Package Purpose
JidoFlame integrates FLAME with Jido agents for remote execution on Fly.io machines.

## Key Patterns

### Creating Directives
```elixir
# SpawnRemoteAgent
%JidoFlame.Directive.SpawnRemoteAgent{
  pool: MyApp.FlamePool,
  agent: WorkerAgent,
  tag: :worker_1,
  meta: %{task: data}
}

# RemoteCall
%JidoFlame.Directive.RemoteCall{
  pool: MyApp.FlamePool,
  fun: fn -> expensive_computation() end
}
```

### Using the Skill
```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    skills: [JidoFlame.Skill]
end
```

### Remote Child Communication
```elixir
JidoFlame.Remote.emit_to_parent(parent_ref, "work.done", %{result: data})
```

## Common Mistakes to Avoid

1. Don't store pids in directives - use logical IDs
2. Don't call FLAME functions directly - use directives
3. Don't forget to start registries and OwnerSupervisor
4. Remember FLAME.LocalBackend for dev/test
