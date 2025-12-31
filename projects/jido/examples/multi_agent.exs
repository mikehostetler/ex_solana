#!/usr/bin/env elixir
# Run with: mix run examples/multi_agent.exs
#
# Requires ANTHROPIC_API_KEY environment variable.
#
# This example demonstrates multi-agent capabilities:
# - A coordinator agent spawns a worker agent via SpawnAgent directive
# - Coordinator receives jido.agent.child.started signal when worker is ready
# - Worker performs LLM call via ReqLLMStream directive
# - Worker sends result back to coordinator via emit_to_parent helper
# - Different PIDs visible for parent/child agents

Logger.configure(level: :info)

defmodule WorkerAgent do
  @moduledoc "Worker agent that performs LLM calls using ReqLLMStream directive"
  use Jido.Agent,
    name: "worker_agent",
    schema: [
      query: [type: :string, default: ""],
      streaming_text: [type: :string, default: ""],
      answer: [type: :string, default: ""],
      status: [type: :atom, default: :idle],
      call_id: [type: :string, default: ""]
    ]

  alias Jido.Agent.Directive
  alias Jido.AI.Directive, as: AIDirective
  alias Jido.Signal

  def handle_signal(agent, %Signal{type: "worker.query", data: data} = _signal) do
    query = data[:query] || data["query"]
    IO.puts("  [Worker #{inspect(self())}] Received query: #{query}")

    call_id = "llm_#{:erlang.unique_integer([:positive])}"

    agent = %{
      agent
      | state: Map.merge(agent.state, %{query: query, call_id: call_id, status: :working})
    }

    context = [
      %{role: :system, content: "You are a helpful assistant. Keep answers brief (1-2 sentences)."},
      %{role: :user, content: query}
    ]

    llm_directive =
      AIDirective.ReqLLMStream.new!(%{
        id: call_id,
        model: "anthropic:claude-haiku-4-5",
        context: context,
        tools: [],
        max_tokens: 100
      })

    {agent, [llm_directive]}
  end

  def handle_signal(agent, %Signal{type: "reqllm.partial", data: data} = _signal) do
    current = agent.state.streaming_text || ""
    delta = data[:delta] || data["delta"] || ""
    IO.write(delta)
    agent = %{agent | state: Map.put(agent.state, :streaming_text, current <> delta)}
    {agent, []}
  end

  def handle_signal(agent, %Signal{type: "reqllm.result", data: data} = _signal) do
    result = data[:result] || data["result"]

    answer =
      case result do
        {:ok, %{text: text}} -> text
        {:error, reason} -> "Error: #{inspect(reason)}"
        other -> inspect(other)
      end

    IO.puts("\n  [Worker #{inspect(self())}] LLM complete")

    agent = %{
      agent
      | state: Map.merge(agent.state, %{answer: answer, status: :completed})
    }

    # Use the new emit_to_parent helper
    reply_signal = Signal.new!("worker.answer", %{answer: answer}, source: "/worker")
    emit_directive = Directive.emit_to_parent(agent, reply_signal)

    if emit_directive do
      IO.puts("  [Worker #{inspect(self())}] Sending answer to parent")
    end

    {agent, List.wrap(emit_directive)}
  end

  def handle_signal(agent, signal) do
    IO.puts("  [Worker] Unhandled signal: #{signal.type}")
    {agent, []}
  end
end

