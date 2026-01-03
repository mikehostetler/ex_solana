defmodule JidoCode.Performance.SessionSwitchingTest do
  @moduledoc """
  Performance tests for session switching operations.

  Target: < 50ms for session switch operation

  These tests profile the actual latency of switching between sessions
  and help identify bottlenecks in the session management system.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.TUI.Model

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

    :ok
  end

  describe "session switching latency" do
    @tag :profile
    test "switching between 2 sessions with empty conversations" do
      # Create 2 sessions
      {:ok, session1} = create_test_session("Session 1")
      {:ok, session2} = create_test_session("Session 2")

      # Warmup: switch once to ensure processes are initialized
      Model.switch_session(%Model{active_session_id: session1.id}, session2.id)

      # Profile 100 switches
      measurements =
        for _ <- 1..100 do
          {time_us, _result} =
            :timer.tc(fn ->
              Model.switch_session(%Model{active_session_id: session1.id}, session2.id)
            end)

          # Convert to milliseconds
          time_us / 1000
        end

      avg_ms = Enum.sum(measurements) / length(measurements)
      median_ms = Enum.sort(measurements) |> Enum.at(div(length(measurements), 2))
      p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))
      max_ms = Enum.max(measurements)

      IO.puts("\n=== Session Switching Performance (Empty Conversations) ===")
      IO.puts("Samples: #{length(measurements)}")
      IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
      IO.puts("Median:  #{Float.round(median_ms, 2)}ms")
      IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
      IO.puts("Max:     #{Float.round(max_ms, 2)}ms")
      IO.puts("Target:  < 50ms")
      IO.puts("Status:  #{if p95_ms < 50, do: "✓ PASS", else: "✗ FAIL"}")

      # Assert P95 latency is under target
      assert p95_ms < 50, "P95 latency (#{Float.round(p95_ms, 2)}ms) exceeds 50ms target"
    end

    @tag :profile
    test "switching between sessions with small conversations (10 messages each)" do
      # Create 2 sessions with 10 messages each
      {:ok, session1} = create_test_session("Session 1")
      {:ok, session2} = create_test_session("Session 2")

      # Add 10 messages to each session
      add_messages(session1.id, 10)
      add_messages(session2.id, 10)

      # Profile 100 switches
      measurements =
        for _ <- 1..100 do
          {time_us, _result} =
            :timer.tc(fn ->
              Model.switch_session(%Model{active_session_id: session1.id}, session2.id)
            end)

          time_us / 1000
        end

      avg_ms = Enum.sum(measurements) / length(measurements)
      p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))

      IO.puts("\n=== Session Switching Performance (10 Messages Each) ===")
      IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
      IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
      IO.puts("Target:  < 50ms")
      IO.puts("Status:  #{if p95_ms < 50, do: "✓ PASS", else: "✗ FAIL"}")

      assert p95_ms < 50
    end

    @tag :profile
    test "switching between sessions with large conversations (500 messages each)" do
      # Create 2 sessions with 500 messages each
      {:ok, session1} = create_test_session("Session 1")
      {:ok, session2} = create_test_session("Session 2")

      IO.puts("\nAdding 500 messages to each session...")
      add_messages(session1.id, 500)
      add_messages(session2.id, 500)
      IO.puts("Messages added. Starting profiling...")

      # Profile 100 switches
      measurements =
        for _ <- 1..100 do
          {time_us, _result} =
            :timer.tc(fn ->
              Model.switch_session(%Model{active_session_id: session1.id}, session2.id)
            end)

          time_us / 1000
        end

      avg_ms = Enum.sum(measurements) / length(measurements)
      p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))

      IO.puts("\n=== Session Switching Performance (500 Messages Each) ===")
      IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
      IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
      IO.puts("Target:  < 50ms")
      IO.puts("Status:  #{if p95_ms < 50, do: "✓ PASS", else: "✗ FAIL"}")

      assert p95_ms < 50
    end

    @tag :profile
    test "switching between 10 sessions (worst case)" do
      # Create 10 sessions
      sessions =
        for i <- 1..10 do
          {:ok, session} = create_test_session("Session #{i}")
          # 50 messages each
          add_messages(session.id, 50)
          session
        end

      session_ids = Enum.map(sessions, & &1.id)

      # Profile switches across all 10 sessions
      measurements =
        for _ <- 1..100 do
          from_id = Enum.random(session_ids)
          to_id = Enum.random(session_ids -- [from_id])

          {time_us, _result} =
            :timer.tc(fn ->
              Model.switch_session(%Model{active_session_id: from_id}, to_id)
            end)

          time_us / 1000
        end

      avg_ms = Enum.sum(measurements) / length(measurements)
      p95_ms = Enum.sort(measurements) |> Enum.at(round(length(measurements) * 0.95))

      IO.puts("\n=== Session Switching Performance (10 Sessions, 50 Messages Each) ===")
      IO.puts("Average: #{Float.round(avg_ms, 2)}ms")
      IO.puts("P95:     #{Float.round(p95_ms, 2)}ms")
      IO.puts("Target:  < 50ms")
      IO.puts("Status:  #{if p95_ms < 50, do: "✓ PASS", else: "✗ FAIL"}")

      assert p95_ms < 50
    end
  end

  # Helper functions

  defp create_test_session(name) do
    session =
      Session.new!(
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
        content: "Test message #{i} with some content to simulate realistic size"
      }

      Session.State.append_message(session_id, message)
    end
  end
end
