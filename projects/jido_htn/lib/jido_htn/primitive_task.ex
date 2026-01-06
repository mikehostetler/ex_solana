defmodule Jido.HTN.PrimitiveTask do
  @moduledoc """
  Represents a primitive task in the HTN planning system, integrated with the Jido Workflow framework.
  """

  @type action :: Jido.Action.t()
  @type params :: keyword()
  @type context :: map()
  @type scheduling_constraints :: %{
          optional(:earliest_start_time) => non_neg_integer(),
          optional(:latest_end_time) => non_neg_integer()
        }

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(description: "Unique name for this primitive task"),
              task:
                Zoi.tuple(
                  {Zoi.atom(description: "Jido.Action module"),
                   Zoi.array(Zoi.any(), description: "Action parameters")},
                  description: "Jido.Action module and parameters"
                )
                |> Zoi.default({nil, []}),
              cost:
                Zoi.integer(description: "Estimated cost for planning")
                |> Zoi.optional(),
              duration:
                Zoi.integer(description: "Estimated duration in milliseconds")
                |> Zoi.optional(),
              scheduling_constraints:
                Zoi.map(description: "Time constraints for execution")
                |> Zoi.optional(),
              preconditions:
                Zoi.list(
                  Zoi.function(),
                  description: "Functions that validate world state (1-arity)"
                )
                |> Zoi.default([]),
              effects:
                Zoi.list(
                  Zoi.function(),
                  description: "Functions that transform world state"
                )
                |> Zoi.default([]),
              expected_effects:
                Zoi.list(
                  Zoi.function(),
                  description: "Expected world state transformations"
                )
                |> Zoi.default([]),
              background:
                Zoi.boolean(description: "Execute asynchronously without blocking")
                |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Creates a new primitive task.

  ## Options
  - `:preconditions` - List of functions that take a world state and return a boolean
  - `:effects` - List of functions that take a result and return a map of world state changes
  - `:expected_effects` - List of functions that take a world state and return expected changes
  - `:cost` - Optional cost of executing the task
  - `:duration` - Optional duration of the task in milliseconds
  - `:scheduling_constraints` - Optional map of scheduling constraints (earliest_start_time, latest_end_time)
  - `:background` - Whether this task should execute in the background (default: false)
  """
  @spec new(String.t(), {action(), params()}, keyword()) :: {:ok, t()} | {:error, term()}
  def new(name, task, opts \\ []) when is_binary(name) do
    # Build base attrs with required fields and defaults
    attrs = %{
      name: name,
      task: task,
      preconditions: Keyword.get(opts, :preconditions, []),
      effects: Keyword.get(opts, :effects, []),
      expected_effects: Keyword.get(opts, :expected_effects, []),
      background: Keyword.get(opts, :background, false)
    }

    # Add optional fields only if they are present in opts
    attrs =
      if Keyword.has_key?(opts, :cost) do
        Map.put(attrs, :cost, Keyword.get(opts, :cost))
      else
        attrs
      end

    attrs =
      if Keyword.has_key?(opts, :duration) do
        Map.put(attrs, :duration, Keyword.get(opts, :duration))
      else
        attrs
      end

    attrs =
      if Keyword.has_key?(opts, :scheduling_constraints) do
        Map.put(attrs, :scheduling_constraints, Keyword.get(opts, :scheduling_constraints))
      else
        attrs
      end

    Zoi.parse(@schema, attrs)
  end

  @spec new!(String.t(), {action(), params()}, keyword()) :: t()
  def new!(name, task, opts \\ []) when is_binary(name) do
    case new(name, task, opts) do
      {:ok, primitive_task} -> primitive_task
      {:error, reason} -> raise ArgumentError, "Invalid PrimitiveTask: #{inspect(reason)}"
    end
  end

  @doc """
  Executes the primitive task with the given context.
  If the task is a background task, it will be started but not waited for completion.
  """
  @spec execute(t(), context()) :: {:ok, map()} | {:error, any()}
  def execute(%__MODULE__{task: {_action, _params}, background: true}, _context) do
    # For background tasks, start them but don't wait for completion
    # Return an empty map since we don't have immediate results
    raise "Jido.Workflow.run/3 is not implemented. Please provide an implementation."
    # Task.start(fn -> Workflow.run(action, params, context) end)
    # {:ok, %{}}
  end

  def execute(%__MODULE__{task: {_action, _params}}, _context) do
    raise "Jido.Workflow.run/3 is not implemented. Please provide an implementation."
    # Workflow.run(action, params, context)
  end
end
