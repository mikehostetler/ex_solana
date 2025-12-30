defmodule Jido.Agent.Strategy.Direct do
  @moduledoc """
  Default execution strategy that runs instructions immediately and sequentially.

  This strategy:
  - Executes each instruction via `Jido.Exec.run/1`
  - Merges results into agent state
  - Applies internal effects (e.g., `SetState`) to the agent
  - Returns only external directives to the caller

  This is the default strategy and provides the simplest execution model.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Internal
  alias Jido.Error
  alias Jido.Instruction

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) when is_list(instructions) do
    Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
      {new_agent, new_directives} = run_instruction(acc_agent, instruction)
      {new_agent, acc_directives ++ new_directives}
    end)
  end

  defp run_instruction(agent, %Instruction{} = instruction) do
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        {apply_result(agent, result), []}

      {:ok, result, effects} when is_map(result) ->
        agent = apply_result(agent, result)
        apply_effects(agent, List.wrap(effects))

      {:error, reason} ->
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :instruction}]}
    end
  end

  defp apply_result(agent, result) when is_map(result) do
    new_state = Jido.Agent.State.merge(agent.state, result)
    %{agent | state: new_state}
  end

  defp apply_effects(agent, effects) do
    Enum.reduce(effects, {agent, []}, fn
      # Internal: deep merge state
      %Internal.SetState{attrs: attrs}, {a, directives} ->
        new_state = Jido.Agent.State.merge(a.state, attrs)
        {%{a | state: new_state}, directives}

      # Internal: replace state wholesale
      %Internal.ReplaceState{state: new_state}, {a, directives} ->
        {%{a | state: new_state}, directives}

      # Internal: delete top-level keys
      %Internal.DeleteKeys{keys: keys}, {a, directives} ->
        new_state = Map.drop(a.state, keys)
        {%{a | state: new_state}, directives}

      # Internal: set value at nested path (creates intermediate maps if needed)
      %Internal.SetPath{path: path, value: value}, {a, directives} ->
        new_state = deep_put_in(a.state, path, value)
        {%{a | state: new_state}, directives}

      # Internal: delete value at nested path
      %Internal.DeletePath{path: path}, {a, directives} ->
        {_, new_state} = pop_in(a.state, path)
        {%{a | state: new_state}, directives}

      # External: any directive struct
      %_{} = directive, {a, directives} ->
        {a, directives ++ [directive]}
    end)
  end

  # Helper to put a value at a nested path, creating intermediate maps if needed
  defp deep_put_in(map, [key], value) do
    Map.put(map, key, value)
  end

  defp deep_put_in(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, deep_put_in(nested, rest, value))
  end
end
