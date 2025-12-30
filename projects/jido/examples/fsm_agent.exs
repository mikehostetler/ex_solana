#!/usr/bin/env elixir
# Run with: mix run examples/fsm_agent.exs
#
# This example demonstrates the FSM (Finite State Machine) strategy.
# No LLM calls - pure state machine transitions.

Logger.configure(level: :warning)

defmodule IncrementAction do
  @moduledoc "Simple action that increments a counter"
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, %{state: state}) do
    current = Map.get(state, :counter, 0)
    {:ok, %{counter: current + amount}}
  end
end

defmodule MultiplyAction do
  @moduledoc "Action that multiplies the counter"
  use Jido.Action,
    name: "multiply",
    schema: [factor: [type: :integer, required: true]]

  def run(%{factor: factor}, %{state: state}) do
    current = Map.get(state, :counter, 0)
    {:ok, %{counter: current * factor}}
  end
end

defmodule GreetAction do
  @moduledoc "Action that sets a greeting message"
  use Jido.Action,
    name: "greet",
    schema: [name: [type: :string, required: true]]

  def run(%{name: name}, _context) do
    {:ok, %{message: "Hello, #{name}!"}}
  end
end

defmodule FSMDemoAgent do
  @moduledoc "Demo agent using the FSM strategy"
  use Jido.Agent,
    name: "fsm_demo_agent",
    description: "Demonstrates FSM-based execution",
    strategy: Jido.Agent.Strategy.FSM,
    schema: [
      counter: [type: :integer, default: 0],
      message: [type: :string, default: ""]
    ]
end

defmodule FSMRunner do
  @moduledoc "Runner for FSM agent demo"

  alias Jido.Agent.Strategy.FSM

  def run do
    IO.puts("\n>>> Jido FSM Strategy Demo\n")
    IO.puts(String.duplicate("=", 60))

    # Create agent
    agent = FSMDemoAgent.new()
    IO.puts("\n[1] Created agent with initial state:")
    print_state(agent)

    # Single action
    IO.puts("\n[2] Running IncrementAction (amount: 5)...")
    {agent, _directives} = FSMDemoAgent.cmd(agent, {IncrementAction, %{amount: 5}})
    print_state(agent)
    print_fsm_snapshot(agent)

    # Another action
    IO.puts("\n[3] Running MultiplyAction (factor: 3)...")
    {agent, _directives} = FSMDemoAgent.cmd(agent, {MultiplyAction, %{factor: 3}})
    print_state(agent)

    # Multiple actions in sequence
    IO.puts("\n[4] Running multiple actions...")
    {agent, _directives} =
      FSMDemoAgent.cmd(agent, [
        {IncrementAction, %{amount: 7}},
        {GreetAction, %{name: "Jido"}}
      ])
    print_state(agent)

    # Show final FSM details
    IO.puts("\n[5] Final FSM snapshot:")
    print_fsm_snapshot(agent)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("[DONE] FSM Strategy demo complete")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp print_state(agent) do
    IO.puts("    counter: #{agent.state.counter}")
    IO.puts("    message: #{inspect(agent.state.message)}")
  end

  defp print_fsm_snapshot(agent) do
    snapshot = FSM.snapshot(agent, %{})
    IO.puts("    FSM status: #{snapshot.status}")
    IO.puts("    FSM done?: #{snapshot.done?}")
    IO.puts("    processed_count: #{snapshot.details.processed_count}")
  end
end

FSMRunner.run()
