defmodule Jido.Agent.Effects do
  @moduledoc """
  Centralized effect application for strategies.

  Separates internal effects (state mutations) from external directives.
  All strategies should use these helpers to ensure consistent behavior.

  ## Effect Types

  - `Internal.SetState` - Deep merge attributes into state
  - `Internal.ReplaceState` - Replace state wholesale
  - `Internal.DeleteKeys` - Remove top-level keys
  - `Internal.SetPath` - Set value at nested path
  - `Internal.DeletePath` - Delete value at nested path

  Any other struct is treated as an external directive and passed through.
  """

  alias Jido.Agent
  alias Jido.Agent.Internal

  @doc """
  Merges action result into agent state.

  Uses deep merge semantics.
  """
  @spec apply_result(Agent.t(), map()) :: Agent.t()
  def apply_result(%Agent{} = agent, result) when is_map(result) do
    new_state = Jido.Agent.State.merge(agent.state, result)
    %{agent | state: new_state}
  end

  @doc """
  Applies a list of effects to the agent.

  Internal effects modify agent state. External directives are collected
  and returned for the runtime to process.

  Returns `{updated_agent, external_directives}`.
  """
  @spec apply_effects(Agent.t(), [struct()]) :: {Agent.t(), [struct()]}
  def apply_effects(%Agent{} = agent, effects) do
    Enum.reduce(effects, {agent, []}, fn
      %Internal.SetState{attrs: attrs}, {a, directives} ->
        new_state = Jido.Agent.State.merge(a.state, attrs)
        {%{a | state: new_state}, directives}

      %Internal.ReplaceState{state: new_state}, {a, directives} ->
        {%{a | state: new_state}, directives}

      %Internal.DeleteKeys{keys: keys}, {a, directives} ->
        new_state = Map.drop(a.state, keys)
        {%{a | state: new_state}, directives}

      %Internal.SetPath{path: path, value: value}, {a, directives} ->
        new_state = deep_put_in(a.state, path, value)
        {%{a | state: new_state}, directives}

      %Internal.DeletePath{path: path}, {a, directives} ->
        {_, new_state} = pop_in(a.state, path)
        {%{a | state: new_state}, directives}

      %_{} = directive, {a, directives} ->
        {a, directives ++ [directive]}
    end)
  end

  @doc """
  Helper to put a value at a nested path, creating intermediate maps if needed.
  """
  @spec deep_put_in(map(), [atom()], term()) :: map()
  def deep_put_in(map, [key], value) do
    Map.put(map, key, value)
  end

  def deep_put_in(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, deep_put_in(nested, rest, value))
  end
end