defmodule CoordinatorAgent do
  @moduledoc "Coordinator agent that spawns workers using SpawnAgent directive"
  use Jido.Agent,
    name: "coordinator_agent",
    schema: [
      pending_query: [type: :string, default: ""],
      answers: [type: {:list, :map}, default: []],
      worker_pid: [type: :any, default: nil],
      status: [type: :atom, default: :idle]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  # Handle request to spawn worker and query
  def handle_signal(agent, %Signal{type: "coordinator.start_work", data: data} = _signal) do
    query = data[:query] || data["query"]
    IO.puts("[Coordinator #{inspect(self())}] Starting work with query: #{query}")

    agent = %{agent | state: Map.merge(agent.state, %{pending_query: query, status: :spawning})}

    # Use SpawnAgent directive - parent will receive jido.agent.child.started
    spawn_directive = Directive.spawn_agent(WorkerAgent, :llm_worker)

    {agent, [spawn_directive]}
  end

  # Handle child started notification - worker is ready!
  def handle_signal(agent, %Signal{type: "jido.agent.child.started", data: data} = _signal) do
    IO.puts("[Coordinator #{inspect(self())}] Worker started: #{inspect(data.pid)}")
    IO.puts("    Child ID: #{data.child_id}")
    IO.puts("    Tag: #{inspect(data.tag)}")

    agent = %{agent | state: Map.put(agent.state, :worker_pid, data.pid)}

    # Now send work to the child
    query = agent.state.pending_query

    work_signal = Signal.new!("worker.query", %{query: query}, source: "/coordinator")
    emit_directive = Directive.emit_to_pid(work_signal, data.pid)

    IO.puts("[Coordinator #{inspect(self())}] Sending query to worker")
    agent = %{agent | state: Map.put(agent.state, :status, :awaiting_answer)}

    {agent, [emit_directive]}
  end

  # Handle answer from worker
  def handle_signal(agent, %Signal{type: "worker.answer", data: %{answer: answer}} = _signal) do
    IO.puts("[Coordinator #{inspect(self())}] Received answer from worker!")

    answers = [%{answer: answer} | Map.get(agent.state, :answers, [])]

    agent = %{
      agent
      | state: %{
          agent.state
          | answers: answers,
            pending_query: "",
            status: :completed
        }
    }

    {agent, []}
  end

  def handle_signal(agent, signal) do
    IO.puts("[Coordinator] Unhandled signal: #{signal.type}")
    {agent, []}
  end
end

defmodule MultiAgentRunner do
  @moduledoc "Runner for multi-agent demo"

  alias Jido.AgentServer
  alias Jido.Signal

  def run do
    IO.puts("\n>>> Jido Multi-Agent Demo\n")
    IO.puts(String.duplicate("=", 60))

    unless System.get_env("ANTHROPIC_API_KEY") do
      IO.puts("\n[ERROR] ANTHROPIC_API_KEY environment variable not set")
      IO.puts("Set it with: export ANTHROPIC_API_KEY=your_key")
      System.halt(1)
    end

    # Start coordinator
    {:ok, coordinator_pid} = AgentServer.start(agent: CoordinatorAgent, id: "coordinator-1")
    IO.puts("\n[1] Started coordinator: #{inspect(coordinator_pid)}")

    # Send work request - coordinator will spawn worker via SpawnAgent directive
    query = "What is the capital of France?"
    IO.puts("\n[2] Sending work request with query: #{query}")
    IO.puts(String.duplicate("-", 60))

    signal =
      Signal.new!(
        "coordinator.start_work",
        %{query: query},
        source: "/demo"
      )

    AgentServer.cast(coordinator_pid, signal)

    IO.puts("\n[3] Waiting for response (streaming)...\n")

    # Use the new MultiAgent helper to wait for completion
    case wait_for_coordinator_completion(coordinator_pid, 30_000) do
      {:ok, answers} ->
        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("[DONE] Multi-agent demo complete")
        IO.puts("\nFinal answers:")

        for answer <- Enum.reverse(answers) do
          IO.puts("  - #{answer.answer}")
        end

        IO.puts(String.duplicate("=", 60) <> "\n")

      {:error, reason} ->
        IO.puts("\n[ERROR] #{inspect(reason)}")
    end

    # Cleanup
    GenServer.stop(coordinator_pid, :normal)
  end

  defp wait_for_coordinator_completion(pid, timeout) do
    start = System.monotonic_time(:millisecond)

    Stream.repeatedly(fn ->
      Process.sleep(200)

      case AgentServer.state(pid) do
        {:ok, %{agent: %{state: %{status: :completed, answers: answers}}}}
        when is_list(answers) and length(answers) > 0 ->
          {:done, answers}

        {:ok, _state} ->
          elapsed = System.monotonic_time(:millisecond) - start

          if elapsed > timeout do
            {:timeout}
          else
            :continue
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> Enum.reduce_while(nil, fn
      {:done, answers}, _acc ->
        {:halt, {:ok, answers}}

      {:timeout}, _acc ->
        {:halt, {:error, :timeout}}

      {:error, reason}, _acc ->
        {:halt, {:error, reason}}

      :continue, _acc ->
        {:cont, nil}
    end)
  end
end

MultiAgentRunner.run()
