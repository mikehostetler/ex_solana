defmodule Jido.Agent.Strategy.FSM do
  @moduledoc """
  A finite state machine execution strategy using Fsmx.

  This strategy demonstrates how to implement a simple FSM-based workflow
  where instructions trigger state transitions. The FSM state is stored
  in `agent.state.__strategy__`.

  ## States

  - `:idle` - Initial state, waiting for work
  - `:processing` - Currently processing an instruction
  - `:completed` - Successfully finished
  - `:failed` - Terminated with an error

  ## Usage

      defmodule MyAgent do
        use Jido.Agent,
          name: "fsm_agent",
          strategy: Jido.Agent.Strategy.FSM
      end

      agent = MyAgent.new()
      {agent, directives} = MyAgent.cmd(agent, SomeAction, %{data: "value"})

  The strategy automatically transitions through states as instructions execute.
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Internal
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Error
  alias Jido.Instruction

  defmodule Machine do
    @moduledoc false
    use Fsmx.Struct,
      state_field: :status,
      transitions: %{
        "idle" => ["processing"],
        "processing" => ["idle", "completed", "failed"],
        "completed" => ["idle"],
        "failed" => ["idle"]
      }

    @type t :: %__MODULE__{
            status: String.t(),
            processed_count: non_neg_integer(),
            last_result: term(),
            error: term()
          }

    defstruct status: "idle",
              processed_count: 0,
              last_result: nil,
              error: nil

    def new, do: %__MODULE__{}

    def transition(%__MODULE__{} = machine, new_status) do
      Fsmx.transition(machine, new_status, state_field: :status)
    end
  end

  @impl true
  def init(agent, _ctx) do
    machine = Machine.new()
    agent = StratState.put(agent, %{machine: machine, module: __MODULE__})
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) when is_list(instructions) do
    state = StratState.get(agent, %{})
    machine = Map.get(state, :machine) || Machine.new()

    case Machine.transition(machine, "processing") do
      {:ok, machine} ->
        {agent, machine, directives} = process_instructions(agent, machine, instructions)
        agent = StratState.put(agent, %{state | machine: machine})
        {agent, directives}

      {:error, reason} ->
        error = Error.execution_error("FSM transition failed", %{reason: reason})
        {agent, [%Directive.Error{error: error, context: :fsm_transition}]}
    end
  end

  defp process_instructions(agent, machine, instructions) do
    {agent, machine, directives} =
      Enum.reduce(instructions, {agent, machine, []}, fn instruction, {acc_agent, acc_machine, acc_directives} ->
        {new_agent, new_machine, new_directives} = run_instruction(acc_agent, acc_machine, instruction)
        {new_agent, new_machine, acc_directives ++ new_directives}
      end)

    case Machine.transition(machine, "idle") do
      {:ok, machine} -> {agent, machine, directives}
      {:error, _} -> {agent, machine, directives}
    end
  end

  defp run_instruction(agent, machine, %Instruction{} = instruction) do
    instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

    case Jido.Exec.run(instruction) do
      {:ok, result} when is_map(result) ->
        machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
        {apply_result(agent, result), machine, []}

      {:ok, result, effects} when is_map(result) ->
        machine = %{machine | processed_count: machine.processed_count + 1, last_result: result}
        agent = apply_result(agent, result)
        {agent, directives} = apply_effects(agent, List.wrap(effects))
        {agent, machine, directives}

      {:error, reason} ->
        machine = %{machine | error: reason}
        error = Error.execution_error("Instruction failed", %{reason: reason})
        {agent, machine, [%Directive.Error{error: error, context: :instruction}]}
    end
  end

  defp apply_result(agent, result) when is_map(result) do
    new_state = Jido.Agent.State.merge(agent.state, result)
    %{agent | state: new_state}
  end

  defp apply_effects(agent, effects) do
    Enum.reduce(effects, {agent, []}, fn
      %Internal.SetState{attrs: attrs}, {a, directives} ->
        new_state = Jido.Agent.State.merge(a.state, attrs)
        {%{a | state: new_state}, directives}

      %Internal.ReplaceState{state: new_state}, {a, directives} ->
        {%{a | state: new_state}, directives}

      %Internal.DeleteKeys{keys: keys}, {a, directives} ->
        new_state = Map.drop(a.state, keys)
        {%{a | state: new_state}, directives}

      %_{} = directive, {a, directives} ->
        {a, directives ++ [directive]}
    end)
  end

  @impl true
  def snapshot(agent, _ctx) do
    state = StratState.get(agent, %{})
    machine = Map.get(state, :machine, %{})
    status = parse_status(Map.get(machine, :status, "idle"))

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:success, :failure],
      result: Map.get(machine, :last_result),
      details: %{
        processed_count: Map.get(machine, :processed_count, 0),
        error: Map.get(machine, :error)
      }
    }
  end

  defp parse_status("idle"), do: :idle
  defp parse_status("processing"), do: :running
  defp parse_status("completed"), do: :success
  defp parse_status("failed"), do: :failure
  defp parse_status(_), do: :idle
end
