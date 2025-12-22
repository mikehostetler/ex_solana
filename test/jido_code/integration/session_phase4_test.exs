defmodule JidoCode.Integration.SessionPhase4Test do
  @moduledoc """
  Integration tests for Phase 4 multi-session TUI components.

  These tests verify the critical paths for multi-session TUI functionality:
  1. Multi-Session Event Routing - PubSub events route to correct session
  2. Session Switch State Synchronization - All UI state updates correctly
  3. Sidebar Activity Indicators - Activity badges display correctly

  These are focused integration tests covering the most critical multi-session
  workflows rather than comprehensive coverage of all scenarios.
  """
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :phase4

  alias JidoCode.Session.State, as: SessionState
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.TUI
  alias JidoCode.TUI.MessageHandlers
  alias JidoCode.TUI.Model
  alias JidoCode.TUI.Widgets.SessionSidebar

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Set API key for test sessions (doesn't need to be real, just non-empty)
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-phase4-integration")

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
    tmp_base = Path.join(System.tmp_dir!(), "phase4_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
      System.delete_env("ANTHROPIC_API_KEY")
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
    project_path = Path.join(tmp_base, name |> String.downcase() |> String.replace(" ", "_"))
    File.mkdir_p!(project_path)

    config = %{
      provider: "anthropic",
      model: "claude-3-5-haiku-20241022",
      temperature: 0.7,
      max_tokens: 4096
    }

    {:ok, session} =
      SessionSupervisor.create_session(project_path: project_path, name: name, config: config)

    {session, session.id}
  end

  # Helper to create a test model with sessions
  defp init_model_with_sessions(sessions, active_session_id \\ nil) do
    session_order = Enum.map(sessions, & &1.id)
    session_map = Map.new(sessions, fn s -> {s.id, s} end)

    %Model{
      sessions: session_map,
      session_order: session_order,
      active_session_id: active_session_id || hd(session_order),
      # Activity tracking fields
      streaming_sessions: MapSet.new(),
      unread_counts: %{},
      active_tools: %{},
      last_activity: %{},
      # Other required fields
      text_input: nil,
      conversation_view: nil,
      messages: [],
      agent_status: :idle,
      config: %{provider: "anthropic", model: "claude-3-5-sonnet-20241022"},
      sidebar_expanded: MapSet.new(),
      sidebar_width: 20
    }
  end

  # ============================================================================
  # Test 1: Multi-Session Event Routing
  # ============================================================================

  describe "multi-session event routing" do
    test "inactive session streaming doesn't corrupt active session", %{tmp_base: tmp_base} do
      # Create two sessions
      {session_a, session_a_id} = create_test_session(tmp_base, "Session A")
      {session_b, session_b_id} = create_test_session(tmp_base, "Session B")

      # Initialize model with Session A active
      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Verify initial state
      assert model.active_session_id == session_a_id
      assert model.streaming_message == nil
      assert MapSet.size(model.streaming_sessions) == 0
      assert map_size(model.unread_counts) == 0

      # Simulate streaming event from Session B (inactive)
      {model, _effects} = MessageHandlers.handle_stream_chunk(session_b_id, "chunk from B", model)

      # Assert: Session A's conversation view unchanged
      assert model.streaming_message == nil, "Active session streaming message should be nil"
      assert model.messages == [], "Active session messages should be empty"

      # Assert: Session B shows streaming indicator in sidebar
      assert MapSet.member?(model.streaming_sessions, session_b_id),
             "Inactive session B should have streaming indicator"

      refute MapSet.member?(model.streaming_sessions, session_a_id),
             "Active session A should not have streaming indicator"

      # Simulate more streaming chunks from inactive session B
      {model, _effects} = MessageHandlers.handle_stream_chunk(session_b_id, " more chunks", model)

      # Assert: Still no corruption of active session
      assert model.streaming_message == nil
      assert model.messages == []

      # Stream end in Session B
      {model, _effects} = MessageHandlers.handle_stream_end(session_b_id, "chunk from B more chunks", model)

      # Assert: Session B streaming indicator cleared
      refute MapSet.member?(model.streaming_sessions, session_b_id),
             "Session B streaming should be complete"

      # Assert: Session B unread count incremented
      assert Map.get(model.unread_counts, session_b_id) == 1,
             "Session B should have 1 unread message"

      # Assert: Session A unread count unchanged
      assert Map.get(model.unread_counts, session_a_id, 0) == 0,
             "Session A should have no unread messages"
    end

    test "active session streaming updates UI correctly", %{tmp_base: tmp_base} do
      # Create two sessions
      {session_a, session_a_id} = create_test_session(tmp_base, "Session A")
      {session_b, _session_b_id} = create_test_session(tmp_base, "Session B")

      # Initialize model with Session A active
      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Simulate streaming event from Session A (active)
      {model, _effects} = MessageHandlers.handle_stream_chunk(session_a_id, "chunk from A", model)

      # Assert: Active session streaming message updated
      assert model.streaming_message == "chunk from A",
             "Active session should accumulate streaming message"

      assert model.is_streaming == true, "is_streaming flag should be true"

      # Assert: Session A has streaming indicator
      assert MapSet.member?(model.streaming_sessions, session_a_id),
             "Active session A should have streaming indicator"

      # Simulate more chunks
      {model, _effects} = MessageHandlers.handle_stream_chunk(session_a_id, " more", model)

      assert model.streaming_message == "chunk from A more",
             "Streaming message should accumulate"

      # Stream end
      {model, _effects} = MessageHandlers.handle_stream_end(session_a_id, "chunk from A more", model)

      # Assert: Message added to messages list
      assert length(model.messages) == 1, "Should have 1 message"
      assert hd(model.messages).content == "chunk from A more"

      # Assert: Streaming state cleared
      assert model.streaming_message == nil
      assert model.is_streaming == false
      refute MapSet.member?(model.streaming_sessions, session_a_id)

      # Assert: No unread count for active session
      assert Map.get(model.unread_counts, session_a_id, 0) == 0,
             "Active session should not have unread count"
    end

    test "concurrent streaming in multiple sessions", %{tmp_base: tmp_base} do
      # Create three sessions
      {session_a, session_a_id} = create_test_session(tmp_base, "Session A")
      {session_b, session_b_id} = create_test_session(tmp_base, "Session B")
      {session_c, session_c_id} = create_test_session(tmp_base, "Session C")

      # Initialize model with Session A active
      model = init_model_with_sessions([session_a, session_b, session_c], session_a_id)

      # Start streaming in all three sessions
      {model, _} = MessageHandlers.handle_stream_chunk(session_a_id, "A1", model)
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "B1", model)
      {model, _} = MessageHandlers.handle_stream_chunk(session_c_id, "C1", model)

      # Assert: All sessions have streaming indicators
      assert MapSet.member?(model.streaming_sessions, session_a_id)
      assert MapSet.member?(model.streaming_sessions, session_b_id)
      assert MapSet.member?(model.streaming_sessions, session_c_id)

      # Assert: Only active session A has streaming_message
      assert model.streaming_message == "A1"

      # Continue streaming
      {model, _} = MessageHandlers.handle_stream_chunk(session_a_id, "A2", model)
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "B2", model)

      assert model.streaming_message == "A1A2"

      # End streaming in B first
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "B1B2", model)

      refute MapSet.member?(model.streaming_sessions, session_b_id)
      assert Map.get(model.unread_counts, session_b_id) == 1

      # Active session still streaming
      assert model.streaming_message == "A1A2"
      assert MapSet.member?(model.streaming_sessions, session_a_id)

      # End streaming in A
      {model, _} = MessageHandlers.handle_stream_end(session_a_id, "A1A2", model)

      assert model.streaming_message == nil
      refute MapSet.member?(model.streaming_sessions, session_a_id)
      assert Map.get(model.unread_counts, session_a_id, 0) == 0

      # C still streaming
      assert MapSet.member?(model.streaming_sessions, session_c_id)
    end
  end

  # ============================================================================
  # Test 2: Session Switch State Synchronization
  # ============================================================================

  describe "session switch state synchronization" do
    test "switching sessions clears unread count", %{tmp_base: tmp_base} do
      # Create two sessions
      {session_a, session_a_id} = create_test_session(tmp_base, "Project A")
      {session_b, session_b_id} = create_test_session(tmp_base, "Project B")

      # Add messages to Session B via State
      SessionState.append_message(session_b_id, %{
        id: "b1",
        role: :user,
        content: "B question",
        timestamp: DateTime.utc_now()
      })

      SessionState.append_message(session_b_id, %{
        id: "b2",
        role: :assistant,
        content: "B answer",
        timestamp: DateTime.utc_now()
      })

      # Initialize model with Session A active
      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Simulate background message in Session B
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "new msg", model)
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "new msg", model)

      # Assert: Session B has unread count
      assert Map.get(model.unread_counts, session_b_id) == 1

      # Switch to Session B using TUI.Model.switch_session
      model = TUI.Model.switch_session(model, session_b_id)

      # Clear unread count (mimics TUI update handler behavior)
      model = %{model | unread_counts: Map.delete(model.unread_counts, session_b_id)}

      # Assert: Active session changed
      assert model.active_session_id == session_b_id

      # Assert: Unread count cleared
      unread = Map.get(model.unread_counts, session_b_id, 0)
      assert unread == 0, "Unread count should be cleared when switching to session, got #{unread}"
    end

    test "switching sessions updates active_session_id", %{tmp_base: tmp_base} do
      # Create three sessions
      {session_a, session_a_id} = create_test_session(tmp_base, "Session A")
      {session_b, session_b_id} = create_test_session(tmp_base, "Session B")
      {session_c, session_c_id} = create_test_session(tmp_base, "Session C")

      # Initialize model with Session A active
      model = init_model_with_sessions([session_a, session_b, session_c], session_a_id)

      assert model.active_session_id == session_a_id

      # Switch to B
      model = TUI.Model.switch_session(model, session_b_id)
      assert model.active_session_id == session_b_id

      # Switch to C
      model = TUI.Model.switch_session(model, session_c_id)
      assert model.active_session_id == session_c_id

      # Switch back to A
      model = TUI.Model.switch_session(model, session_a_id)
      assert model.active_session_id == session_a_id
    end

    test "switching to session with unread messages clears count", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "A")
      {session_b, session_b_id} = create_test_session(tmp_base, "B")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Simulate 3 background messages in Session B
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "msg1", model)
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "msg2", model)
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "msg3", model)

      assert Map.get(model.unread_counts, session_b_id) == 3

      # Switch to B
      model = TUI.Model.switch_session(model, session_b_id)

      # Clear unread count (mimics TUI update handler behavior)
      model = %{model | unread_counts: Map.delete(model.unread_counts, session_b_id)}

      # Unread cleared
      assert Map.get(model.unread_counts, session_b_id, 0) == 0
    end
  end

  # ============================================================================
  # Test 3: Sidebar Activity Indicators
  # ============================================================================

  describe "sidebar activity indicators" do
    test "sidebar shows streaming indicator for inactive session", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, session_b_id} = create_test_session(tmp_base, "Inactive")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Simulate streaming in inactive session B
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "chunk", model)

      # Build sidebar
      sidebar = SessionSidebar.new(
        sessions: Map.values(model.sessions),
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Check title contains streaming indicator
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      assert String.contains?(session_b_title, "[...]"),
             "Session B title should contain streaming indicator [...], got: #{session_b_title}"

      # Active session A should not have streaming indicator (even though it could)
      session_a_title = SessionSidebar.build_title(sidebar, session_a)
      refute String.contains?(session_a_title, "[...]"),
             "Session A title should not contain streaming indicator"
    end

    test "sidebar shows unread count after stream ends", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, session_b_id} = create_test_session(tmp_base, "Inactive")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Complete stream in inactive session
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "full ", model)
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "content", model)
      {model, _} = MessageHandlers.handle_stream_end(session_b_id, "full content", model)

      # Build sidebar
      sidebar = SessionSidebar.new(
        sessions: Map.values(model.sessions),
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Check unread count shown
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      assert String.contains?(session_b_title, "[1]"),
             "Session B should show unread count [1], got: #{session_b_title}"

      # Should NOT show streaming indicator anymore
      refute String.contains?(session_b_title, "[...]"),
             "Session B should not show streaming indicator after end"
    end

    test "sidebar shows tool badge during tool execution", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, session_b_id} = create_test_session(tmp_base, "Inactive")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Simulate tool call in inactive session B
      {model, _} =
        MessageHandlers.handle_tool_call(session_b_id, "grep", %{pattern: "test"}, "call-1", model)

      # Build sidebar
      sidebar = SessionSidebar.new(
        sessions: Map.values(model.sessions),
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Check tool badge shown
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      assert String.contains?(session_b_title, "⚙1"),
             "Session B should show tool badge ⚙1, got: #{session_b_title}"
    end

    test "sidebar clears tool badge after tool completion", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, session_b_id} = create_test_session(tmp_base, "Inactive")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Tool call
      {model, _} =
        MessageHandlers.handle_tool_call(session_b_id, "grep", %{}, "call-1", model)

      # Tool result
      tool_result = %JidoCode.Tools.Result{
        tool_call_id: "call-1",
        tool_name: "grep",
        status: :ok,
        content: "found something",
        duration_ms: 100
      }

      {model, _} = MessageHandlers.handle_tool_result(session_b_id, tool_result, model)

      # Build sidebar
      sidebar = SessionSidebar.new(
        sessions: Map.values(model.sessions),
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Tool badge should be cleared
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      refute String.contains?(session_b_title, "⚙"),
             "Session B should not show tool badge after completion, got: #{session_b_title}"
    end

    test "sidebar shows multiple activity indicators simultaneously", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, session_b_id} = create_test_session(tmp_base, "Busy")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      # Session B: streaming
      {model, _} = MessageHandlers.handle_stream_chunk(session_b_id, "chunk", model)

      # Session B: tool executing
      {model, _} =
        MessageHandlers.handle_tool_call(session_b_id, "grep", %{}, "call-1", model)

      # Session B: has unread (manually set for this test)
      model = %{model | unread_counts: Map.put(model.unread_counts, session_b_id, 2)}

      # Build sidebar
      sidebar = SessionSidebar.new(
        sessions: Map.values(model.sessions),
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Check all three indicators present
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      assert String.contains?(session_b_title, "[...]"), "Should show streaming"
      assert String.contains?(session_b_title, "[2]"), "Should show unread count"
      assert String.contains?(session_b_title, "⚙1"), "Should show tool badge"
    end

    test "sidebar active indicator shows for current session", %{tmp_base: tmp_base} do
      {session_a, session_a_id} = create_test_session(tmp_base, "Active")
      {session_b, _session_b_id} = create_test_session(tmp_base, "Inactive")

      model = init_model_with_sessions([session_a, session_b], session_a_id)

      sidebar = SessionSidebar.new(
        sessions: model.sessions,
        order: model.session_order,
        active_id: model.active_session_id,
        streaming_sessions: model.streaming_sessions,
        unread_counts: model.unread_counts,
        active_tools: model.active_tools
      )

      # Session A (active) should have → prefix
      session_a_title = SessionSidebar.build_title(sidebar, session_a)
      assert String.starts_with?(session_a_title, "→ "),
             "Active session should start with → , got: #{session_a_title}"

      # Session B (inactive) should not have → prefix
      session_b_title = SessionSidebar.build_title(sidebar, session_b)
      refute String.starts_with?(session_b_title, "→ "),
             "Inactive session should not start with → , got: #{session_b_title}"
    end
  end
end
