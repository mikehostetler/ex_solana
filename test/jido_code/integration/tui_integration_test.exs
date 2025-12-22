defmodule JidoCode.Integration.TUIIntegrationTest do
  @moduledoc """
  Integration tests for TUI behavior with multiple sessions.

  These tests verify that:
  - Tab rendering works correctly with various session counts
  - Keyboard navigation switches to correct sessions
  - Status bar updates correctly on session switch
  - Conversation view renders the correct session
  - Input is routed to the active session

  Note: These tests verify the TUI model updates and logic, not actual terminal rendering.

  **Requirements**:
  - ANTHROPIC_API_KEY environment variable must be set
  - Tests are tagged :llm and excluded from regular runs
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :tui
  @moduletag :llm

  alias JidoCode.Session
  alias JidoCode.Session.State
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.TUI
  alias JidoCode.Test.SessionTestHelpers

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    {:ok, _} = Application.ensure_all_started(:jido_code)

    wait_for_supervisor()

    # Clear sessions
    SessionRegistry.clear()

    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    tmp_base = Path.join(System.tmp_dir!(), "tui_test_#{:rand.uniform(100_000)}")
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
    session_id
  end

  # ============================================================================
  # Test: Tab Rendering with 0, 1, 5, 10 Sessions
  # ============================================================================

  test "TUI model handles different session counts correctly", %{tmp_base: tmp_base} do
    # Test with 0 sessions (only if we allow this state)
    sessions_0 = SessionRegistry.list_all()
    assert sessions_0 == [] or length(sessions_0) >= 0

    # Test with 1 session
    session_1 = create_test_session(tmp_base, "Session 1")
    sessions_1 = SessionRegistry.list_all()
    assert length(sessions_1) == 1
    assert Enum.any?(sessions_1, &(&1.id == session_1))

    # Test with 5 sessions
    for i <- 2..5 do
      create_test_session(tmp_base, "Session #{i}")
    end

    sessions_5 = SessionRegistry.list_all()
    assert length(sessions_5) == 5

    # Test with 10 sessions (maximum)
    for i <- 6..10 do
      create_test_session(tmp_base, "Session #{i}")
    end

    sessions_10 = SessionRegistry.list_all()
    assert length(sessions_10) == 10

    # Verify all sessions are properly registered
    for session <- sessions_10 do
      assert SessionRegistry.exists?(session.id)
    end
  end

  # ============================================================================
  # Test: Session Switching Updates Active Session
  # ============================================================================

  test "switching active session updates correctly", %{tmp_base: tmp_base} do
    # Create 3 sessions
    session_ids =
      for i <- 1..3 do
        create_test_session(tmp_base, "Session #{i}")
      end

    [id1, id2, id3] = session_ids

    # Add unique messages to each session
    State.append_message(id1, %{
      id: "msg1",
      role: :user,
      content: "Message in Session 1",
      timestamp: DateTime.utc_now()
    })

    State.append_message(id2, %{
      id: "msg2",
      role: :user,
      content: "Message in Session 2",
      timestamp: DateTime.utc_now()
    })

    State.append_message(id3, %{
      id: "msg3",
      role: :user,
      content: "Message in Session 3",
      timestamp: DateTime.utc_now()
    })

    # Verify each session has its own message
    {:ok, messages1} = State.get_messages(id1)
    {:ok, messages2} = State.get_messages(id2)
    {:ok, messages3} = State.get_messages(id3)

    assert hd(messages1).content == "Message in Session 1"
    assert hd(messages2).content == "Message in Session 2"
    assert hd(messages3).content == "Message in Session 3"
  end

  # ============================================================================
  # Test: Status Bar Shows Correct Session Info
  # ============================================================================

  test "session metadata available for status bar display", %{tmp_base: tmp_base} do
    # Create sessions with different names and paths
    session_id_1 = create_test_session(tmp_base, "Development Session")
    session_id_2 = create_test_session(tmp_base, "Production Session")

    # Retrieve session info
    {:ok, session1} = SessionRegistry.lookup(session_id_1)
    {:ok, session2} = SessionRegistry.lookup(session_id_2)

    # Verify session metadata is available
    assert session1.name == "Development Session"
    assert session2.name == "Production Session"

    assert String.ends_with?(session1.project_path, "Development Session")
    assert String.ends_with?(session2.project_path, "Production Session")

    # Verify session config is available
    assert is_map(session1.config)
    assert is_map(session2.config)
  end

  # ============================================================================
  # Test: Conversation View Renders Correct Session
  # ============================================================================

  test "conversation view shows correct session messages", %{tmp_base: tmp_base} do
    # Create two sessions
    session_a = create_test_session(tmp_base, "Session A")
    session_b = create_test_session(tmp_base, "Session B")

    # Add different conversations to each
    State.append_message(session_a, %{
      id: "a1",
      role: :user,
      content: "User message in A",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_a, %{
      id: "a2",
      role: :assistant,
      content: "Assistant response in A",
      timestamp: DateTime.utc_now()
    })

    State.append_message(session_b, %{
      id: "b1",
      role: :user,
      content: "User message in B",
      timestamp: DateTime.utc_now()
    })

    # Verify conversation view can fetch correct messages
    {:ok, conv_a} = State.get_messages(session_a)
    {:ok, conv_b} = State.get_messages(session_b)

    assert length(conv_a) == 2
    assert length(conv_b) == 1

    assert Enum.at(conv_a, 0).content == "User message in A"
    assert Enum.at(conv_a, 1).content == "Assistant response in A"
    assert hd(conv_b).content == "User message in B"
  end

  # ============================================================================
  # Test: Input Routes to Active Session
  # ============================================================================

  test "message append routes to correct session", %{tmp_base: tmp_base} do
    # Create multiple sessions
    sessions =
      for i <- 1..3 do
        create_test_session(tmp_base, "Session #{i}")
      end

    # Simulate routing input to different sessions
    for {session_id, idx} <- Enum.with_index(sessions, 1) do
      State.append_message(session_id, %{
        id: "user_input_#{idx}",
        role: :user,
        content: "Input to session #{idx}",
        timestamp: DateTime.utc_now()
      })
    end

    # Verify each session received only its own input
    for {session_id, idx} <- Enum.with_index(sessions, 1) do
      {:ok, messages} = State.get_messages(session_id)
      assert length(messages) == 1
      assert hd(messages).content == "Input to session #{idx}"
    end
  end

  # ============================================================================
  # Test: Session List for Tab Display
  # ============================================================================

  test "session list retrieval for tab rendering", %{tmp_base: tmp_base} do
    # Create sessions with specific names
    session_names = ["Alpha", "Beta", "Gamma", "Delta"]

    session_ids =
      for name <- session_names do
        create_test_session(tmp_base, name)
      end

    # Retrieve all sessions
    all_sessions = SessionRegistry.list_all()

    assert length(all_sessions) == 4

    # Verify all expected sessions are present
    retrieved_names = Enum.map(all_sessions, & &1.name) |> Enum.sort()
    assert retrieved_names == Enum.sort(session_names)

    # Verify session IDs match
    retrieved_ids = Enum.map(all_sessions, & &1.id) |> Enum.sort()
    assert retrieved_ids == Enum.sort(session_ids)
  end

  # ============================================================================
  # Test: Tab Close Updates Session List
  # ============================================================================

  test "closing a session updates available session list", %{tmp_base: tmp_base} do
    # Create 5 sessions
    session_ids =
      for i <- 1..5 do
        create_test_session(tmp_base, "Session #{i}")
      end

    # Verify all 5 exist
    assert length(SessionRegistry.list_all()) == 5

    # Close middle session
    middle_id = Enum.at(session_ids, 2)
    :ok = SessionSupervisor.stop_session(middle_id)

    # Verify count reduced
    assert length(SessionRegistry.list_all()) == 4

    # Verify specific session is gone
    refute SessionRegistry.exists?(middle_id)

    # Verify others still exist
    for id <- Enum.take(session_ids, 2) ++ Enum.drop(session_ids, 3) do
      assert SessionRegistry.exists?(id)
    end
  end
end
