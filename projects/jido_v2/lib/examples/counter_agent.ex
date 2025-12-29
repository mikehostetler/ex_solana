defmodule Jido.Examples.CounterAgent do
  @moduledoc """
  A simple counter agent example demonstrating the Jido v2 agent contract.

  This agent:
  - Tracks a count value
  - Responds to increment/decrement/reset signals
  - Emits Reply effects for get_count requests

  ## Running

      mix run -e "Jido.Examples.CounterAgent.demo()"

  """
  use Jido.Agent,
    name: "counter",
    schema: %{
      count: Zoi.integer() |> Zoi.default(0),
      history: Zoi.array(Zoi.map()) |> Zoi.default([])
    }

  alias Jido.Agent.Effect
  alias Jido.Agent.Runner.Simple
  alias Jido.Signal

  @impl true
  def handle_signal(state, %Signal{type: "counter.increment"}) do
    new_state = %{
      state
      | count: state.count + 1,
        history: [%{action: :increment, at: DateTime.utc_now()} | state.history]
    }

    {:ok, new_state, []}
  end

  def handle_signal(state, %Signal{type: "counter.decrement"}) do
    new_state = %{
      state
      | count: state.count - 1,
        history: [%{action: :decrement, at: DateTime.utc_now()} | state.history]
    }

    {:ok, new_state, []}
  end

  def handle_signal(state, %Signal{type: "counter.reset"}) do
    new_state = %{
      state
      | count: 0,
        history: [%{action: :reset, at: DateTime.utc_now()} | state.history]
    }

    {:ok, new_state, []}
  end

  def handle_signal(state, %Signal{type: "counter.add", data: %{"amount" => amount}}) do
    new_state = %{
      state
      | count: state.count + amount,
        history: [%{action: :add, amount: amount, at: DateTime.utc_now()} | state.history]
    }

    {:ok, new_state, []}
  end

  def handle_signal(state, %Signal{type: "counter.get"}) do
    effects = [
      %Effect.Reply{
        signal: Signal.new!("counter.value", %{count: state.count}, source: "/counter")
      }
    ]

    {:ok, state, effects}
  end

  def handle_signal(state, _signal), do: {:ok, state, []}

  @doc """
  Demo function to exercise the CounterAgent.

  Run with: mix run -e "Jido.Examples.CounterAgent.demo()"
  """
  def demo do
    IO.puts("=== Jido v2 CounterAgent Demo ===\n")

    # Create a new agent
    {:ok, agent} = new(%{id: "demo-counter"})
    IO.puts("Created agent: #{agent.id}")
    IO.puts("Initial count: #{agent.count}\n")

    # Process some signals through the runner
    signals = [
      Signal.new!("counter.increment", %{}, source: "/demo"),
      Signal.new!("counter.increment", %{}, source: "/demo"),
      Signal.new!("counter.add", %{"amount" => 10}, source: "/demo"),
      Signal.new!("counter.decrement", %{}, source: "/demo"),
      Signal.new!("counter.get", %{}, source: "/demo")
    ]

    final_agent =
      Enum.reduce(signals, agent, fn signal, current_agent ->
        IO.puts("Processing signal: #{signal.type}")

        case Simple.handle(__MODULE__, current_agent, signal) do
          {:ok, new_agent, effects} ->
            IO.puts("  Count: #{new_agent.count}")

            Enum.each(effects, fn effect ->
              case effect do
                %Effect.Reply{signal: reply} ->
                  IO.puts("  Effect.Reply: #{reply.type} -> #{inspect(reply.data)}")

                other ->
                  IO.puts("  Effect: #{inspect(other)}")
              end
            end)

            new_agent

          {:error, reason} ->
            IO.puts("  Error: #{inspect(reason)}")
            current_agent
        end
      end)

    IO.puts("\n=== Final State ===")
    IO.puts("Count: #{final_agent.count}")
    IO.puts("History entries: #{length(final_agent.history)}")
    IO.puts("\nDemo complete!")
  end
end
