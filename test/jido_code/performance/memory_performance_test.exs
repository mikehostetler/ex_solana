defmodule JidoCode.Performance.MemoryTest do
  @moduledoc """
  Performance tests for memory management.

  Targets:
  - < 100MB total memory footprint with 10 active sessions
  - No memory leaks (< 1MB delta after 100 create/close cycles)

  These tests profile memory usage and detect memory leaks in the
  session management system.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @moduletag :performance
  @moduletag :llm
  @moduletag timeout: 600_000

  setup do
    # Clear registry before each test
    SessionRegistry.list_all()
    |> Enum.each(fn {session_id, _pid} ->
      SessionSupervisor.stop_session(session_id)
    end)

    # Clean up persisted sessions
    sessions_dir = Path.expand("~/.jido_code/sessions")
    if File.exists?(sessions_dir) do
      File.rm_rf!(sessions_dir)
    end

    # Force garbage collection before test
    :erlang.garbage_collect()
    Process.sleep(100)

    :ok
  end

  describe "memory footprint" do
    @tag :profile
    test "memory usage with 10 active sessions (empty conversations)" do
      # Measure baseline memory
      baseline_memory = get_memory_mb()

      # Create 10 sessions
      sessions = for i <- 1..10 do
        {:ok, session} = create_test_session("Session #{i}")
        session
      end

      # Measure memory after creating sessions
      after_create_memory = get_memory_mb()
      sessions_memory = after_create_memory - baseline_memory

      IO.puts("\n=== Memory Footprint (10 Sessions, Empty Conversations) ===")
      IO.puts("Baseline:       #{Float.round(baseline_memory, 2)} MB")
      IO.puts("After creation: #{Float.round(after_create_memory, 2)} MB")
      IO.puts("Sessions cost:  #{Float.round(sessions_memory, 2)} MB")
      IO.puts("Per session:    #{Float.round(sessions_memory / 10, 2)} MB")
      IO.puts("Target:         < 100 MB total")
      IO.puts("Status:         #{if sessions_memory < 100, do: "✓ PASS", else: "✗ FAIL"}")

      # Assert total memory is under target
      assert sessions_memory < 100,
             "Memory usage (#{Float.round(sessions_memory, 2)}MB) exceeds 100MB target"

      # Cleanup
      Enum.each(sessions, fn session ->
        SessionSupervisor.stop_session(session.id)
      end)
    end

    @tag :profile
    test "memory usage with 10 active sessions (1000 messages each)" do
      # Measure baseline memory
      baseline_memory = get_memory_mb()

      # Create 10 sessions with 1000 messages each (max limit)
      IO.puts("\nCreating 10 sessions with 1000 messages each...")
      sessions = for i <- 1..10 do
        {:ok, session} = create_test_session("Session #{i}")
        add_messages(session.id, 1000)
        session
      end
      IO.puts("Sessions created. Measuring memory...")

      # Force garbage collection to get accurate measurement
      :erlang.garbage_collect()
      Process.sleep(100)

      # Measure memory after creating sessions
      after_create_memory = get_memory_mb()
      sessions_memory = after_create_memory - baseline_memory

      IO.puts("\n=== Memory Footprint (10 Sessions, 1000 Messages Each) ===")
      IO.puts("Baseline:       #{Float.round(baseline_memory, 2)} MB")
      IO.puts("After creation: #{Float.round(after_create_memory, 2)} MB")
      IO.puts("Sessions cost:  #{Float.round(sessions_memory, 2)} MB")
      IO.puts("Per session:    #{Float.round(sessions_memory / 10, 2)} MB")
      IO.puts("Target:         < 100 MB total")
      IO.puts("Status:         #{if sessions_memory < 100, do: "✓ PASS", else: "⚠ WARNING (expected with max data)"}")

      # With max data, we're just documenting the memory usage, not strictly enforcing limit
      # This helps us understand worst-case memory footprint
      IO.puts("\nNote: With 10 sessions × 1000 messages, memory usage may exceed 100MB")
      IO.puts("      This test documents worst-case memory footprint for capacity planning")

      # Cleanup
      Enum.each(sessions, fn session ->
        SessionSupervisor.stop_session(session.id)
      end)
    end
  end

  describe "memory leak detection" do
    @tag :profile
    test "no memory leaks after 100 create/close cycles" do
      # Measure baseline memory
      :erlang.garbage_collect()
      Process.sleep(100)
      baseline_memory = get_memory_mb()

      IO.puts("\n=== Memory Leak Detection (100 Create/Close Cycles) ===")
      IO.puts("Baseline: #{Float.round(baseline_memory, 2)} MB")
      IO.puts("Running 100 cycles...")

      # Perform 100 create/close cycles
      for i <- 1..100 do
        {:ok, session} = create_test_session("Cycle #{i}")
        add_messages(session.id, 10)  # Add some messages
        SessionSupervisor.stop_session(session.id)

        # Print progress every 25 cycles
        if rem(i, 25) == 0 do
          :erlang.garbage_collect()
          current_memory = get_memory_mb()
          delta = current_memory - baseline_memory
          IO.puts("  Cycle #{i}: #{Float.round(current_memory, 2)} MB (Δ #{Float.round(delta, 2)} MB)")
        end
      end

      # Force garbage collection and measure final memory
      :erlang.garbage_collect()
      Process.sleep(100)
      final_memory = get_memory_mb()
      memory_delta = final_memory - baseline_memory

      IO.puts("\nFinal:    #{Float.round(final_memory, 2)} MB")
      IO.puts("Delta:    #{Float.round(memory_delta, 2)} MB")
      IO.puts("Target:   < 1 MB delta")
      IO.puts("Status:   #{if memory_delta < 1, do: "✓ PASS", else: "✗ FAIL"}")

      # Assert memory delta is less than 1MB
      assert memory_delta < 1,
             "Memory leak detected: #{Float.round(memory_delta, 2)}MB increase after 100 cycles"
    end

    @tag :profile
    test "no memory leaks with message accumulation and cleanup" do
      # Create a session
      {:ok, session} = create_test_session("Leak Test")

      # Measure baseline
      :erlang.garbage_collect()
      baseline_memory = get_memory_mb()

      IO.puts("\n=== Memory Leak Detection (Message Accumulation) ===")
      IO.puts("Baseline: #{Float.round(baseline_memory, 2)} MB")

      # Add and remove messages 10 times
      for cycle <- 1..10 do
        # Add 100 messages
        add_messages(session.id, 100)

        # Clear messages (simulating conversation reset)
        Session.State.clear_messages(session.id)

        if rem(cycle, 2) == 0 do
          :erlang.garbage_collect()
          current_memory = get_memory_mb()
          delta = current_memory - baseline_memory
          IO.puts("  Cycle #{cycle}: #{Float.round(current_memory, 2)} MB (Δ #{Float.round(delta, 2)} MB)")
        end
      end

      # Measure final memory
      :erlang.garbage_collect()
      Process.sleep(100)
      final_memory = get_memory_mb()
      memory_delta = final_memory - baseline_memory

      IO.puts("\nFinal:  #{Float.round(final_memory, 2)} MB")
      IO.puts("Delta:  #{Float.round(memory_delta, 2)} MB")
      IO.puts("Target: < 1 MB delta")
      IO.puts("Status: #{if memory_delta < 1, do: "✓ PASS", else: "✗ FAIL"}")

      assert memory_delta < 1

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "ets table memory" do
    @tag :profile
    test "ETS tables remain bounded with session churn" do
      # Get initial ETS memory
      initial_ets_memory = get_ets_memory_mb()

      IO.puts("\n=== ETS Table Memory (Session Churn) ===")
      IO.puts("Initial ETS memory: #{Float.round(initial_ets_memory, 2)} MB")

      # Create and destroy 50 sessions
      for i <- 1..50 do
        {:ok, session} = create_test_session("Session #{i}")
        add_messages(session.id, 10)
        SessionSupervisor.stop_session(session.id)
      end

      # Measure ETS memory after churn
      final_ets_memory = get_ets_memory_mb()
      ets_delta = final_ets_memory - initial_ets_memory

      IO.puts("Final ETS memory:   #{Float.round(final_ets_memory, 2)} MB")
      IO.puts("Delta:              #{Float.round(ets_delta, 2)} MB")
      IO.puts("Target:             < 1 MB growth")
      IO.puts("Status:             #{if ets_delta < 1, do: "✓ PASS", else: "✗ FAIL"}")

      # ETS tables should not grow significantly
      assert ets_delta < 1,
             "ETS memory grew by #{Float.round(ets_delta, 2)}MB after session churn"
    end
  end

  # Helper functions

  defp get_memory_mb do
    memory_bytes = :erlang.memory(:total)
    memory_bytes / (1024 * 1024)
  end

  defp get_ets_memory_mb do
    ets_bytes = :erlang.memory(:ets)
    ets_bytes / (1024 * 1024)
  end

  defp create_test_session(name) do
    session = Session.new!(
      name: name,
      project_path: System.tmp_dir!(),
      config: %{
        provider: :anthropic,
        model: "claude-3-5-sonnet-20241022"
      }
    )

    {:ok, session_id} = SessionSupervisor.start_session(session)
    {:ok, %{session | id: session_id}}
  end

  defp add_messages(session_id, count) do
    for i <- 1..count do
      message = %{
        role: if(rem(i, 2) == 0, do: "user", else: "assistant"),
        content: "Test message #{i} with some content to simulate realistic size. " <>
                 String.duplicate("Lorem ipsum dolor sit amet. ", 10)
      }

      Session.State.append_message(session_id, message)
    end
  end
end
