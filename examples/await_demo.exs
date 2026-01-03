#!/usr/bin/env elixir
# Run with: mix run examples/await_demo.exs
#
# This example demonstrates the event-driven Jido.Await module:
# - Single agent completion waiting (no polling!)
# - Multiple agent coordination with await_all/await_any
# - Parent-child coordination with await_child
# - Timeout handling
# - Failed agent handling

Logger.configure(level: :info)

# ---------------------------------------------------------------------------
# Action Modules
# ---------------------------------------------------------------------------

defmodule StartWorkAction do
  @moduledoc "Starts work and schedules completion"
  use Jido.Action,
    name: "start_work",
    schema: [
      work_id: [type: :string, required: true],
      delay_ms: [type: :integer, default: 100]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{work_id: work_id, delay_ms: delay_ms}, _context) do
    complete_signal = Signal.new!("worker.complete", %{work_id: work_id}, source: "/worker")
    schedule = Directive.schedule(delay_ms, complete_signal)
    {:ok, %{work_id: work_id, status: :working}, [schedule]}
  end
end

defmodule CompleteWorkAction do
  @moduledoc "Marks work as completed"
  use Jido.Action,
    name: "complete_work",
    schema: [
      work_id: [type: :string, required: true]
    ]

  def run(%{work_id: work_id}, _context) do
    {:ok, %{status: :completed, last_answer: "Completed work: #{work_id}"}}
  end
end

defmodule FailWorkAction do
  @moduledoc "Marks work as failed"
  use Jido.Action,
    name: "fail_work",
    schema: [
      reason: [type: :atom, default: :unknown_error]
    ]

  def run(%{reason: reason}, _context) do
    {:ok, %{status: :failed, error: reason}}
  end
end

defmodule CancelWorkAction do
  @moduledoc "Cancels work"
  use Jido.Action,
    name: "cancel_work",
    schema: [
      reason: [type: :any, default: :client_cancelled]
    ]

  def run(%{reason: reason}, _context) do
    {:ok, %{status: :failed, error: {:cancelled, reason}}}
  end
end

defmodule SpawnWorkerAction do
  @moduledoc "Spawns a child worker"
  use Jido.Action,
    name: "spawn_worker",
    schema: [
      tag: [type: :atom, required: true],
      delay_ms: [type: :integer, default: 100]
    ]

  alias Jido.Agent.Directive

  def run(%{tag: tag, delay_ms: delay_ms}, _context) do
    spawn_directive = Directive.spawn_agent(SimpleWorker, tag, initial_state: %{delay_ms: delay_ms})
    {:ok, %{pending_work: [tag]}, [spawn_directive]}
  end
end

