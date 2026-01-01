defmodule Jido.BehaviorTree.Nodes.Action do
  @moduledoc """
  A leaf node that executes a Jido Action.

  The Action node wraps a Jido Action module and executes it when ticked.
  The action result is converted to behavior tree statuses:
  - `{:ok, result}` -> `:success`
  - `{:error, reason}` -> `{:error, reason}`

  Parameters are passed to the action and can include values from the blackboard.

  ## Example

      action = Action.new(MyApp.Actions.SendEmail, %{
        to: "user@example.com",
        subject: "Hello"
      })

  ## Using Blackboard Values

  You can reference blackboard values using the `:from_blackboard` option:

      action = Action.new(MyApp.Actions.ProcessData, %{
        data: {:from_blackboard, :input_data}
      })

  """

  alias Jido.BehaviorTree.{Tick, Error}

  @schema Zoi.struct(
            __MODULE__,
            %{
              action_module: Zoi.any(description: "The Jido Action module to execute"),
              params: Zoi.any(description: "Parameters to pass to the action") |> Zoi.default(%{}),
              context: Zoi.any(description: "Context to pass to the action") |> Zoi.default(%{}),
              result: Zoi.any(description: "The result of the last execution") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @doc """
  Creates a new Action node for the given action module.

  ## Parameters

  - `action_module` - The Jido Action module to execute
  - `params` - Parameters to pass to the action (default: %{})
  - `context` - Context to pass to the action (default: %{})

  ## Examples

      iex> Action.new(MyAction)
      %Action{action_module: MyAction, params: %{}, context: %{}}

      iex> Action.new(MyAction, %{input: "value"})
      %Action{action_module: MyAction, params: %{input: "value"}, context: %{}}

  """
  @spec new(module(), map(), map()) :: t()
  def new(action_module, params \\ %{}, context \\ %{}) do
    %__MODULE__{
      action_module: action_module,
      params: params,
      context: context,
      result: nil
    }
  end

  @impl true
  def tick(
        %__MODULE__{action_module: action_module, params: params, context: context} = state,
        tick
      ) do
    resolved_params = resolve_params(params, tick)

    try do
      case Jido.Exec.run(action_module, resolved_params, context) do
        {:ok, result} ->
          {:success, %{state | result: result}}

        {:error, reason} ->
          {{:error, reason}, state}
      end
    rescue
      error ->
        bt_error =
          Error.node_error(Exception.message(error), __MODULE__, %{
            action_module: action_module,
            original_error: error
          })

        {{:error, bt_error}, state}
    end
  end

  @doc """
  Context-aware tick that integrates with Jido Agent Effects.

  When called via `Tree.tick_with_context/2`, this function:
  1. Resolves params from the blackboard
  2. Builds a Jido Instruction with agent state context
  3. Executes via `Jido.Exec.run/1`
  4. Applies results and effects to the agent via `Jido.Agent.Effects`
  5. Accumulates directives on the tick
  6. Updates the blackboard with last_result

  Returns a 3-tuple `{status, updated_node, updated_tick}`.
  """
  @spec tick_with_context(t(), Tick.t()) :: {Jido.BehaviorTree.Status.t(), t(), Tick.t()}
  def tick_with_context(
        %__MODULE__{action_module: action_module, params: params, context: node_context} = state,
        tick
      ) do
    resolved_params = resolve_params(params, tick)
    agent = tick.agent

    try do
      if agent do
        execute_with_agent(state, tick, action_module, resolved_params, node_context, agent)
      else
        execute_without_agent(state, tick, action_module, resolved_params, node_context)
      end
    rescue
      error ->
        bt_error =
          Error.node_error(Exception.message(error), __MODULE__, %{
            action_module: action_module,
            original_error: error
          })

        tick = Tick.put(tick, :error, bt_error)
        {{:error, bt_error}, state, tick}
    end
  end

  defp execute_with_agent(state, tick, action_module, resolved_params, node_context, agent) do
    merged_context =
      Map.merge(node_context, %{state: agent.state})
      |> Map.merge(tick.context)

    instruction = %Jido.Instruction{
      action: action_module,
      params: resolved_params,
      context: merged_context
    }

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        updated_agent = Jido.Agent.Effects.apply_result(agent, result)

        tick =
          tick
          |> Tick.update_agent(updated_agent)
          |> Tick.put(:last_result, result)

        {:success, %{state | result: result}, tick}

      {:ok, result, effects} when is_map(result) ->
        updated_agent = Jido.Agent.Effects.apply_result(agent, result)
        {final_agent, directives} = Jido.Agent.Effects.apply_effects(updated_agent, List.wrap(effects))

        tick =
          tick
          |> Tick.update_agent(final_agent)
          |> Tick.append_directives(directives)
          |> Tick.put(:last_result, result)

        {:success, %{state | result: result}, tick}

      {:error, reason} ->
        tick = Tick.put(tick, :error, reason)
        {:failure, state, tick}
    end
  end

  defp execute_without_agent(state, tick, action_module, resolved_params, node_context) do
    case Jido.Exec.run(action_module, resolved_params, node_context) do
      {:ok, result} ->
        tick = Tick.put(tick, :last_result, result)
        {:success, %{state | result: result}, tick}

      {:error, reason} ->
        tick = Tick.put(tick, :error, reason)
        {:failure, state, tick}
    end
  end

  @impl true
  def halt(state) do
    %{state | result: nil}
  end

  defp resolve_params(params, tick) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      resolved_value = resolve_value(value, tick)
      Map.put(acc, key, resolved_value)
    end)
  end

  defp resolve_value({:from_blackboard, key}, tick) do
    Tick.get(tick, key)
  end

  defp resolve_value(value, _tick) do
    value
  end
end
