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
  alias Jido.Agent.Effects
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
        {Effects.apply_result(agent, result), []}

      {:ok, result, effects} when is_map(result) ->
        agent = Effects.apply_result(agent, result)
        Effects.apply_effects(agent, List.wrap(effects))

      {:error, reason} ->
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :instruction}]}
    end
  end
end
