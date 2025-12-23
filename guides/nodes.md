# Node Reference

Jido BehaviorTree provides three categories of nodes:

## Composite Nodes

Composite nodes manage the execution of multiple children.

### Sequence

Executes children in order. Succeeds if all succeed, fails if any fails.

```elixir
alias Jido.BehaviorTree.Nodes.Sequence

sequence = Sequence.new([
  ValidateNode.new(),
  ProcessNode.new(),
  SaveNode.new()
])
```

**Behavior:**
- Executes children left to right
- Returns `:failure` immediately if any child fails
- Returns `:running` if a child is still running
- Returns `:success` only when all children succeed

### Selector

Tries children in order until one succeeds. Fails only if all fail.

```elixir
alias Jido.BehaviorTree.Nodes.Selector

selector = Selector.new([
  TryLocalCache.new(),
  TryRemoteAPI.new(),
  UseFallback.new()
])
```

**Behavior:**
- Executes children left to right
- Returns `:success` immediately if any child succeeds
- Returns `:running` if a child is still running
- Returns `:failure` only when all children fail

## Decorator Nodes

Decorator nodes modify the behavior of a single child.

### Inverter

Inverts success/failure of its child.

```elixir
alias Jido.BehaviorTree.Nodes.Inverter

inverter = Inverter.new(IsEnemy.new())
```

**Behavior:**
- `:success` becomes `:failure`
- `:failure` becomes `:success`
- `:running` passes through unchanged

### Succeeder

Always returns success when child completes.

```elixir
alias Jido.BehaviorTree.Nodes.Succeeder

succeeder = Succeeder.new(OptionalAction.new())
```

**Behavior:**
- Both `:success` and `:failure` become `:success`
- `:running` passes through unchanged

### Failer

Always returns failure when child completes.

```elixir
alias Jido.BehaviorTree.Nodes.Failer

failer = Failer.new(SomeAction.new())
```

**Behavior:**
- Both `:success` and `:failure` become `:failure`
- `:running` passes through unchanged

### Repeat

Repeats child N times.

```elixir
alias Jido.BehaviorTree.Nodes.Repeat

repeat = Repeat.new(FlakyAction.new(), 3)
```

**Behavior:**
- Executes child up to N times
- Returns `:failure` immediately if child fails
- Returns `:success` after N successful executions

## Leaf Nodes

Leaf nodes perform actual work and have no children.

### Action

Executes a Jido Action.

```elixir
alias Jido.BehaviorTree.Nodes.Action

action = Action.new(MyApp.Actions.SendEmail, %{
  to: "user@example.com",
  subject: "Hello"
})

# With blackboard reference
action = Action.new(MyApp.Actions.ProcessData, %{
  data: {:from_blackboard, :input_data}
})
```

**Behavior:**
- Runs the action's `run/2` callback
- `{:ok, result}` returns `:success`
- `{:error, _}` returns `:failure`

### Wait

Waits for a specified duration.

```elixir
alias Jido.BehaviorTree.Nodes.Wait

wait = Wait.new(1000)  # Wait 1000ms
```

**Behavior:**
- Returns `:running` until duration elapses
- Returns `:success` when complete

### SetBlackboard

Sets values in the blackboard.

```elixir
alias Jido.BehaviorTree.Nodes.SetBlackboard

# Set a single key
node = SetBlackboard.new(:status, :ready)

# Set multiple keys
node = SetBlackboard.new(%{status: :ready, timestamp: DateTime.utc_now()})
```

**Behavior:**
- Always returns `:success`
- Updates the tick's blackboard with the specified values
