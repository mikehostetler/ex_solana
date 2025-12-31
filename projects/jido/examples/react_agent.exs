#!/usr/bin/env elixir
# Run with: mix run examples/react_agent.exs
#
# Requires ANTHROPIC_API_KEY environment variable.
# Uses claude-haiku for cost efficiency.
#
# This example demonstrates TRUE STREAMING - tokens appear as they arrive
# from the LLM, not buffered until completion.

# Suppress noisy logging - only show warnings and errors
Logger.configure(level: :warning)

defmodule ReActRunner do
  @moduledoc """
  Demo runner for the ReAct agent with streaming output.
  """

  alias Jido.AI.Examples.ReActDemoAgent, as: Agent

  def run do
    IO.puts("\n>>> Starting Jido ReAct Agent Demo (with Streaming)\n")
    IO.puts(String.duplicate("=", 70))

    unless System.get_env("ANTHROPIC_API_KEY") do
      IO.puts("\n[ERROR] ANTHROPIC_API_KEY environment variable not set")
      IO.puts("Set it with: export ANTHROPIC_API_KEY=your_key")
      System.halt(1)
    end

    # Start a Jido instance for the example
    {:ok, _} = Jido.start_link(name: ReActRunner.Jido)

    {:ok, pid} = Jido.start_agent(ReActRunner.Jido, Agent)
    IO.puts("[OK] Agent started\n")

    query = "What is 15 multiplied by 7? Also, what's the weather in Algonquin, IL?"
    IO.puts("Query: #{query}\n")
    IO.puts(String.duplicate("-", 70))
    IO.puts("\nStreaming response:\n")

    Agent.ask(pid, query)

    wait_for_completion_with_streaming(pid, 60_000)
  end

  defp wait_for_completion_with_streaming(pid, timeout) do
    start = System.monotonic_time(:millisecond)

    # Track: {last_streaming_text, last_iteration, last_status, shown_tools}
    initial_acc = {"", 0, :unknown, MapSet.new()}

    result =
      Stream.repeatedly(fn ->
        Process.sleep(30)

        case Jido.state(ReActRunner.Jido, pid) do
          {:ok, %{agent: %{state: %{completed: true, last_answer: answer}}}}
          when is_binary(answer) and answer != "" ->
            {:done, answer}

          {:ok, %{agent: %{state: %{__strategy__: %{status: :error, result: answer}}}}} ->
            {:error, answer}

          {:ok, %{agent: agent}} ->
            elapsed = System.monotonic_time(:millisecond) - start

            if elapsed > timeout do
              {:timeout, agent.state}
            else
              strat = agent.state.__strategy__ || %{}

              {:continue, %{
                status: strat[:status] || :unknown,
                iteration: strat[:iteration] || 0,
                streaming_text: strat[:streaming_text] || "",
                pending_tool_calls: strat[:pending_tool_calls] || []
              }}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end)
      |> Enum.reduce_while(initial_acc, fn
        {:done, answer}, _acc ->
          {:halt, {:done, answer}}

        {:error, error}, _acc ->
          {:halt, {:error, error}}

        {:timeout, state}, _acc ->
          {:halt, {:timeout, state}}

        {:continue, info}, {last_text, last_iter, last_status, shown_tools} ->
          %{
            status: status,
            iteration: iteration,
            streaming_text: streaming_text,
            pending_tool_calls: pending_tools
          } = info

          # Print new streaming text
          if String.length(streaming_text) > String.length(last_text) do
            new_text = String.slice(streaming_text, String.length(last_text)..-1//1)
            IO.write(new_text)
          end

          # Show tool calls when status changes to awaiting_tool
          shown_tools =
            if status == :awaiting_tool and last_status != :awaiting_tool and pending_tools != [] do
              IO.puts("\n")
              IO.puts(String.duplicate("-", 70))
              IO.puts("[TOOLS] Executing #{length(pending_tools)} tool(s):")

              for tool <- pending_tools do
                IO.puts("  - #{tool.name}")
                IO.puts("    Arguments: #{inspect(tool.arguments)}")
              end

              IO.puts(String.duplicate("-", 70))
              IO.puts("")

              MapSet.new(Enum.map(pending_tools, & &1.id))
            else
              shown_tools
            end

          # Show when tools complete and new iteration starts
          if iteration > last_iter and last_iter > 0 do
            IO.puts("[TOOLS] Complete. Continuing with iteration #{iteration}...\n")
          end

          {:cont, {streaming_text, iteration, status, shown_tools}}
      end)

    case result do
      {:done, _answer} ->
        IO.puts("\n\n" <> String.duplicate("=", 70))
        IO.puts("[DONE] Agent completed successfully")
        IO.puts(String.duplicate("=", 70))

      {:error, error} ->
        IO.puts("\n\n[ERROR] #{inspect(error)}")

      {:timeout, state} ->
        IO.puts("\n\n[TIMEOUT] Last state: #{inspect(state, pretty: true)}")
    end

    GenServer.stop(pid, :normal)
    IO.puts("\n[STOPPED] Agent stopped")
  end
end

ReActRunner.run()
