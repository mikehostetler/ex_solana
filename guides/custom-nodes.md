# Creating Custom Nodes

All custom nodes must implement the `Jido.BehaviorTree.Node` behaviour and use the Zoi struct pattern.

## Basic Structure

```elixir
defmodule MyApp.Nodes.MyCustomNode do
  @moduledoc "A custom behavior tree node"

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
    __MODULE__,
    %{
      my_field: Zoi.string(description: "Custom field") |> Zoi.default("default"),
      internal_state: Zoi.any(description: "Internal state") |> Zoi.optional()
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  def new(my_field \\ "default") do
    %__MODULE__{my_field: my_field, internal_state: nil}
  end

  @impl true
  def tick(%__MODULE__{} = state, tick) do
    {:success, state}
  end

  @impl true
  def halt(%__MODULE__{} = state) do
    %{state | internal_state: nil}
  end
end
```

## The Node Behaviour

The `Jido.BehaviorTree.Node` behaviour requires two callbacks:

### `tick/2`

Called each time the node is executed.

```elixir
@callback tick(node :: t(), tick :: Tick.t()) ::
  {Node.status(), t()} | {{:error, term()}, t()}
```

**Parameters:**
- `node` - The current node state
- `tick` - The tick context containing blackboard, tree info, etc.

**Return Values:**
- `{:success, updated_node}` - Node completed successfully
- `{:failure, updated_node}` - Node failed
- `{:running, updated_node}` - Node is still executing
- `{{:error, reason}, updated_node}` - An error occurred

### `halt/1`

Called when execution is interrupted (e.g., parent node stops ticking this branch).

```elixir
@callback halt(node :: t()) :: t()
```

Use this to clean up any running state.

## Using Zoi for Schemas

Zoi provides type-safe struct definitions with validation and coercion.

### Common Zoi Types

```elixir
# Basic types
Zoi.string()
Zoi.integer()
Zoi.boolean()
Zoi.atom()
Zoi.any()

# With constraints
Zoi.integer() |> Zoi.min(0)
Zoi.string() |> Zoi.min_length(1)

# Optional and defaults
Zoi.integer() |> Zoi.optional()
Zoi.integer() |> Zoi.default(0)

# Complex types
Zoi.list(Zoi.string())
Zoi.map(%{key: Zoi.string()})
```

### Schema Definition Pattern

```elixir
@schema Zoi.struct(
  __MODULE__,
  %{
    # Required field with description
    name: Zoi.string(description: "Node name"),
    
    # Optional field
    timeout: Zoi.integer(description: "Timeout in ms") |> Zoi.optional(),
    
    # Field with default
    retries: Zoi.integer(description: "Retry count") |> Zoi.default(3),
    
    # Child node
    child: Zoi.any(description: "Child node") |> Zoi.optional()
  },
  coerce: true
)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

## Example: Condition Node

A node that evaluates a condition function:

```elixir
defmodule MyApp.Nodes.Condition do
  @moduledoc "Evaluates a condition and returns success or failure"

  @schema Zoi.struct(
    __MODULE__,
    %{
      condition_fn: Zoi.any(description: "Function that returns boolean")
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  def new(condition_fn) when is_function(condition_fn, 1) do
    %__MODULE__{condition_fn: condition_fn}
  end

  @impl true
  def tick(%__MODULE__{condition_fn: condition_fn} = state, tick) do
    if condition_fn.(tick.blackboard) do
      {:success, state}
    else
      {:failure, state}
    end
  end

  @impl true
  def halt(state), do: state
end
```

Usage:

```elixir
condition = Condition.new(fn blackboard ->
  blackboard[:health] > 50
end)
```

## Example: Async Node

A node that handles async operations:

```elixir
defmodule MyApp.Nodes.AsyncTask do
  @moduledoc "Runs an async task and waits for completion"

  @schema Zoi.struct(
    __MODULE__,
    %{
      task_fn: Zoi.any(description: "Function to run asynchronously"),
      task_ref: Zoi.any(description: "Running task reference") |> Zoi.optional()
    },
    coerce: true
  )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  def new(task_fn) when is_function(task_fn, 0) do
    %__MODULE__{task_fn: task_fn, task_ref: nil}
  end

  @impl true
  def tick(%__MODULE__{task_ref: nil, task_fn: task_fn} = state, _tick) do
    task = Task.async(task_fn)
    {:running, %{state | task_ref: task}}
  end

  def tick(%__MODULE__{task_ref: task} = state, _tick) do
    case Task.yield(task, 0) do
      {:ok, {:ok, _result}} ->
        {:success, %{state | task_ref: nil}}

      {:ok, {:error, _reason}} ->
        {:failure, %{state | task_ref: nil}}

      nil ->
        {:running, state}
    end
  end

  @impl true
  def halt(%__MODULE__{task_ref: nil} = state), do: state

  def halt(%__MODULE__{task_ref: task} = state) do
    Task.shutdown(task, :brutal_kill)
    %{state | task_ref: nil}
  end
end
```
