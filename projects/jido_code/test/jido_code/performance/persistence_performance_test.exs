defmodule JidoCode.Performance.PersistenceTest do
  @moduledoc """
  Performance tests for persistence operations.

  Targets:
  - < 100ms for save operation
  - < 200ms for load/resume operation

  These tests profile save and load operations with varying
  conversation sizes to identify bottlenecks.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.Persistence
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @moduletag :performance
  @moduletag :llm
  @moduletag timeout: 300_000

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
    File.mkdir_p!(sessions_dir)

    :ok
  end

  describe "save operation performance" do
    @tag :profile
    test "save performance with empty conversation" do
      {:ok, session} = create_test_session("Empty Session")

      # Warmup
      Persistence.save(session.id)

      # Profile 100 save operations
      measurements = for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        time_us / 1000  # Convert to milliseconds
      end

      report_performance("Save (Empty Conversation)", measurements, 100)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    @tag :profile
    test "save performance with small conversation (10 messages)" do
      {:ok, session} = create_test_session("Small Session")
      add_messages(session.id, 10)

      # Warmup
      Persistence.save(session.id)

      # Profile 100 save operations
      measurements = for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        time_us / 1000
      end

      report_performance("Save (10 Messages)", measurements, 100)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    @tag :profile
    test "save performance with medium conversation (100 messages)" do
      {:ok, session} = create_test_session("Medium Session")
      add_messages(session.id, 100)

      # Warmup
      Persistence.save(session.id)

      # Profile 50 save operations
      measurements = for _ <- 1..50 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        time_us / 1000
      end

      report_performance("Save (100 Messages)", measurements, 100)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    @tag :profile
    test "save performance with large conversation (500 messages)" do
      {:ok, session} = create_test_session("Large Session")
      IO.puts("\nAdding 500 messages...")
      add_messages(session.id, 500)

      # Warmup
      Persistence.save(session.id)

      # Profile 20 save operations
      IO.puts("Profiling save operations...")
      measurements = for _ <- 1..20 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        time_us / 1000
      end

      report_performance("Save (500 Messages)", measurements, 100)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end

    @tag :profile
    test "save performance with maximum conversation (1000 messages)" do
      {:ok, session} = create_test_session("Max Session")
      IO.puts("\nAdding 1000 messages (max limit)...")
      add_messages(session.id, 1000)

      # Warmup
      Persistence.save(session.id)

      # Profile 10 save operations
      IO.puts("Profiling save operations...")
      measurements = for _ <- 1..10 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.save(session.id)
        end)

        time_us / 1000
      end

      report_performance("Save (1000 Messages - Max)", measurements, 100)

      # Cleanup
      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "load operation performance" do
    @tag :profile
    test "load performance with empty conversation" do
      {:ok, session} = create_test_session("Empty Session")
      Persistence.save(session.id)
      SessionSupervisor.stop_session(session.id)

      # Profile 100 load operations
      measurements = for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.load(session.id)
        end)

        time_us / 1000
      end

      report_performance("Load (Empty Conversation)", measurements, 200)
    end

    @tag :profile
    test "load performance with small conversation (10 messages)" do
      {:ok, session} = create_test_session("Small Session")
      add_messages(session.id, 10)
      Persistence.save(session.id)
      SessionSupervisor.stop_session(session.id)

      # Profile 100 load operations
      measurements = for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.load(session.id)
        end)

        time_us / 1000
      end

      report_performance("Load (10 Messages)", measurements, 200)
    end

    @tag :profile
    test "load performance with medium conversation (100 messages)" do
      {:ok, session} = create_test_session("Medium Session")
      add_messages(session.id, 100)
      Persistence.save(session.id)
      SessionSupervisor.stop_session(session.id)

      # Profile 50 load operations
      measurements = for _ <- 1..50 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.load(session.id)
        end)

        time_us / 1000
      end

      report_performance("Load (100 Messages)", measurements, 200)
    end

    @tag :profile
    test "load performance with large conversation (500 messages)" do
      {:ok, session} = create_test_session("Large Session")
      IO.puts("\nAdding 500 messages...")
      add_messages(session.id, 500)
      Persistence.save(session.id)
      SessionSupervisor.stop_session(session.id)

      # Profile 20 load operations
      IO.puts("Profiling load operations...")
      measurements = for _ <- 1..20 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.load(session.id)
        end)

        time_us / 1000
      end

      report_performance("Load (500 Messages)", measurements, 200)
    end

    @tag :profile
    test "load performance with maximum conversation (1000 messages)" do
      {:ok, session} = create_test_session("Max Session")
      IO.puts("\nAdding 1000 messages (max limit)...")
      add_messages(session.id, 1000)
      Persistence.save(session.id)
      SessionSupervisor.stop_session(session.id)

      # Profile 10 load operations
      IO.puts("Profiling load operations...")
      measurements = for _ <- 1..10 do
        {time_us, _result} = :timer.tc(fn ->
          Persistence.load(session.id)
        end)

        time_us / 1000
      end

      report_performance("Load (1000 Messages - Max)", measurements, 200)
    end
  end

  describe "end-to-end persistence performance" do
    @tag :profile
    test "save-close-resume cycle with realistic session" do
      {:ok, session} = create_test_session("Realistic Session")
      add_messages(session.id, 50)  # Typical conversation size

      # Profile the complete cycle 20 times
      measurements = for _ <- 1..20 do
        {time_us, _result} = :timer.tc(fn ->
          # Save
          {:ok, _} = Persistence.save(session.id)

          # Close
          :ok = SessionSupervisor.stop_session(session.id)

          # Resume
          {:ok, resumed_session} = Persistence.resume(session.id)

          resumed_session
        end)

        time_us / 1000
      end

      avg_ms = Enum.sum(measurements) / length(measurements)
      p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))

      IO.puts("\n=== Save-Close-Resume Cycle (50 Messages) ===")
      IO.puts("Samples: #{length(measurements)}")
      IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
      IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
      IO.puts("Target:  < 300ms (save < 100ms + load < 200ms)")
      IO.puts("Status:  #{if p95_ms < 300, do: "✓ PASS", else: "✗ FAIL"}")

      assert p95_ms < 300
    end
  end

  # Helper functions

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
        content: "Test message #{i}. " <>
                 String.duplicate("Lorem ipsum dolor sit amet, consectetur adipiscing elit. ", 5)
      }

      Session.State.append_message(session_id, message)
    end
  end

  defp report_performance(label, measurements, target_ms) do
    avg_ms = Enum.sum(measurements) / length(measurements)
    median_ms = Enum.sort(measurements) |> Enum.at(div(length(measurements), 2))
    p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))
    max_ms = Enum.max(measurements)

    IO.puts("\n=== #{label} ===")
    IO.puts("Samples: #{length(measurements)}")
    IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
    IO.puts("Median:  #{Float.round(median_ms, 2)}ms")
    IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
    IO.puts("Max:     #{Float.round(max_ms, 2)}ms")
    IO.puts("Target:  < #{target_ms}ms")
    IO.puts("Status:  #{if p95_ms < target_ms, do: "✓ PASS", else: "✗ FAIL"}")

    assert p95_ms < target_ms,
           "P95 latency (#{Float.round(p95_ms, 2)}ms) exceeds #{target_ms}ms target"
  end
end
