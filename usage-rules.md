# Jido BehaviorTree Usage Rules

## Node Implementation Pattern

All custom nodes must follow the Zoi struct pattern:

```elixir
defmodule MyApp.Nodes.MyNode do
  @schema Zoi.struct(
    __MODULE__,
    %{
      my_field: Zoi.string(description: "Field description")
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @behaviour Jido.BehaviorTree.Node

  @impl true
  def tick(node_state, tick) do
    # Your tick logic
    {:success, node_state}
  end

  @impl true
  def halt(node_state) do
    # Cleanup logic
    node_state
  end
end
```

## Status Return Values

Nodes must return one of:
- `{:success, updated_state}` - Node completed successfully
- `{:failure, updated_state}` - Node failed
- `{:running, updated_state}` - Node still executing
- `{{:error, reason}, state}` - Unexpected error occurred

## Blackboard Usage

Use the blackboard for inter-node communication:

```elixir
def tick(state, tick) do
  # Read from blackboard
  value = Jido.BehaviorTree.Tick.get(tick, :my_key)
  
  # Write to blackboard (returns updated tick)
  updated_tick = Jido.BehaviorTree.Tick.put(tick, :result, value)
  
  {:success, state}
end
```
