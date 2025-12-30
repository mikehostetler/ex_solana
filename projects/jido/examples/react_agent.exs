#!/usr/bin/env elixir
# Run with: mix run examples/react_agent.exs
#
# Requires ANTHROPIC_API_KEY environment variable.
# Uses claude-haiku for cost efficiency.

defmodule ReActRunner do
  @moduledoc """
  Demo runner for the ReAct agent.
  """

  alias Jido.AgentServer
  alias Jido.Examples.ReAct.Agent

  def run do
    IO.puts("\n🤖 Starting Jido ReAct Agent Demo\n")
    IO.puts("=" |> String.duplicate(50))

    unless System.get_env("ANTHROPIC_API_KEY") do
      IO.puts("\n❌ Error: ANTHROPIC_API_KEY environment variable not set")
      IO.puts("Set it with: export ANTHROPIC_API_KEY=your_key")
      System.halt(1)
    end

    {:ok, pid} = AgentServer.start(agent: Agent)
    IO.puts("✅ Agent started: #{inspect(pid)}")

    query = "What is 15 multiplied by 7? Also, what's the weather in Portland?"
    IO.puts("\n📝 Query: #{query}\n")
    IO.puts("-" |> String.duplicate(50))

    Agent.ask(pid, query)

    wait_for_completion(pid, 30_000)
  end

  defp wait_for_completion(pid, timeout) do
    start = System.monotonic_time(:millisecond)

    result =
      Stream.repeatedly(fn ->
        Process.sleep(200)

        case AgentServer.state(pid) do
          {:ok, %{agent: %{state: %{completed: true, last_answer: answer}}}}
          when is_binary(answer) and answer != "" ->
            {:done, answer}

          {:ok, %{agent: %{state: %{__strategy__: %{status: :error, final_answer: answer}}}}} ->
            {:error, answer}

          {:ok, %{agent: agent}} ->
            elapsed = System.monotonic_time(:millisecond) - start

            if elapsed > timeout do
              {:timeout, agent.state}
            else
              strat = agent.state.__strategy__ || %{}
              status = strat[:status] || :unknown
              iteration = strat[:iteration] || 0
              IO.write("\r⏳ Status: #{status}, Iteration: #{iteration}...")
              :continue
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)
      |> Enum.find(&(&1 != :continue))

    case result do
      {:done, answer} ->
        IO.puts("\n\n" <> ("=" |> String.duplicate(50)))
        IO.puts("✅ Final Answer:")
        IO.puts("-" |> String.duplicate(50))
        IO.puts(answer)
        IO.puts("=" |> String.duplicate(50))

      {:error, error} ->
        IO.puts("\n\n❌ Error: #{inspect(error)}")

      {:timeout, state} ->
        IO.puts("\n\n⏰ Timeout! Last state: #{inspect(state, pretty: true)}")
    end

    GenServer.stop(pid, :normal)
    IO.puts("\n🛑 Agent stopped")
  end
end

ReActRunner.run()
