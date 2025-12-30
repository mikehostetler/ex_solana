defmodule Jido.Examples.HelloWorld do
  @moduledoc """
  A simple Hello World HTN domain example demonstrating basic hierarchical task decomposition.

  This example shows:
  - Compound task decomposition (greeting -> greet_world -> say_hello & say_goodbye)
  - Primitive actions using Jido.Tools.Basic.Log
  - Basic state management with a simple counter

  ## Running

      mix run -e "Jido.Examples.HelloWorld.run()"
  """

  def run do
    IO.puts("\n=== Hello World HTN Example ===\n")

    world_state = %{
      greeted: false,
      count: 0
    }

    case Jido.HTN.plan(domain(), world_state) do
      {:ok, plan, _mtr} ->
        IO.puts("Generated plan:")

        Enum.each(plan, fn {action, params} ->
          IO.puts("  - #{inspect(action)} with params #{inspect(params)}")
        end)

        IO.puts("\nExecuting plan...\n")
        execute_plan(plan, world_state)

      {:error, reason} ->
        IO.puts("Planning failed: #{inspect(reason)}")
    end
  end

  defp execute_plan(plan, state) do
    Enum.reduce(plan, state, fn {action_mod, params}, acc_state ->
      param_map = Enum.into(params, %{})

      case action_mod.run(param_map, %{}) do
        {:ok, _result} ->
          Map.update(acc_state, :count, 0, &(&1 + 1))

        {:error, reason} ->
          IO.puts("Action failed: #{inspect(reason)}")
          acc_state
      end
    end)
  end

  def domain do
    alias Jido.HTN.Domain, as: D
    alias Jido.Tools.Basic, as: B

    "HelloWorld"
    |> D.new()
    |> D.compound("root",
      methods: [%{subtasks: ["greeting"]}]
    )
    |> D.compound("greeting",
      methods: [
        %{
          subtasks: ["greet_world"],
          conditions: [&not_greeted?/1]
        }
      ]
    )
    |> D.compound("greet_world",
      methods: [
        %{
          subtasks: ["say_hello", "say_goodbye"]
        }
      ]
    )
    |> D.primitive(
      "say_hello",
      {B.Log, level: :info, message: "Hello, World! 🌍"},
      expected_effects: [&mark_greeted/1]
    )
    |> D.primitive(
      "say_goodbye",
      {B.Log, level: :info, message: "Goodbye, World! 👋"},
      preconditions: [&greeted?/1]
    )
    |> D.allow("say_hello", B.Log)
    |> D.allow("say_goodbye", B.Log)
    |> D.build!()
  end

  defp not_greeted?(state), do: !state.greeted
  defp greeted?(state), do: state.greeted
  defp mark_greeted(state), do: %{state | greeted: true}
end
