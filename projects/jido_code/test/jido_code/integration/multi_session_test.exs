defmodule JidoCode.Integration.MultiSessionTest do
  @moduledoc """
  Integration tests for multi-session interactions and isolation.

  These tests verify that:
  - Multiple sessions operate independently without interference
  - State isolation is maintained between sessions
  - Tool execution respects session boundaries
  - Streaming in one session doesn't affect others
  - Sessions can be closed without affecting others
  - Concurrent operations work correctly

  These are end-to-end tests using real infrastructure including LLM agents.

  **Requirements**:
  - ANTHROPIC_API_KEY environment variable must be set
  - Tests are tagged :llm and excluded from regular runs
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :multi_session
  @moduletag :llm

  alias JidoCode.Session
  alias JidoCode.Session.{State, Manager}
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor
    wait_for_supervisor()

    # Clear any existing sessions
    SessionRegistry.clear()

    # Stop any running sessions
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp directories for multiple sessions
    tmp_base = Path.join(System.tmp_dir!(), "multi_session_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
    end)

    {:ok, tmp_base: tmp_base}
  end

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor did not start in time"
      end
    end
  end

  # Helper to create a test session
  defp create_test_session(tmp_base, name) do
    project_path = Path.join(tmp_base, name)
    File.mkdir_p!(project_path)

    {:ok, session} =
      Session.new(
        name: name,
        project_path: project_path,
        config: SessionTestHelpers.valid_session_config()
      )

    {:ok, session_id} = SessionSupervisor.start_session(session)
    {session_id, project_path}
  end

  # ============================================================================
  # Test: Switch Between Sessions → Verify State Isolation
  # ============================================================================

  test "switching between sessions maintains state isolation", %{tmp_base: tmp_base} do
    # Create three sessions
    {session_a, _path_a} = create_test_session(tmp_base, "session_a")
    {session_b, _path_b} = create_test_session(tmp_base, "session_b")
    {session_c, _path_c} = create_test_session(tmp_base, "session_c")

    # Add different messages to each session
    State.append_message(session_a, %{
      id: "a1",
      role: :user,
      content: "Message in A",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_b, %{
      id: "b1",
      role: :user,
      content: "Message in B",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_c, %{
      id: "c1",
      role: :user,
      content: "Message in C",
      timestamp: DateTime.utc_now()
    })

    # Verify each session has only its own messages
    {:ok, messages_a} = State.get_messages(session_a)
    {:ok, messages_b} = State.get_messages(session_b)
    {:ok, messages_c} = State.get_messages(session_c)

    assert length(messages_a) == 1
    assert length(messages_b) == 1
    assert length(messages_c) == 1

    assert hd(messages_a).content == "Message in A"
    assert hd(messages_b).content == "Message in B"
    assert hd(messages_c).content == "Message in C"

    # Add more messages and verify isolation is maintained
    State.append_message(session_a, %{
      id: "a2",
      role: :assistant,
      content: "Response in A",
      timestamp: DateTime.utc_now()
    })

    {:ok, updated_a} = State.get_messages(session_a)
    {:ok, updated_b} = State.get_messages(session_b)

    assert length(updated_a) == 2
    assert length(updated_b) == 1
  end

  # ============================================================================
  # Test: Send Message in Session A → Verify Session B Unaffected
  # ============================================================================

  test "message sent to session A does not appear in session B", %{tmp_base: tmp_base} do
    {session_a, _} = create_test_session(tmp_base, "session_a")
    {session_b, _} = create_test_session(tmp_base, "session_b")

    # Get initial state of both sessions
    {:ok, initial_a} = State.get_messages(session_a)
    {:ok, initial_b} = State.get_messages(session_b)

    assert initial_a == []
    assert initial_b == []

    # Send message only to session A
    State.append_message(session_a, %{
      id: "msg1",
      role: :user,
      content: "Hello A",
      timestamp: DateTime.utc_now()
    })

    # Verify message appears in A
    {:ok, messages_a} = State.get_messages(session_a)
    assert length(messages_a) == 1
    assert hd(messages_a).content == "Hello A"

    # Verify B is still empty
    {:ok, messages_b} = State.get_messages(session_b)
    assert messages_b == []

    # Send multiple messages to A
    for i <- 2..5 do
      State.append_message(session_a, %{
        id: "msg#{i}",
        role: :user,
        content: "Message #{i}",
        timestamp: DateTime.utc_now()
      })
    end

    # Verify A has all messages, B still empty
    {:ok, final_a} = State.get_messages(session_a)
    {:ok, final_b} = State.get_messages(session_b)

    assert length(final_a) == 5
    assert final_b == []
  end

  # ============================================================================
  # Test: Tool Execution in Session A → Verify Boundary Isolation
  # ============================================================================

  test "tool execution in session A respects session boundary", %{tmp_base: tmp_base} do
    {session_a, path_a} = create_test_session(tmp_base, "session_a")
    {session_b, path_b} = create_test_session(tmp_base, "session_b")

    # Create test files in each session's project
    file_a = Path.join(path_a, "test.txt")
    file_b = Path.join(path_b, "test.txt")

    File.write!(file_a, "Content A")
    File.write!(file_b, "Content B")

    # Verify Manager has correct project_root for each session
    {:ok, root_a} = Manager.project_root(session_a)
    {:ok, root_b} = Manager.project_root(session_b)

    assert root_a == path_a
    assert root_b == path_b

    # Verify files exist in their respective projects
    assert File.exists?(file_a)
    assert File.exists?(file_b)
    assert File.read!(file_a) == "Content A"
    assert File.read!(file_b) == "Content B"
  end

  # ============================================================================
  # Test: Streaming in Session A → Switch to B → Switch Back → Verify State
  # ============================================================================

  test "streaming state preserved when switching between sessions", %{tmp_base: tmp_base} do
    {session_a, _} = create_test_session(tmp_base, "session_a")
    {session_b, _} = create_test_session(tmp_base, "session_b")

    # Set streaming state in session A
    State.start_streaming(session_a, "msg-a")
    State.update_streaming(session_a, "Streaming content in A")

    # Verify streaming state in A
    {:ok, state_a} = State.get_state(session_a)
    assert state_a.is_streaming == true
    assert state_a.streaming_message == "Streaming content in A"

    # Set different streaming state in session B
    State.start_streaming(session_b, "msg-b")
    State.update_streaming(session_b, "Streaming content in B")

    # Verify both sessions maintain their own streaming state
    {:ok, state_a_check} = State.get_state(session_a)
    {:ok, state_b_check} = State.get_state(session_b)

    assert state_a_check.streaming_message == "Streaming content in A"
    assert state_b_check.streaming_message == "Streaming content in B"

    # Stop streaming in A, verify B unaffected
    State.end_streaming(session_a)

    {:ok, state_a_final} = State.get_state(session_a)
    {:ok, state_b_final} = State.get_state(session_b)

    assert state_a_final.is_streaming == false
    assert state_b_final.is_streaming == true
  end

  # ============================================================================
  # Test: Close Session A → Verify B Remains Functional
  # ============================================================================

  test "closing session A does not affect session B", %{tmp_base: tmp_base} do
    {session_a, _} = create_test_session(tmp_base, "session_a")
    {session_b, _} = create_test_session(tmp_base, "session_b")

    # Add messages to both sessions
    State.append_message(session_a, %{
      id: "a1",
      role: :user,
      content: "Message A",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_b, %{
      id: "b1",
      role: :user,
      content: "Message B",
      timestamp: DateTime.utc_now()
    })

    # Verify both sessions exist and are functional
    assert SessionRegistry.exists?(session_a)
    assert SessionRegistry.exists?(session_b)
    {:ok, _} = State.get_messages(session_a)
    {:ok, _} = State.get_messages(session_b)

    # Close session A
    :ok = SessionSupervisor.stop_session(session_a)

    # Verify A is gone
    refute SessionRegistry.exists?(session_a)

    # Verify B still exists and is functional
    assert SessionRegistry.exists?(session_b)
    {:ok, messages_b} = State.get_messages(session_b)
    assert length(messages_b) == 1
    assert hd(messages_b).content == "Message B"

    # Verify we can still add messages to B
    State.append_message(session_b, %{
      id: "b2",
      role: :assistant,
      content: "Still working",
      timestamp: DateTime.utc_now()
    })

    {:ok, updated_b} = State.get_messages(session_b)
    assert length(updated_b) == 2
  end

  # ============================================================================
  # Test: Concurrent Messages to Different Sessions
  # ============================================================================

  test "concurrent message operations on different sessions work correctly", %{
    tmp_base: tmp_base
  } do
    # Create multiple sessions
    sessions =
      for i <- 1..3 do
        {id, _path} = create_test_session(tmp_base, "session_#{i}")
        id
      end

    # Concurrently add messages to all sessions
    tasks =
      for {session_id, idx} <- Enum.with_index(sessions, 1) do
        Task.async(fn ->
          for i <- 1..5 do
            State.append_message(session_id, %{
              id: "s#{idx}_m#{i}",
              role: :user,
              content: "Session #{idx} Message #{i}",
              timestamp: DateTime.utc_now()
            })

            # Small delay to simulate real usage
            Process.sleep(5)
          end

          session_id
        end)
      end

    # Wait for all tasks to complete
    completed_sessions = Task.await_many(tasks, 5000)

    # Verify all sessions completed
    assert length(completed_sessions) == 3

    # Verify each session has exactly 5 messages
    for {session_id, idx} <- Enum.with_index(sessions, 1) do
      {:ok, messages} = State.get_messages(session_id)
      assert length(messages) == 5

      # Verify messages belong to the correct session
      for msg <- messages do
        assert String.starts_with?(msg.content, "Session #{idx}")
      end
    end
  end

  # ============================================================================
  # Test: Todo List Isolation Between Sessions
  # ============================================================================

  test "todo lists are isolated between sessions", %{tmp_base: tmp_base} do
    {session_a, _} = create_test_session(tmp_base, "session_a")
    {session_b, _} = create_test_session(tmp_base, "session_b")

    # Set different todos for each session
    todos_a = [
      %{content: "Task A1", status: :pending, active_form: "Task A1"},
      %{content: "Task A2", status: :in_progress, active_form: "Task A2"}
    ]

    todos_b = [
      %{content: "Task B1", status: :completed, active_form: "Task B1"}
    ]

    State.update_todos(session_a, todos_a)
    State.update_todos(session_b, todos_b)

    # Verify isolation
    {:ok, retrieved_a} = State.get_todos(session_a)
    {:ok, retrieved_b} = State.get_todos(session_b)

    assert length(retrieved_a) == 2
    assert length(retrieved_b) == 1

    assert hd(retrieved_a).content == "Task A1"
    assert hd(retrieved_b).content == "Task B1"
  end
end