defmodule ChildStartedAction do
  @moduledoc "Handles child started notification"
  use Jido.Action,
    name: "child_started",
    schema: [
      child_id: [type: :string, required: true],
      tag: [type: :atom, required: true],
      pid: [type: :any, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{tag: tag, pid: pid}, _context) do
    work_signal = Signal.new!("worker.start", %{work_id: "#{tag}", delay_ms: 100}, source: "/coordinator")
    emit = Directive.emit_to_pid(work_signal, pid)
    {:ok, %{}, [emit]}
  end
end

defmodule ChildExitAction do
  @moduledoc "Handles child exit notification"
  use Jido.Action,
    name: "child_exit",
    schema: [
      tag: [type: :any, required: true],
      pid: [type: :any, required: true],
      reason: [type: :any, required: true]
    ]

  def run(%{tag: tag, reason: reason}, _context) do
    IO.puts("  [Coordinator] Child #{inspect(tag)} exited: #{inspect(reason)}")
    {:ok, %{}}
  end
end

# ---------------------------------------------------------------------------
# Agent Modules
# ---------------------------------------------------------------------------

defmodule SimpleWorker do
  @moduledoc "A simple agent that completes after a delay"
  use Jido.Agent,
    name: "simple_worker",
    schema: [
      work_id: [type: :string, default: ""],
      delay_ms: [type: :integer, default: 100],
      status: [type: :atom, default: :idle],
      last_answer: [type: :any, default: nil],
      error: [type: :any, default: nil]
    ]

  def signal_routes do
    [
      {"worker.start", StartWorkAction},
      {"worker.complete", CompleteWorkAction},
      {"worker.fail", FailWorkAction},
      {"jido.agent.cancel", CancelWorkAction}
    ]
  end
end

defmodule CoordinatorAgent do
  @moduledoc "Coordinator that spawns child workers"
  use Jido.Agent,
    name: "coordinator",
    schema: [
      pending_work: [type: {:list, :atom}, default: []],
      results: [type: {:list, :map}, default: []],
      status: [type: :atom, default: :idle],
      last_answer: [type: :any, default: nil]
    ]

  def signal_routes do
    [
      {"coordinator.spawn_worker", SpawnWorkerAction},
      {"jido.agent.child.started", ChildStartedAction},
      {"jido.agent.child.exit", ChildExitAction}
    ]
  end
end

# ---------------------------------------------------------------------------
# Demo Runner
# ---------------------------------------------------------------------------

defmodule AwaitDemoRunner do
  @moduledoc "Runner for await demo"

  alias Jido.Signal

  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts(">>> Jido.Await Event-Driven Demo")
    IO.puts(String.duplicate("=", 70))

    {:ok, _} = Jido.start_link(name: AwaitDemo.Jido)

    demo_single_completion()
    demo_immediate_completion()
    demo_failed_agent()
    demo_timeout()
    demo_await_all()
    demo_await_any()
    demo_await_child()
    demo_multiple_waiters()

    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts(">>> All demos completed successfully!")
    IO.puts(String.duplicate("=", 70) <> "\n")
  end

  defp demo_single_completion do
    IO.puts("\n[1] Single Agent Completion (event-driven, no polling)")
    IO.puts(String.duplicate("-", 50))

    {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "worker-1")
    IO.puts("  Started worker: #{inspect(pid)}")

    signal = Signal.new!("worker.start", %{work_id: "task-001", delay_ms: 200}, source: "/demo")
    Jido.AgentServer.cast(pid, signal)
    IO.puts("  Sent work signal, waiting for completion...")

    start = System.monotonic_time(:millisecond)
    result = Jido.await(pid, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, %{status: :completed, result: answer}} ->
        IO.puts("  ✓ Completed in #{elapsed}ms: #{answer}")

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    GenServer.stop(pid)
  end

  defp demo_immediate_completion do
    IO.puts("\n[2] Immediate Completion (already completed)")
    IO.puts(String.duplicate("-", 50))

    {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "worker-immed")

    signal = Signal.new!("worker.start", %{work_id: "quick", delay_ms: 10}, source: "/demo")
    Jido.AgentServer.cast(pid, signal)
    Process.sleep(50)

    start = System.monotonic_time(:millisecond)
    {:ok, %{status: :completed}} = Jido.await(pid, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    IO.puts("  ✓ Await returned immediately (#{elapsed}ms) for already-completed agent")

    GenServer.stop(pid)
  end

  defp demo_failed_agent do
    IO.puts("\n[3] Failed Agent Handling")
    IO.puts(String.duplicate("-", 50))

    {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "worker-fail")

    signal = Signal.new!("worker.fail", %{reason: :simulated_error}, source: "/demo")
    Jido.AgentServer.cast(pid, signal)

    case Jido.await(pid, 5_000) do
      {:ok, %{status: :failed, result: reason}} ->
        IO.puts("  ✓ Correctly detected failed status: #{inspect(reason)}")

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    GenServer.stop(pid)
  end

  defp demo_timeout do
    IO.puts("\n[4] Timeout Handling")
    IO.puts(String.duplicate("-", 50))

    {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "worker-slow")

    signal = Signal.new!("worker.start", %{work_id: "slow", delay_ms: 5000}, source: "/demo")
    Jido.AgentServer.cast(pid, signal)

    start = System.monotonic_time(:millisecond)
    result = Jido.await(pid, 100)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:error, :timeout} ->
        IO.puts("  ✓ Timeout returned correctly after ~#{elapsed}ms")

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    GenServer.stop(pid)
  end

  defp demo_await_all do
    IO.puts("\n[5] Await All - Multiple Agents")
    IO.puts(String.duplicate("-", 50))

    pids =
      for i <- 1..3 do
        {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "all-worker-#{i}")
        delay = 100 + i * 50
        signal = Signal.new!("worker.start", %{work_id: "parallel-#{i}", delay_ms: delay}, source: "/demo")
        Jido.AgentServer.cast(pid, signal)
        pid
      end

    IO.puts("  Started #{length(pids)} workers with staggered delays")

    start = System.monotonic_time(:millisecond)
    result = Jido.await_all(pids, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, results} when map_size(results) == 3 ->
        IO.puts("  ✓ All #{map_size(results)} agents completed in #{elapsed}ms")
        Enum.each(results, fn {_pid, %{result: r}} ->
          IO.puts("    - #{r}")
        end)

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    Enum.each(pids, &GenServer.stop/1)
  end

  defp demo_await_any do
    IO.puts("\n[6] Await Any - First to Complete")
    IO.puts(String.duplicate("-", 50))

    pids =
      for {i, delay} <- [{1, 500}, {2, 100}, {3, 300}] do
        {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "any-worker-#{i}")
        signal = Signal.new!("worker.start", %{work_id: "race-#{i}", delay_ms: delay}, source: "/demo")
        Jido.AgentServer.cast(pid, signal)
        {pid, delay}
      end

    pid_list = Enum.map(pids, fn {pid, _} -> pid end)
    IO.puts("  Started 3 workers with delays: 500ms, 100ms, 300ms")

    start = System.monotonic_time(:millisecond)
    result = Jido.await_any(pid_list, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, {_winner, %{status: :completed, result: answer}}} ->
        IO.puts("  ✓ First completion in #{elapsed}ms: #{answer}")

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    Enum.each(pid_list, &GenServer.stop/1)
  end

  defp demo_await_child do
    IO.puts("\n[7] Await Child - Parent-Child Coordination")
    IO.puts(String.duplicate("-", 50))

    {:ok, coordinator} = Jido.start_agent(AwaitDemo.Jido, CoordinatorAgent, id: "coord-1")
    IO.puts("  Started coordinator: #{inspect(coordinator)}")

    signal = Signal.new!("coordinator.spawn_worker", %{tag: :my_worker, delay_ms: 150}, source: "/demo")
    Jido.AgentServer.cast(coordinator, signal)
    IO.puts("  Instructed coordinator to spawn child worker")

    start = System.monotonic_time(:millisecond)
    result = Jido.await_child(coordinator, :my_worker, 5_000)
    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, %{status: :completed, result: answer}} ->
        IO.puts("  ✓ Child completed in #{elapsed}ms: #{answer}")

      other ->
        IO.puts("  ✗ Unexpected result: #{inspect(other)}")
    end

    GenServer.stop(coordinator)
  end

  defp demo_multiple_waiters do
    IO.puts("\n[8] Multiple Waiters on Same Agent")
    IO.puts(String.duplicate("-", 50))

    {:ok, pid} = Jido.start_agent(AwaitDemo.Jido, SimpleWorker, id: "multi-wait")

    signal = Signal.new!("worker.start", %{work_id: "shared", delay_ms: 200}, source: "/demo")
    Jido.AgentServer.cast(pid, signal)

    parent = self()

    tasks =
      for i <- 1..3 do
        Task.async(fn ->
          start = System.monotonic_time(:millisecond)
          result = Jido.await(pid, 5_000)
          elapsed = System.monotonic_time(:millisecond) - start
          send(parent, {:waiter_done, i, elapsed, result})
          result
        end)
      end

    IO.puts("  Started 3 concurrent waiters on the same agent")

    results = Task.await_many(tasks, 10_000)

    all_ok = Enum.all?(results, fn
      {:ok, %{status: :completed}} -> true
      _ -> false
    end)

    if all_ok do
      IO.puts("  ✓ All 3 waiters received completion notification")
      receive_all_waiter_messages()
    else
      IO.puts("  ✗ Some waiters failed: #{inspect(results)}")
    end

    GenServer.stop(pid)
  end

  defp receive_all_waiter_messages do
    receive do
      {:waiter_done, i, elapsed, {:ok, _}} ->
        IO.puts("    - Waiter #{i}: completed in #{elapsed}ms")
        receive_all_waiter_messages()
    after
      0 -> :done
    end
  end
end

AwaitDemoRunner.run()
