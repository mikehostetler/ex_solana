#!/usr/bin/env elixir
# Run with: mix run examples/bt_agent.exs
#
# This example demonstrates the BehaviorTree strategy.
# No LLM calls - pure behavior tree execution with Jido Actions.

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

defmodule CheckCounterAction do
  @moduledoc "Condition action that succeeds if counter is above threshold"
  use Jido.Action,
    name: "check_counter",
    schema: [threshold: [type: :integer, required: true]]

  def run(%{threshold: threshold}, %{state: state}) do
    current = Map.get(state, :counter, 0)

    if current >= threshold do
      {:ok, %{check_passed: true}}
    else
      {:error, "Counter #{current} is below threshold #{threshold}"}
    end
  end
end

defmodule BTDemoAgent do
  @moduledoc "Demo agent using the BehaviorTree strategy"

  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Sequence, Action}

  @tree Tree.new(
          Sequence.new([
            Action.new(IncrementAction, %{amount: 5}),
            Action.new(MultiplyAction, %{factor: 3}),
            Action.new(IncrementAction, %{amount: 7}),
            Action.new(GreetAction, %{name: "BehaviorTree"})
          ])
        )

  use Jido.Agent,
    name: "bt_demo_agent",
    description: "Demonstrates BehaviorTree-based execution",
    strategy: {Jido.Agent.Strategy.BehaviorTree, tree: @tree},
    schema: [
      counter: [type: :integer, default: 0],
      message: [type: :string, default: ""],
      check_passed: [type: :boolean, default: false]
    ]
end

defmodule SelectorDemoAgent do
  @moduledoc "Demo agent showing Selector (fallback) behavior"

  alias Jido.BehaviorTree.Tree
  alias Jido.BehaviorTree.Nodes.{Sequence, Selector, Action}

  @tree Tree.new(
          Sequence.new([
            Action.new(IncrementAction, %{amount: 3}),
            Selector.new([
              Action.new(CheckCounterAction, %{threshold: 10}),
              Action.new(IncrementAction, %{amount: 10})
            ]),
            Action.new(MultiplyAction, %{factor: 2})
          ])
        )

  use Jido.Agent,
    name: "selector_demo_agent",
    description: "Demonstrates Selector (fallback) behavior",
    strategy: {Jido.Agent.Strategy.BehaviorTree, tree: @tree},
    schema: [
      counter: [type: :integer, default: 0],
      check_passed: [type: :boolean, default: false]
    ]
end

defmodule BTRunner do
  @moduledoc "Runner for BehaviorTree agent demos"

  alias Jido.Agent.Strategy.BehaviorTree, as: BTStrategy

  def run do
    IO.puts("\n>>> Jido BehaviorTree Strategy Demo\n")
    IO.puts(String.duplicate("=", 60))

    run_sequence_demo()
    run_selector_demo()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("[DONE] BehaviorTree Strategy demos complete")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp run_sequence_demo do
    IO.puts("\n--- Sequence Demo (BTDemoAgent) ---\n")

    # Create agent
    agent = BTDemoAgent.new()
    IO.puts("[1] Created agent with initial state:")
    print_state(agent)

    # Run the behavior tree (single tick executes entire sequence)
    IO.puts("\n[2] Running BT tick (Sequence: Increment→Multiply→Increment→Greet)...")
    {agent, _directives} = BTDemoAgent.cmd(agent, :tick)
    print_state(agent)
    print_bt_snapshot(agent)
  end

  defp run_selector_demo do
    IO.puts("\n--- Selector Demo (SelectorDemoAgent) ---\n")

    # Create agent
    agent = SelectorDemoAgent.new()
    IO.puts("[1] Created agent with initial state:")
    print_state(agent)

    # Run the behavior tree
    IO.puts("\n[2] Running BT tick (Sequence with Selector fallback)...")
    IO.puts("    Selector: Check if counter >= 10, else increment by 10")
    {agent, _directives} = SelectorDemoAgent.cmd(agent, :tick)
    print_state(agent)
    print_bt_snapshot(agent)
  end

  defp print_state(agent) do
    IO.puts("    counter: #{Map.get(agent.state, :counter, 0)}")
    IO.puts("    message: #{inspect(Map.get(agent.state, :message, ""))}")
    IO.puts("    check_passed: #{Map.get(agent.state, :check_passed, false)}")
  end

  defp print_bt_snapshot(agent) do
    snapshot = BTStrategy.snapshot(agent, %{})
    IO.puts("    BT status: #{snapshot.status}")
    IO.puts("    BT done?: #{snapshot.done?}")
    IO.puts("    tick_count: #{snapshot.details.tick_count}")
    IO.puts("    tree_depth: #{snapshot.details.tree_depth}")
  end
end

BTRunner.run()
