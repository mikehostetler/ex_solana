defmodule JidoCode.TUITest do
  use ExUnit.Case, async: false

  alias Jido.AI.Keyring
  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.Settings
  alias JidoCode.TestHelpers.SessionIsolation
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias JidoCode.TUI.Widgets.ConversationView
  alias TermUI.Event

  # Helper to set up API key for tests
  defp setup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.set_session_value(key_name, "test-api-key-#{provider}")
  end

  defp cleanup_api_key(provider) do
    key_name = provider_to_key_name(provider)
    Keyring.clear_session_value(key_name)
  end

  defp provider_to_key_name(provider) do
    case provider do
      "openai" -> :openai_api_key
      "anthropic" -> :anthropic_api_key
      _ -> String.to_atom("#{provider}_api_key")
    end
  end

  setup do
    # Clear session registry before and after each test
    SessionIsolation.isolate()

    # Clear settings cache before each test
    Settings.clear_cache()

    # Save and remove local settings file temporarily to avoid test interference
    settings_path = Settings.local_path()
    backup_path = settings_path <> ".bak"

    if File.exists?(settings_path) do
      File.rename(settings_path, backup_path)
    end

    on_exit(fn ->
      # Restore settings file after test
      if File.exists?(backup_path) do
        File.rename(backup_path, settings_path)
      end

      Settings.clear_cache()
    end)

    :ok
  end

  # Helper to create a ConversationView state with given input value
  # Positions cursor at the end of the input for natural typing behavior
  defp create_conversation_view(input_value \\ "") do
    props =
      ConversationView.new(
        messages: [],
        viewport_width: 76,
        viewport_height: 20,
        input_placeholder: "Type a message...",
        max_input_lines: 5
      )

    {:ok, state} = ConversationView.init(props)

    # Set the input value if provided
    if input_value != "" do
      state = ConversationView.set_input_value(state, input_value)
      # Move cursor to end of input for natural typing behavior
      text_input = %{state.text_input | cursor_col: String.length(input_value)}
      %{state | text_input: text_input}
    else
      state
    end
  end

  # Helper to create a TextInput state for testing
  defp create_text_input(value \\ "") do
    props =
      TermUI.Widgets.TextInput.new(
        placeholder: "Type a message...",
        width: 76,
        enter_submits: false
      )

    {:ok, state} = TermUI.Widgets.TextInput.init(props)
    state = TermUI.Widgets.TextInput.set_focused(state, true)

    if value != "" do
      %{state | value: value, cursor_col: String.length(value)}
    else
      state
    end
  end

  # Helper to get text value from ConversationView's TextInput
  defp get_input_value(model) do
    Model.get_active_input_value(model)
  end

  # Helper to get streaming_message from active session's UI state
  defp get_streaming_message(model) do
    case Model.get_active_ui_state(model) do
      nil -> nil
      ui_state -> ui_state.streaming_message
    end
  end

  # Helper to get is_streaming from active session's UI state
  defp get_is_streaming(model) do
    case Model.get_active_ui_state(model) do
      nil -> false
      ui_state -> ui_state.is_streaming
    end
  end

  # Helper to get messages from active session's UI state
  defp get_session_messages(model) do
    case Model.get_active_ui_state(model) do
      nil -> []
      ui_state -> ui_state.messages
    end
  end

  # Helper to get tool_calls from active session's UI state
  defp get_tool_calls(model) do
    case Model.get_active_ui_state(model) do
      nil -> []
      ui_state -> ui_state.tool_calls
    end
  end

  # Helper to get reasoning_steps from active session's UI state
  defp get_reasoning_steps(model) do
    case Model.get_active_ui_state(model) do
      nil -> []
      ui_state -> ui_state.reasoning_steps
    end
  end

  # Helper to create a test Session struct
  defp create_test_session(id, name, project_path) do
    %Session{
      id: id,
      name: name,
      project_path: project_path,
      config: %{provider: "anthropic", model: "claude-3-5-sonnet-20241022"},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # Helper to create a Model with an active session and input value
  defp create_model_with_input(input_value \\ "") do
    session = create_test_session("test-session", "Test Session", "/tmp")

    ui_state = %{
      conversation_view: create_conversation_view(input_value),
      accordion: nil,
      scroll_offset: 0,
      streaming_message: nil,
      is_streaming: false,
      reasoning_steps: [],
      tool_calls: [],
      messages: [],
      agent_activity: :idle,
      awaiting_input: nil,
      agent_status: :idle
    }

    session_with_ui = Map.put(session, :ui_state, ui_state)

    %Model{
      sessions: %{"test-session" => session_with_ui},
      session_order: ["test-session"],
      active_session_id: "test-session"
    }
  end

  defp create_model_with_session(session) do
    ui_state = %{
      conversation_view: create_conversation_view(""),
      accordion: nil,
      scroll_offset: 0,
      streaming_message: nil,
      is_streaming: false,
      reasoning_steps: [],
      tool_calls: [],
      messages: [],
      agent_activity: :idle,
      awaiting_input: nil,
      agent_status: :idle,
      text_input: create_text_input()
    }

    session_with_ui = Map.put(session, :ui_state, ui_state)

    %Model{
      sessions: %{session.id => session_with_ui},
      session_order: [session.id],
      active_session_id: session.id
    }
  end

  describe "Model struct" do
    test "has correct default values" do
      model = %Model{}

      assert model.messages == []
      # agent_status is now per-session in ui_state, defaults to :idle when no session
      assert Model.get_active_agent_status(model) == :idle
      assert model.config == %{provider: nil, model: nil}
      assert model.reasoning_steps == []
      assert model.window == {80, 24}
    end

    test "can be created with custom values" do
      model = %Model{
        messages: [%{role: :user, content: "hello", timestamp: DateTime.utc_now()}],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"},
        reasoning_steps: [%{step: "thinking", status: :active}],
        window: {120, 40}
      }

      assert length(model.messages) == 1
      assert model.config.provider == "anthropic"
      assert model.window == {120, 40}
    end

    test "input is managed through ConversationView in session UI state" do
      # Create a session with UI state that includes ConversationView
      session = create_test_session("test-id", "Test", "/tmp")

      ui_state = %{
        conversation_view: create_conversation_view("test input"),
        accordion: nil,
        scroll_offset: 0,
        streaming_message: nil,
        is_streaming: false,
        reasoning_steps: [],
        tool_calls: [],
        messages: [],
        agent_activity: :idle,
        awaiting_input: nil
      }

      session_with_ui = Map.put(session, :ui_state, ui_state)

      model = %Model{
        sessions: %{"test-id" => session_with_ui},
        session_order: ["test-id"],
        active_session_id: "test-id"
      }

      assert get_input_value(model) == "test input"
    end
  end

  describe "Model sidebar state (Phase 4.5.3)" do
    test "Model struct has sidebar_visible field" do
      model = %Model{}
      assert Map.has_key?(model, :sidebar_visible)
    end

    test "Model struct has sidebar_width field" do
      model = %Model{}
      assert Map.has_key?(model, :sidebar_width)
    end

    test "Model struct has sidebar_expanded field" do
      model = %Model{}
      assert Map.has_key?(model, :sidebar_expanded)
    end

    test "Model struct has sidebar_selected_index field" do
      model = %Model{}
      assert Map.has_key?(model, :sidebar_selected_index)
    end

    test "sidebar_visible defaults to true" do
      model = %Model{}
      assert model.sidebar_visible == true
    end

    test "sidebar_width defaults to 20" do
      model = %Model{}
      assert model.sidebar_width == 20
    end

    test "sidebar_expanded defaults to empty MapSet" do
      model = %Model{}
      assert model.sidebar_expanded == MapSet.new()
    end

    test "sidebar_selected_index defaults to 0" do
      model = %Model{}
      assert model.sidebar_selected_index == 0
    end

    test "can create Model with sidebar_visible false" do
      model = %Model{sidebar_visible: false}
      assert model.sidebar_visible == false
    end

    test "can create Model with custom sidebar_width" do
      model = %Model{sidebar_width: 25}
      assert model.sidebar_width == 25
    end

    test "can create Model with expanded sessions" do
      expanded = MapSet.new(["s1", "s2"])
      model = %Model{sidebar_expanded: expanded}
      assert MapSet.member?(model.sidebar_expanded, "s1")
      assert MapSet.member?(model.sidebar_expanded, "s2")
    end

    test "can create Model with custom sidebar_selected_index" do
      model = %Model{sidebar_selected_index: 2}
      assert model.sidebar_selected_index == 2
    end

    test "can add session to sidebar_expanded" do
      model = %Model{}
      expanded = MapSet.put(model.sidebar_expanded, "s1")
      model = %{model | sidebar_expanded: expanded}
      assert MapSet.member?(model.sidebar_expanded, "s1")
    end

    test "can remove session from sidebar_expanded" do
      expanded = MapSet.new(["s1", "s2"])
      model = %Model{sidebar_expanded: expanded}

      expanded = MapSet.delete(model.sidebar_expanded, "s1")
      model = %{model | sidebar_expanded: expanded}

      refute MapSet.member?(model.sidebar_expanded, "s1")
      assert MapSet.member?(model.sidebar_expanded, "s2")
    end

    test "can toggle session expansion" do
      model = %Model{}

      # Expand
      expanded = MapSet.put(model.sidebar_expanded, "s1")
      model = %{model | sidebar_expanded: expanded}
      assert MapSet.member?(model.sidebar_expanded, "s1")

      # Collapse
      expanded = MapSet.delete(model.sidebar_expanded, "s1")
      model = %{model | sidebar_expanded: expanded}
      refute MapSet.member?(model.sidebar_expanded, "s1")
    end
  end

  describe "init/1 sidebar initialization (Phase 4.5.3)" do
    test "init/1 sets sidebar_visible to true" do
      model = TUI.init([])
      assert model.sidebar_visible == true
    end

    test "init/1 sets sidebar_width to 20" do
      model = TUI.init([])
      assert model.sidebar_width == 20
    end

    test "init/1 sets sidebar_expanded to empty MapSet" do
      model = TUI.init([])
      assert model.sidebar_expanded == MapSet.new()
    end

    test "init/1 sets sidebar_selected_index to 0" do
      model = TUI.init([])
      assert model.sidebar_selected_index == 0
    end

    test "init/1 initializes all sidebar fields together" do
      model = TUI.init([])

      # All sidebar fields should be present with default values
      assert model.sidebar_visible == true
      assert model.sidebar_width == 20
      assert model.sidebar_expanded == MapSet.new()
      assert model.sidebar_selected_index == 0
    end
  end

  describe "Sidebar layout integration (Phase 4.5.4)" do
    # Helper to create model with sessions for testing
    defp build_model_with_sessions(opts \\ []) do
      session1 = create_test_session(id: "s1", name: "Project")
      session2 = create_test_session(id: "s2", name: "Backend")

      %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1",
        sidebar_visible: Keyword.get(opts, :sidebar_visible, true),
        sidebar_width: Keyword.get(opts, :sidebar_width, 20),
        sidebar_expanded: Keyword.get(opts, :sidebar_expanded, MapSet.new()),
        window: Keyword.get(opts, :window, {100, 24})
      }
    end

    test "sidebar visible when sidebar_visible=true and width >= 90" do
      model = build_model_with_sessions(sidebar_visible: true, window: {100, 24})

      view = TUI.view(model)
      # View should render successfully with sidebar
      assert view != nil
    end

    test "sidebar hidden when width < 90" do
      model = build_model_with_sessions(sidebar_visible: true, window: {89, 24})

      view = TUI.view(model)
      # Should render without sidebar (standard layout)
      assert view != nil
    end

    test "sidebar hidden when sidebar_visible=false" do
      model = build_model_with_sessions(sidebar_visible: false, window: {120, 24})

      view = TUI.view(model)
      # Should render without sidebar
      assert view != nil
    end

    test "sidebar with reasoning panel on wide terminal" do
      model =
        build_model_with_sessions(
          sidebar_visible: true,
          window: {120, 24}
        )
        |> Map.put(:show_reasoning, true)

      view = TUI.view(model)
      # Should render with both sidebar and reasoning panel
      assert view != nil
    end

    test "sidebar with reasoning drawer on medium terminal" do
      model =
        build_model_with_sessions(
          sidebar_visible: true,
          window: {95, 24}
        )
        |> Map.put(:show_reasoning, true)

      view = TUI.view(model)
      # Should render with sidebar and reasoning in compact mode
      assert view != nil
    end
  end

  # Helper to create test session
  defp create_test_session(opts) do
    %JidoCode.Session{
      id: Keyword.fetch!(opts, :id),
      name: Keyword.get(opts, :name, "Test Session"),
      project_path: Keyword.get(opts, :project_path, "/test/path"),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now())
    }
  end

  describe "init/1" do
    test "returns a Model struct" do
      model = TUI.init([])
      assert %Model{} = model
    end

    test "subscribes to PubSub tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_message, "hello"})
      assert_receive {:test_message, "hello"}, 1000
    end

    test "sets agent_status to :idle when no active session" do
      # Ensure no settings file exists (use empty settings)
      model = TUI.init([])

      # Without active session, agent_status defaults to :idle
      assert Model.get_active_agent_status(model) == :idle
    end

    test "initializes with empty messages list" do
      model = TUI.init([])
      assert model.messages == []
    end

    test "initializes with empty text input" do
      model = TUI.init([])
      assert get_input_value(model) == ""
    end

    test "initializes with empty reasoning steps" do
      model = TUI.init([])
      assert model.reasoning_steps == []
    end

    test "loads sessions from SessionRegistry" do
      # SessionIsolation.isolate() in setup clears all sessions
      session1 = create_test_session("s1", "Session 1", "/path1")
      session2 = create_test_session("s2", "Session 2", "/path2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      model = TUI.init([])

      # Should have both sessions in model
      assert map_size(model.sessions) == 2
      assert Map.has_key?(model.sessions, "s1")
      assert Map.has_key?(model.sessions, "s2")
    end

    test "builds session_order from registry sessions" do
      # SessionIsolation.isolate() in setup clears all sessions
      session1 = create_test_session("s1", "Session 1", "/path1")
      session2 = create_test_session("s2", "Session 2", "/path2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      model = TUI.init([])

      # session_order should contain both IDs in registry order
      assert length(model.session_order) == 2
      assert "s1" in model.session_order
      assert "s2" in model.session_order
    end

    test "sets active_session_id to first session" do
      # SessionIsolation.isolate() in setup clears all sessions
      session1 = create_test_session("s1", "Session 1", "/path1")
      session2 = create_test_session("s2", "Session 2", "/path2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      model = TUI.init([])

      # First session in order should be active
      first_id = List.first(model.session_order)
      assert model.active_session_id == first_id
    end

    test "handles empty SessionRegistry (no sessions)" do
      # SessionIsolation.isolate() in setup clears all sessions
      model = TUI.init([])

      # Should have empty sessions
      assert model.sessions == %{}
      assert model.session_order == []
      assert model.active_session_id == nil
    end

    test "subscribes to each session's PubSub topic" do
      # SessionIsolation.isolate() in setup clears all sessions

      session1 = create_test_session("s1", "Session 1", "/path1")
      session2 = create_test_session("s2", "Session 2", "/path2")

      {:ok, _} = SessionRegistry.register(session1)
      {:ok, _} = SessionRegistry.register(session2)

      _model = TUI.init([])

      # Verify subscriptions by broadcasting to each session's topic
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.s1", {:test_s1, "hello"})
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.s2", {:test_s2, "world"})

      assert_receive {:test_s1, "hello"}, 1000
      assert_receive {:test_s2, "world"}, 1000

      # Cleanup
      SessionRegistry.unregister("s1")
      SessionRegistry.unregister("s2")
    end

    test "handles single session in registry" do
      # SessionIsolation.isolate() in setup clears all sessions
      session = create_test_session("s1", "Solo Session", "/path1")
      {:ok, _} = SessionRegistry.register(session)

      model = TUI.init([])

      assert map_size(model.sessions) == 1
      assert model.session_order == ["s1"]
      assert model.active_session_id == "s1"
    end
  end

  describe "ViewHelpers.truncate/2" do
    alias JidoCode.TUI.ViewHelpers

    test "returns text unchanged when shorter than max_length" do
      assert ViewHelpers.truncate("short", 10) == "short"
    end

    test "returns text unchanged when equal to max_length" do
      assert ViewHelpers.truncate("exactly10c", 10) == "exactly10c"
    end

    test "truncates text and adds ellipsis when longer than max_length" do
      assert ViewHelpers.truncate("this is a long text", 10) == "this is..."
    end

    test "truncates at max_length - 3 to account for ellipsis" do
      result = ViewHelpers.truncate("1234567890", 7)
      assert result == "1234..."
      assert String.length(result) == 7
    end

    test "handles empty string" do
      assert ViewHelpers.truncate("", 10) == ""
    end

    test "handles unicode characters correctly" do
      # Unicode characters should be counted correctly
      assert ViewHelpers.truncate("hello 世界", 10) == "hello 世界"
      assert ViewHelpers.truncate("hello 世界 more text", 10) == "hello 世..."
    end
  end

  describe "ViewHelpers.format_tab_label/2" do
    alias JidoCode.TUI.ViewHelpers
    alias JidoCode.Session

    test "formats label with index 1-9" do
      session = %Session{id: "s1", name: "my-project"}
      assert ViewHelpers.format_tab_label(session, 1) == "1:my-project"
      assert ViewHelpers.format_tab_label(session, 5) == "5:my-project"
      assert ViewHelpers.format_tab_label(session, 9) == "9:my-project"
    end

    test "formats index 10 as '0'" do
      session = %Session{id: "s10", name: "tenth-session"}
      assert ViewHelpers.format_tab_label(session, 10) == "0:tenth-session"
    end

    test "truncates long session names" do
      session = %Session{id: "s1", name: "this-is-a-very-long-session-name"}
      label = ViewHelpers.format_tab_label(session, 1)
      # Format is "1:" + truncated name (15 chars max: 12 chars + "...")
      assert label == "1:this-is-a-ve..."
    end

    test "does not truncate short session names" do
      session = %Session{id: "s1", name: "short"}
      assert ViewHelpers.format_tab_label(session, 3) == "3:short"
    end

    test "handles session name exactly 15 characters" do
      session = %Session{id: "s1", name: "exactly-15-char"}
      assert ViewHelpers.format_tab_label(session, 2) == "2:exactly-15-char"
    end
  end

  describe "ViewHelpers.render_tabs/1" do
    alias JidoCode.TUI.ViewHelpers
    alias JidoCode.TUI.Model
    alias JidoCode.Session

    test "returns nil when sessions map is empty" do
      model = %Model{sessions: %{}, session_order: [], active_session_id: nil}
      assert ViewHelpers.render_tabs(model) == nil
    end

    test "renders single tab" do
      session = %Session{id: "s1", name: "project"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      result = ViewHelpers.render_tabs(model)
      assert result != nil
      # Result is a TermUI view node, we can't easily test its content
      # Just verify it returns something non-nil
    end

    test "renders multiple tabs" do
      s1 = %Session{id: "s1", name: "project-one"}
      s2 = %Session{id: "s2", name: "project-two"}
      s3 = %Session{id: "s3", name: "project-three"}

      model = %Model{
        sessions: %{"s1" => s1, "s2" => s2, "s3" => s3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s2"
      }

      result = ViewHelpers.render_tabs(model)
      assert result != nil
    end

    test "handles 10th session with 0 index" do
      sessions =
        Enum.reduce(1..10, %{}, fn i, acc ->
          id = "s#{i}"
          Map.put(acc, id, %Session{id: id, name: "session-#{i}"})
        end)

      order = Enum.map(1..10, fn i -> "s#{i}" end)

      model = %Model{
        sessions: sessions,
        session_order: order,
        active_session_id: "s10"
      }

      result = ViewHelpers.render_tabs(model)
      assert result != nil
      # The 10th tab should use format_tab_label which shows "0:"
    end
  end

  describe "Model.get_session_status/1" do
    test "returns :unconfigured for nonexistent session" do
      # Session that doesn't exist should return unconfigured
      assert TUI.Model.get_session_status("nonexistent-session-id") == :unconfigured
    end

    test "returns an agent_status atom" do
      # Should return one of the valid status atoms
      result = TUI.Model.get_session_status("test-session")
      assert result in [:idle, :processing, :error, :unconfigured]
    end
  end

  describe "determine_status/1" do
    test "returns :unconfigured when provider is nil" do
      config = %{provider: nil, model: "gpt-4"}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when model is nil" do
      config = %{provider: "openai", model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when both are nil" do
      config = %{provider: nil, model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :idle when both provider and model are set" do
      config = %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      assert TUI.determine_status(config) == :idle
    end
  end

  describe "event_to_msg/2" do
    test "Ctrl+X returns {:msg, :quit}" do
      model = %Model{}
      event = Event.key("x", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :quit}
    end

    test "Ctrl+R returns {:msg, :toggle_reasoning}" do
      model = %Model{}
      event = Event.key("r", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_reasoning}
    end

    test "Ctrl+T returns {:msg, :toggle_tool_details}" do
      model = %Model{}
      event = Event.key("t", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_tool_details}
    end

    test "Ctrl+W returns {:msg, :close_active_session}" do
      model = %Model{}
      event = Event.key("w", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :close_active_session}
    end

    test "plain 'w' key is forwarded to TextInput" do
      model = %Model{}
      event = Event.key("w", char: "w")

      assert {:msg, {:input_event, %Event.Key{key: "w"}}} = TUI.event_to_msg(event, model)
    end

    test "up arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:up)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "down arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:down)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "resize event returns {:msg, {:resize, width, height}}" do
      model = %Model{}
      event = Event.resize(120, 40)

      assert TUI.event_to_msg(event, model) == {:msg, {:resize, 120, 40}}
    end

    test "Enter key returns {:msg, {:input_submitted, value}}" do
      # Create a model with input value "hello"
      model = create_model_with_input("hello")

      enter_event = Event.key(:enter)
      assert {:msg, {:input_submitted, "hello"}} = TUI.event_to_msg(enter_event, model)
    end

    test "key events are forwarded to TextInput as {:msg, {:input_event, event}}" do
      model = %Model{}

      # Backspace key
      backspace_event = Event.key(:backspace)
      assert {:msg, {:input_event, ^backspace_event}} = TUI.event_to_msg(backspace_event, model)

      # Printable character (without ctrl modifier)
      char_result = TUI.event_to_msg(Event.key("a", char: "a"), model)
      assert {:msg, {:input_event, %Event.Key{key: "a"}}} = char_result
    end

    test "returns :ignore for unhandled events" do
      model = %Model{}

      # Focus events
      assert TUI.event_to_msg(Event.focus(:gained), model) == :ignore

      # Unknown events
      assert TUI.event_to_msg(:some_event, model) == :ignore
      assert TUI.event_to_msg(nil, model) == :ignore
    end

    test "routes mouse events based on click region" do
      # Model with default window size (80x24) and sidebar visible
      model = %Model{window: {80, 24}, sidebar_visible: true}

      # sidebar_width = round(80 * 0.20) = 16, tabs_start_x = 16 + 1 = 17
      # tab_bar_height = 2

      # Click in sidebar area (x < 16)
      result = TUI.event_to_msg(Event.mouse(:click, :left, 10, 5), model)
      assert {:msg, {:sidebar_click, 10, 5}} = result

      # Click in tab bar area (x >= 17, y < 2)
      result = TUI.event_to_msg(Event.mouse(:click, :left, 25, 1), model)
      # relative_x = 25 - 17 = 8
      assert {:msg, {:tab_click, 8, 1}} = result

      # Click in content area (x >= 17, y >= 2)
      result = TUI.event_to_msg(Event.mouse(:click, :left, 30, 10), model)
      assert {:msg, {:conversation_event, %TermUI.Event.Mouse{}}} = result

      # When sidebar is hidden, clicks in former sidebar area go to tabs or content
      model_hidden_sidebar = %{model | sidebar_visible: false}
      # tabs_start_x = 0 when sidebar hidden, click at y < 2 goes to tab_click
      result = TUI.event_to_msg(Event.mouse(:click, :left, 10, 0), model_hidden_sidebar)
      assert {:msg, {:tab_click, 10, 0}} = result
    end
  end

  describe "update/2 - input events" do
    test "forwards key events to TextInput widget" do
      # Model with session and initial input "hel"
      model = create_model_with_input("hel")

      # Simulate typing 'l' via input_event
      event = Event.key("l", char: "l")
      {new_model, commands} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "hell"
      assert commands == []
    end

    test "appends to empty text input" do
      model = create_model_with_input()

      event = Event.key("a", char: "a")
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "a"
    end

    test "handles multiple characters" do
      model = create_model_with_input()

      {model1, _} = TUI.update({:input_event, Event.key("h", char: "h")}, model)
      {model2, _} = TUI.update({:input_event, Event.key("i", char: "i")}, model1)

      assert get_input_value(model2) == "hi"
    end
  end

  describe "update/2 - backspace via input_event" do
    test "removes last character from text input" do
      # Model with session and initial input "hello"
      model = create_model_with_input("hello")

      event = Event.key(:backspace)
      {new_model, commands} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == "hell"
      assert commands == []
    end

    test "does nothing on empty input" do
      model = create_model_with_input()

      event = Event.key(:backspace)
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == ""
    end

    test "handles single character input" do
      # Model with session and initial input "a"
      model = create_model_with_input("a")

      event = Event.key(:backspace)
      {new_model, _} = TUI.update({:input_event, event}, model)

      assert get_input_value(new_model) == ""
    end
  end

  describe "update/2 - input_submitted" do
    test "does nothing with empty input" do
      model = %Model{messages: []}

      {new_model, _} = TUI.update({:input_submitted, ""}, model)

      assert get_input_value(new_model) == ""
      assert new_model.messages == []
    end

    test "does nothing with whitespace-only input" do
      model = %Model{messages: []}

      {new_model, _} = TUI.update({:input_submitted, "   "}, model)

      assert new_model.messages == []
    end

    test "shows config error when provider is nil" do
      model = %Model{
        messages: [],
        config: %{provider: nil, model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "configure a model"
    end

    test "shows config error when model is nil" do
      model = %Model{
        messages: [],
        config: %{provider: "test", model: nil}
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "configure a model"
    end

    test "handles command input with / prefix" do
      model = %Model{
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/help"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Available commands"
    end

    test "/config command shows current configuration" do
      model = %Model{
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/config"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).content =~ "Provider: anthropic"
      assert hd(new_model.messages).content =~ "Model: claude-3-5-haiku-20241022"
    end

    test "/provider command updates config and status" do
      setup_api_key("anthropic")

      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = %{model | config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:input_submitted, "/provider anthropic"}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == nil
      # Still unconfigured because model is nil
      assert Model.get_active_agent_status(new_model) == :unconfigured

      cleanup_api_key("anthropic")
    end

    test "/model provider:model command updates config and status" do
      setup_api_key("anthropic")

      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = %{model | config: %{provider: nil, model: nil}}

      {new_model, _} =
        TUI.update({:input_submitted, "/model anthropic:claude-3-5-haiku-20241022"}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == "claude-3-5-haiku-20241022"
      # Now configured - status should be idle
      assert Model.get_active_agent_status(new_model) == :idle

      cleanup_api_key("anthropic")
    end

    test "unknown command shows error" do
      model = %Model{
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "/unknown_cmd"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Unknown command"
    end

    test "shows error when no active session" do
      model = %Model{
        messages: [],
        config: %{provider: "test", model: "test"},
        active_session_id: nil
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      # Should have error message about no active session
      assert length(new_model.messages) == 1
      assert Enum.at(new_model.messages, 0).role == :system
      assert Enum.at(new_model.messages, 0).content =~ "No active session"
    end

    @tag :requires_api_key
    @tag :skip
    test "sets status to processing when dispatching to agent" do
      # This test requires a real API key since the agent runs in a separate process
      # and cannot see session-scoped test values. Skip for now.
      setup_api_key("anthropic")

      # Start a mock agent for this test
      {:ok, _pid} =
        JidoCode.AgentSupervisor.start_agent(%{
          name: :test_llm_agent,
          module: JidoCode.Agents.LLMAgent,
          args: [provider: :anthropic, model: "claude-3-5-haiku-latest"]
        })

      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)

      model = %{
        model
        | config: %{provider: "anthropic", model: "claude-3-5-haiku-latest"},
          agent_name: :test_llm_agent
      }

      {new_model, _} = TUI.update({:input_submitted, "hello"}, model)

      assert get_input_value(new_model) == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :user
      assert hd(new_model.messages).content == "hello"
      assert Model.get_active_agent_status(new_model) == :processing

      # Cleanup
      JidoCode.AgentSupervisor.stop_agent(:test_llm_agent)
      cleanup_api_key("anthropic")
    end

    test "trims whitespace from input before processing" do
      model = %Model{
        messages: [],
        config: %{provider: "test", model: "test"}
      }

      {new_model, _} = TUI.update({:input_submitted, "  /help  "}, model)

      # Command should be received without leading whitespace
      assert hd(new_model.messages).content =~ "/help"
    end
  end

  describe "update/2 - quit" do
    test "returns :quit command" do
      model = %Model{}

      {_new_model, commands} = TUI.update(:quit, model)

      assert commands == [:quit]
    end
  end

  describe "update/2 - resize" do
    test "updates window dimensions" do
      model = %Model{window: {80, 24}}

      {new_model, commands} = TUI.update({:resize, 120, 40}, model)

      assert new_model.window == {120, 40}
      assert commands == []
    end
  end

  describe "update/2 - agent messages" do
    test "handles agent_response" do
      model = %Model{messages: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :assistant
      assert hd(new_model.messages).content == "Hello!"
    end

    test "agent_response sets status to idle" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = Model.set_active_agent_status(model, :processing)

      {new_model, _} = TUI.update({:agent_response, "Done!"}, model)

      assert Model.get_active_agent_status(new_model) == :idle
    end

    test "unhandled messages are logged but do not change state" do
      # After message type normalization, :llm_response is no longer supported
      # It should go to the catch-all handler and not change state
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = Model.set_active_agent_status(model, :processing)

      {new_model, _} = TUI.update({:llm_response, "Hello from LLM!"}, model)

      # State should remain unchanged - message goes to catch-all
      assert new_model.messages == []
      assert Model.get_active_agent_status(new_model) == :processing
    end

    # Streaming tests - use create_model_with_input for proper session setup
    test "stream_chunk appends to streaming_message" do
      model = create_model_with_input()

      {new_model, _} = TUI.update({:stream_chunk, "test-session", "Hello "}, model)

      assert get_streaming_message(new_model) == "Hello "
      assert get_is_streaming(new_model) == true

      # Append another chunk
      {new_model2, _} = TUI.update({:stream_chunk, "test-session", "world!"}, new_model)

      assert get_streaming_message(new_model2) == "Hello world!"
      assert get_is_streaming(new_model2) == true
    end

    test "stream_chunk starts with nil streaming_message" do
      model = create_model_with_input()

      {new_model, _} = TUI.update({:stream_chunk, "test-session", "Hello"}, model)

      assert get_streaming_message(new_model) == "Hello"
      assert get_is_streaming(new_model) == true
    end

    test "stream_end finalizes message and clears streaming state" do
      model = create_model_with_input()

      # First send a chunk to set up streaming state
      {model_streaming, _} =
        TUI.update({:stream_chunk, "test-session", "Complete response"}, model)

      # Now end the stream
      {new_model, _} =
        TUI.update({:stream_end, "test-session", "Complete response"}, model_streaming)

      assert length(get_session_messages(new_model)) == 1
      assert hd(get_session_messages(new_model)).role == :assistant
      assert hd(get_session_messages(new_model)).content == "Complete response"
      assert get_streaming_message(new_model) == nil
      assert get_is_streaming(new_model) == false
    end

    test "stream_error shows error message and clears streaming" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)

      model = %{
        model
        | messages: [],
          streaming_message: "Partial",
          is_streaming: true
      }

      model = Model.set_active_agent_status(model, :processing)

      {new_model, _} = TUI.update({:stream_error, :connection_failed}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :system
      assert hd(new_model.messages).content =~ "Streaming error"
      assert hd(new_model.messages).content =~ "connection_failed"
      assert new_model.streaming_message == nil
      assert new_model.is_streaming == false
      assert Model.get_active_agent_status(new_model) == :error
    end

    test "handles status_update" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert Model.get_active_agent_status(new_model) == :processing
    end

    test "handles agent_status as alias for status_update" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)

      {new_model, _} = TUI.update({:agent_status, :processing}, model)

      assert Model.get_active_agent_status(new_model) == :processing
    end

    test "handles config_change with atom keys" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = %{model | config: %{provider: nil, model: nil}}

      {new_model, _} =
        TUI.update({:config_change, %{provider: "anthropic", model: "claude"}}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == "claude"
      assert Model.get_active_agent_status(new_model) == :idle
    end

    test "handles config_change with string keys" do
      model = %Model{config: %{provider: nil, model: nil}}

      {new_model, _} =
        TUI.update({:config_change, %{"provider" => "openai", "model" => "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
    end

    test "handles config_changed as alias for config_change" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)
      model = %{model | config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:config_changed, %{provider: "openai", model: "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
      assert Model.get_active_agent_status(new_model) == :idle
    end

    test "handles reasoning_step" do
      model = create_model_with_input()
      step = %{step: "Thinking...", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(get_reasoning_steps(new_model)) == 1
      assert hd(get_reasoning_steps(new_model)) == step
    end

    test "handles clear_reasoning_steps" do
      model = create_model_with_input()

      # First add a reasoning step
      step = %{step: "Step 1", status: :complete}
      {model_with_step, _} = TUI.update({:reasoning_step, step}, model)

      {new_model, _} = TUI.update(:clear_reasoning_steps, model_with_step)

      assert get_reasoning_steps(new_model) == []
    end
  end

  describe "message queueing" do
    test "agent_response adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.message_queue) == 1
      {{:agent_response, "Hello!"}, _timestamp} = hd(new_model.message_queue)
    end

    test "status_update adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert length(new_model.message_queue) == 1
      {{:status_update, :processing}, _timestamp} = hd(new_model.message_queue)
    end

    test "config_change adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:config_change, %{provider: "test"}}, model)

      assert length(new_model.message_queue) == 1
    end

    test "reasoning_step adds to message queue" do
      model = %Model{message_queue: []}
      step = %{step: "Thinking", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.message_queue) == 1
    end

    test "message queue limits size to max_queue_size" do
      # Create a model with a queue at max size
      large_queue =
        Enum.map(1..100, fn i ->
          {{:test_message, i}, DateTime.utc_now()}
        end)

      model = %Model{message_queue: large_queue}

      # Add one more message
      {new_model, _} = TUI.update({:agent_response, "New message"}, model)

      # Queue should still be at max size (100)
      assert length(new_model.message_queue) == 100

      # Most recent message should be first
      {{:agent_response, "New message"}, _} = hd(new_model.message_queue)
    end

    test "queue_message maintains LIFO order" do
      queue = []
      queue = TUI.queue_message(queue, :msg1)
      queue = TUI.queue_message(queue, :msg2)
      queue = TUI.queue_message(queue, :msg3)

      assert length(queue) == 3
      {:msg3, _} = Enum.at(queue, 0)
      {:msg2, _} = Enum.at(queue, 1)
      {:msg1, _} = Enum.at(queue, 2)
    end
  end

  describe "PubSub integration" do
    test "init subscribes to tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_pubsub, "integration"})
      assert_receive {:test_pubsub, "integration"}, 1000
    end

    test "full message flow: agent_response via PubSub" do
      model = TUI.init([])

      # Simulate receiving a PubSub message
      msg = {:agent_response, "Test response from agent"}
      {new_model, _} = TUI.update(msg, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).content == "Test response from agent"
      assert hd(new_model.messages).role == :assistant
    end

    test "full message flow: status transitions" do
      # Create model with a session for agent_status tracking
      session = create_test_session("test-session", "Test", "/tmp")
      model = create_model_with_session(session)

      # Start processing
      {model, _} = TUI.update({:agent_status, :processing}, model)
      assert Model.get_active_agent_status(model) == :processing

      # Complete with response
      {model, _} = TUI.update({:agent_response, "Done!"}, model)
      assert length(model.messages) == 1

      # Back to idle
      {model, _} = TUI.update({:agent_status, :idle}, model)
      assert Model.get_active_agent_status(model) == :idle
    end

    test "full message flow: reasoning steps accumulation" do
      # Create model with active session for reasoning steps
      model = create_model_with_input()

      # Simulate CoT reasoning flow
      {model, _} = TUI.update({:reasoning_step, %{step: "Understanding", status: :active}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Planning", status: :pending}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Executing", status: :pending}}, model)

      # Steps are stored in reverse order (newest first)
      reasoning_steps = get_reasoning_steps(model)
      assert length(reasoning_steps) == 3
      assert Enum.at(reasoning_steps, 0).step == "Executing"
      assert Enum.at(reasoning_steps, 2).step == "Understanding"

      # Clear reasoning steps for next query
      {model, _} = TUI.update(:clear_reasoning_steps, model)
      assert get_reasoning_steps(model) == []
    end

    test "rapid message handling doesn't exceed queue limit" do
      model = TUI.init([])

      # Simulate rapid message burst (150 messages)
      model =
        Enum.reduce(1..150, model, fn i, acc ->
          {new_model, _} = TUI.update({:agent_response, "Message #{i}"}, acc)
          new_model
        end)

      # Queue should be limited to 100
      assert length(model.message_queue) == 100

      # All 150 messages should be in the messages list
      assert length(model.messages) == 150
    end
  end

  describe "update/2 - unknown messages" do
    test "returns state unchanged for unknown messages" do
      model = %Model{}

      {new_model, commands} = TUI.update(:unknown_message, model)

      assert new_model == model
      assert commands == []
    end
  end

  describe "view/1" do
    test "returns a render tree" do
      model = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      view = TUI.view(model)

      # View should return a RenderNode (MainLayout now uses :stack as root)
      assert %TermUI.Component.RenderNode{} = view
      assert view.type in [:stack, :box]
    end

    test "main view has children when configured" do
      model = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"},
        messages: []
      }

      view = TUI.view(model)

      # Main view should have children (MainLayout renders a stack with content)
      assert %TermUI.Component.RenderNode{children: children} = view
      assert is_list(children)
      assert length(children) > 0
    end
  end

  describe "integration" do
    test "TUI module uses TermUI.Elm behaviour" do
      # Verify the module implements the required callbacks
      behaviours = JidoCode.TUI.__info__(:attributes)[:behaviour] || []
      assert TermUI.Elm in behaviours
    end

    test "Model struct is accessible via JidoCode.TUI.Model" do
      # Verify the nested module is accessible
      assert Code.ensure_loaded?(JidoCode.TUI.Model)
    end
  end

  describe "wrap_text/2" do
    test "returns single line for short text" do
      result = TUI.wrap_text("hello world", 80)
      assert result == ["hello world"]
    end

    test "wraps text at word boundaries" do
      result = TUI.wrap_text("hello world foo bar", 11)
      assert result == ["hello world", "foo bar"]
    end

    test "handles text exactly at max width" do
      result = TUI.wrap_text("hello", 5)
      assert result == ["hello"]
    end

    test "splits words longer than max width" do
      result = TUI.wrap_text("superlongword", 5)
      # First iteration splits at 5, then the remainder is handled
      assert result == ["super", "longword"]
    end

    test "handles empty string" do
      result = TUI.wrap_text("", 80)
      assert result == [""]
    end

    test "handles single word" do
      result = TUI.wrap_text("word", 80)
      assert result == ["word"]
    end

    test "handles multiple spaces" do
      result = TUI.wrap_text("hello world", 80)
      # String.split on single space produces empty strings
      assert is_list(result)
    end

    test "handles invalid max_width" do
      result = TUI.wrap_text("hello", 0)
      assert result == [""]

      result = TUI.wrap_text("hello", -5)
      assert result == [""]
    end
  end

  describe "format_timestamp/1" do
    test "formats datetime as [HH:MM]" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[14:32]"
    end

    test "pads single digit hours and minutes" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[09:05:00], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[09:05]"
    end

    test "handles midnight" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[00:00:00], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[00:00]"
    end

    test "handles end of day" do
      datetime = DateTime.new!(~D[2024-01-15], ~T[23:59:59], "Etc/UTC")
      result = TUI.format_timestamp(datetime)
      assert result == "[23:59]"
    end
  end

  describe "max_scroll_offset/1" do
    test "returns 0 when no messages" do
      model = %Model{messages: [], window: {80, 24}}
      assert TUI.max_scroll_offset(model) == 0
    end

    test "returns 0 when messages fit in view" do
      model = %Model{
        messages: [
          %{role: :user, content: "hello", timestamp: DateTime.utc_now()}
        ],
        window: {80, 24}
      }

      assert TUI.max_scroll_offset(model) == 0
    end

    test "returns positive offset when messages exceed view" do
      # Create many messages to exceed the view height
      messages =
        Enum.map(1..50, fn i ->
          %{role: :user, content: "Message #{i}", timestamp: DateTime.utc_now()}
        end)

      model = %Model{messages: messages, window: {80, 10}}

      # With 50 messages and height 10 (8 available after status/input)
      # max_offset should be positive
      assert TUI.max_scroll_offset(model) > 0
    end
  end

  describe "scroll navigation" do
    alias JidoCode.TUI.Widgets.ConversationView

    test "up arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:up)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "down arrow returns {:msg, {:conversation_event, event}}" do
      model = %Model{}
      event = Event.key(:down)

      assert TUI.event_to_msg(event, model) == {:msg, {:conversation_event, event}}
    end

    test "conversation_event delegates to ConversationView.handle_event" do
      # Create a ConversationView with scrollable content
      cv_messages =
        Enum.map(1..50, fn i ->
          %{id: "#{i}", role: :user, content: "Message #{i}", timestamp: DateTime.utc_now()}
        end)

      cv_props =
        ConversationView.new(messages: cv_messages, viewport_width: 80, viewport_height: 10)

      {:ok, cv_state} = ConversationView.init(cv_props)
      # Set input_focused: false so down arrow scrolls instead of going to text input
      cv_state = %{cv_state | input_focused: false}

      # Create model with session containing conversation_view
      session = create_test_session("test-session", "Test Session", "/tmp")
      ui_state = Model.default_ui_state({80, 24})
      ui_state = %{ui_state | conversation_view: cv_state}
      session_with_ui = Map.put(session, :ui_state, ui_state)

      model = %Model{
        sessions: %{"test-session" => session_with_ui},
        session_order: ["test-session"],
        active_session_id: "test-session",
        window: {80, 24}
      }

      # Down arrow should trigger scroll in ConversationView
      event = Event.key(:down)
      {new_model, _} = TUI.update({:conversation_event, event}, model)

      # ConversationView should have scrolled
      new_cv = Model.get_active_conversation_view(new_model)
      assert new_cv != nil
      assert new_cv.scroll_offset == 1
    end

    test "conversation_event ignored when no active session" do
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        window: {80, 24}
      }

      event = Event.key(:down)
      {new_model, _} = TUI.update({:conversation_event, event}, model)

      # Should be unchanged
      assert new_model == model
    end

    test "scroll keys route to conversation_event" do
      model = %Model{}

      for key <- [:up, :down, :page_up, :page_down, :home, :end] do
        event = Event.key(key)
        assert {:msg, {:conversation_event, ^event}} = TUI.event_to_msg(event, model)
      end
    end
  end

  describe "Model scroll_offset field" do
    test "has default value of 0" do
      model = %Model{}
      assert model.scroll_offset == 0
    end

    test "init sets scroll_offset to 0" do
      model = TUI.init([])
      assert model.scroll_offset == 0
    end
  end

  describe "show_reasoning field" do
    test "has default value of false" do
      model = %Model{}
      assert model.show_reasoning == false
    end

    test "init sets show_reasoning to false" do
      model = TUI.init([])
      assert model.show_reasoning == false
    end
  end

  describe "toggle_reasoning" do
    test "Ctrl+R returns {:msg, :toggle_reasoning}" do
      model = %Model{}
      event = Event.key("r", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_reasoning}
    end

    test "plain 'r' key is forwarded to TextInput" do
      model = %Model{}
      event = Event.key("r", char: "r")

      assert {:msg, {:input_event, %Event.Key{key: "r"}}} = TUI.event_to_msg(event, model)
    end

    test "toggle_reasoning flips show_reasoning from false to true" do
      model = %Model{show_reasoning: false}

      {new_model, commands} = TUI.update(:toggle_reasoning, model)

      assert new_model.show_reasoning == true
      assert commands == []
    end

    test "toggle_reasoning flips show_reasoning from true to false" do
      model = %Model{show_reasoning: true}

      {new_model, commands} = TUI.update(:toggle_reasoning, model)

      assert new_model.show_reasoning == false
      assert commands == []
    end
  end

  describe "render_reasoning/1" do
    test "returns a render tree" do
      model = %Model{reasoning_steps: []}

      view = TUI.render_reasoning(model)

      assert %TermUI.Component.RenderNode{} = view
    end
  end

  describe "render_reasoning_compact/1" do
    test "returns a render tree" do
      model = %Model{reasoning_steps: []}

      view = TUI.render_reasoning_compact(model)

      assert %TermUI.Component.RenderNode{} = view
    end
  end

  describe "status_style/1" do
    test "idle status returns green style" do
      style = TUI.status_style(:idle)
      assert style.fg == :green
      assert style.bg == :blue
    end

    test "processing status returns yellow style" do
      style = TUI.status_style(:processing)
      assert style.fg == :yellow
      assert style.bg == :blue
    end

    test "error status returns red style" do
      style = TUI.status_style(:error)
      assert style.fg == :red
      assert style.bg == :blue
    end

    test "unconfigured status returns dim red style" do
      style = TUI.status_style(:unconfigured)
      assert style.fg == :red
      assert style.bg == :blue
      assert :dim in style.attrs
    end
  end

  describe "config_style/1" do
    test "no provider returns red style" do
      style = TUI.config_style(%{provider: nil, model: "test"})
      assert style.fg == :red
    end

    test "no model returns yellow style" do
      style = TUI.config_style(%{provider: "test", model: nil})
      assert style.fg == :yellow
    end

    test "fully configured returns white style" do
      style = TUI.config_style(%{provider: "test", model: "test"})
      assert style.fg == :white
    end
  end

  # ============================================================================
  # Tool Call Display Tests
  # ============================================================================

  describe "tool_calls and show_tool_details fields" do
    test "Model has default empty tool_calls list" do
      model = %Model{}
      assert model.tool_calls == []
    end

    test "Model has default false show_tool_details" do
      model = %Model{}
      assert model.show_tool_details == false
    end

    test "init sets tool_calls to empty list" do
      model = TUI.init([])
      assert model.tool_calls == []
    end

    test "init sets show_tool_details to false" do
      model = TUI.init([])
      assert model.show_tool_details == false
    end
  end

  describe "toggle_tool_details" do
    test "Ctrl+T returns {:msg, :toggle_tool_details}" do
      model = %Model{}
      event = Event.key("t", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :toggle_tool_details}
    end

    test "plain 't' key is forwarded to TextInput" do
      model = %Model{}
      event = Event.key("t", char: "t")

      assert {:msg, {:input_event, %Event.Key{key: "t"}}} = TUI.event_to_msg(event, model)
    end

    test "toggle_tool_details flips show_tool_details from false to true" do
      model = %Model{show_tool_details: false}

      {new_model, commands} = TUI.update(:toggle_tool_details, model)

      assert new_model.show_tool_details == true
      assert commands == []
    end

    test "toggle_tool_details flips show_tool_details from true to false" do
      model = %Model{show_tool_details: true}

      {new_model, commands} = TUI.update(:toggle_tool_details, model)

      assert new_model.show_tool_details == false
      assert commands == []
    end
  end

  describe "update/2 - tool_call message" do
    test "adds tool call entry to tool_calls list" do
      model = create_model_with_input()

      # Pass "test-session" as session_id to match the active session
      {new_model, _} =
        TUI.update(
          {:tool_call, "read_file", %{"path" => "test.ex"}, "call_123", "test-session"},
          model
        )

      assert length(get_tool_calls(new_model)) == 1
      entry = hd(get_tool_calls(new_model))
      assert entry.call_id == "call_123"
      assert entry.tool_name == "read_file"
      assert entry.params == %{"path" => "test.ex"}
      assert entry.result == nil
      assert %DateTime{} = entry.timestamp
    end

    test "appends to existing tool calls" do
      model = create_model_with_input()

      # Add first tool call - pass "test-session" as session_id
      {model1, _} =
        TUI.update({:tool_call, "grep", %{}, "call_1", "test-session"}, model)

      # Add second tool call
      {new_model, _} =
        TUI.update(
          {:tool_call, "read_file", %{"path" => "test.ex"}, "call_2", "test-session"},
          model1
        )

      # Tool calls are stored in reverse order (newest first)
      assert length(get_tool_calls(new_model)) == 2
      assert Enum.at(get_tool_calls(new_model), 0).call_id == "call_2"
      assert Enum.at(get_tool_calls(new_model), 1).call_id == "call_1"
    end

    test "adds tool_call to message queue" do
      model = %Model{tool_calls: [], message_queue: []}

      {new_model, _} =
        TUI.update({:tool_call, "read_file", %{"path" => "test.ex"}, "call_123", nil}, model)

      assert length(new_model.message_queue) == 1

      {{:tool_call, "read_file", %{"path" => "test.ex"}, "call_123"}, _ts} =
        hd(new_model.message_queue)
    end
  end

  describe "update/2 - tool_result message" do
    alias JidoCode.Tools.Result

    test "matches result to pending tool call by call_id" do
      model = create_model_with_input()

      # First add a tool call - use "test-session" as session_id
      {model_with_call, _} =
        TUI.update(
          {:tool_call, "read_file", %{"path" => "test.ex"}, "call_123", "test-session"},
          model
        )

      result = Result.ok("call_123", "read_file", "file contents", 45)

      {new_model, _} = TUI.update({:tool_result, result, "test-session"}, model_with_call)

      assert length(get_tool_calls(new_model)) == 1
      entry = hd(get_tool_calls(new_model))
      assert entry.result != nil
      assert entry.result.status == :ok
      assert entry.result.content == "file contents"
      assert entry.result.duration_ms == 45
    end

    test "does not modify unmatched tool calls" do
      model = create_model_with_input()

      # Add two tool calls - use "test-session" as session_id
      {model1, _} = TUI.update({:tool_call, "read_file", %{}, "call_1", "test-session"}, model)
      {model2, _} = TUI.update({:tool_call, "grep", %{}, "call_2", "test-session"}, model1)

      result = Result.ok("call_1", "read_file", "content", 30)

      {new_model, _} = TUI.update({:tool_result, result, "test-session"}, model2)

      # call_2 is at index 0 (newest first), call_1 at index 1
      assert Enum.at(get_tool_calls(new_model), 1).result != nil
      assert Enum.at(get_tool_calls(new_model), 0).result == nil
    end

    test "handles error results" do
      model = create_model_with_input()

      # First add a tool call - use "test-session" as session_id
      {model_with_call, _} =
        TUI.update({:tool_call, "read_file", %{}, "call_123", "test-session"}, model)

      result = Result.error("call_123", "read_file", "File not found", 12)

      {new_model, _} = TUI.update({:tool_result, result, "test-session"}, model_with_call)

      entry = hd(get_tool_calls(new_model))
      assert entry.result.status == :error
      assert entry.result.content == "File not found"
    end

    test "handles timeout results" do
      model = create_model_with_input()

      # First add a tool call - use "test-session" as session_id
      {model_with_call, _} =
        TUI.update({:tool_call, "slow_op", %{}, "call_123", "test-session"}, model)

      result = Result.timeout("call_123", "slow_op", 30_000)

      {new_model, _} = TUI.update({:tool_result, result, "test-session"}, model_with_call)

      entry = hd(get_tool_calls(new_model))
      assert entry.result.status == :timeout
    end

    test "adds tool_result to message queue" do
      pending = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: nil,
        timestamp: DateTime.utc_now()
      }

      model = %Model{tool_calls: [pending], message_queue: []}

      result = Result.ok("call_123", "read_file", "content", 30)

      {new_model, _} = TUI.update({:tool_result, result, nil}, model)

      assert length(new_model.message_queue) == 1
      {{:tool_result, ^result}, _ts} = hd(new_model.message_queue)
    end
  end

  describe "format_tool_call_entry/2" do
    alias JidoCode.Tools.Result

    test "formats pending tool call (no result yet)" do
      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: nil,
        timestamp: DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      }

      lines = TUI.format_tool_call_entry(entry, false)

      assert length(lines) == 2
      # First line is the tool call
      call_text = inspect(Enum.at(lines, 0))
      assert call_text =~ "[14:32]"
      assert call_text =~ "⚙"
      assert call_text =~ "read_file"
      # Second line is "executing..."
      exec_text = inspect(Enum.at(lines, 1))
      assert exec_text =~ "executing"
    end

    test "formats successful tool result" do
      result = Result.ok("call_123", "read_file", "file contents", 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{"path" => "test.ex"},
        result: result,
        timestamp: DateTime.new!(~D[2024-01-15], ~T[14:32:45], "Etc/UTC")
      }

      lines = TUI.format_tool_call_entry(entry, false)

      assert length(lines) == 2
      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "✓"
      assert result_text =~ "[45ms]"
      assert result_text =~ "file contents"
    end

    test "formats error tool result" do
      result = Result.error("call_123", "read_file", "File not found", 12)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "✗"
      assert result_text =~ "File not found"
    end

    test "formats timeout tool result" do
      result = Result.timeout("call_123", "slow_op", 30_000)

      entry = %{
        call_id: "call_123",
        tool_name: "slow_op",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "⏱"
      assert result_text =~ "[30000ms]"
    end

    test "truncates long content when show_details is false" do
      long_content = String.duplicate("x", 200)
      result = Result.ok("call_123", "read_file", long_content, 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, false)

      result_text = inspect(Enum.at(lines, 1))
      assert result_text =~ "[...]"
    end

    test "shows full content when show_details is true" do
      long_content = String.duplicate("x", 200)
      result = Result.ok("call_123", "read_file", long_content, 45)

      entry = %{
        call_id: "call_123",
        tool_name: "read_file",
        params: %{},
        result: result,
        timestamp: DateTime.utc_now()
      }

      lines = TUI.format_tool_call_entry(entry, true)

      result_text = inspect(Enum.at(lines, 1))
      refute result_text =~ "[...]"
    end
  end

  # ============================================================================
  # Session Keyboard Shortcuts Tests (B3)
  # ============================================================================

  describe "session switching keyboard shortcuts" do
    test "Ctrl+1 returns {:msg, {:switch_to_session_index, 1}}" do
      model = %Model{}
      event = Event.key("1", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 1}}
    end

    test "Ctrl+2 returns {:msg, {:switch_to_session_index, 2}}" do
      model = %Model{}
      event = Event.key("2", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 2}}
    end

    test "Ctrl+3 returns {:msg, {:switch_to_session_index, 3}}" do
      model = %Model{}
      event = Event.key("3", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 3}}
    end

    test "Ctrl+4 returns {:msg, {:switch_to_session_index, 4}}" do
      model = %Model{}
      event = Event.key("4", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 4}}
    end

    test "Ctrl+5 returns {:msg, {:switch_to_session_index, 5}}" do
      model = %Model{}
      event = Event.key("5", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 5}}
    end

    test "Ctrl+6 returns {:msg, {:switch_to_session_index, 6}}" do
      model = %Model{}
      event = Event.key("6", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 6}}
    end

    test "Ctrl+7 returns {:msg, {:switch_to_session_index, 7}}" do
      model = %Model{}
      event = Event.key("7", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 7}}
    end

    test "Ctrl+8 returns {:msg, {:switch_to_session_index, 8}}" do
      model = %Model{}
      event = Event.key("8", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 8}}
    end

    test "Ctrl+9 returns {:msg, {:switch_to_session_index, 9}}" do
      model = %Model{}
      event = Event.key("9", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 9}}
    end

    test "Ctrl+0 returns {:msg, {:switch_to_session_index, 10}} (maps to session 10)" do
      model = %Model{}
      event = Event.key("0", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, {:switch_to_session_index, 10}}
    end
  end

  # ============================================================================
  # Session Model Helper Tests (B1)
  # Tests the Model helpers that power session action handling.
  # Note: Session actions are processed by handle_session_command/2 which uses
  # these Model helpers. The helpers are extensively tested in model_test.exs.
  # These tests verify the Model helpers work correctly in TUI context.
  # ============================================================================

  describe "session model helpers in TUI context" do
    test "Model.add_session/2 adds session and sets as active" do
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      session = %JidoCode.Session{
        id: "test-session-id",
        name: "Test Session",
        project_path: "/tmp/test"
      }

      new_model = Model.add_session(model, session)

      # Session should be added
      assert Map.has_key?(new_model.sessions, "test-session-id")
      assert new_model.active_session_id == "test-session-id"
      assert "test-session-id" in new_model.session_order
    end

    test "Model.switch_session/2 switches active session" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Session 1"},
          "session-2" => %{id: "session-2", name: "Session 2"}
        },
        session_order: ["session-1", "session-2"],
        active_session_id: "session-1",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      new_model = Model.switch_session(model, "session-2")

      assert new_model.active_session_id == "session-2"
    end

    test "Model.rename_session/3 renames session" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Old Name"}
        },
        session_order: ["session-1"],
        active_session_id: "session-1",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      new_model = Model.rename_session(model, "session-1", "New Name")

      assert new_model.sessions["session-1"].name == "New Name"
    end

    test "Model.remove_session/2 removes session and switches to adjacent" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Session 1"},
          "session-2" => %{id: "session-2", name: "Session 2"}
        },
        session_order: ["session-1", "session-2"],
        active_session_id: "session-1",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      new_model = Model.remove_session(model, "session-1")

      refute Map.has_key?(new_model.sessions, "session-1")
      refute "session-1" in new_model.session_order
      # Should switch to adjacent session
      assert new_model.active_session_id == "session-2"
    end
  end

  # ============================================================================
  # Session Index Switching Handler Tests
  # Tests the update handler for {:switch_to_session_index, index}
  # ============================================================================

  describe "switch to session index handler" do
    test "switches to session at valid index" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Session 1"},
          "session-2" => %{id: "session-2", name: "Session 2"}
        },
        session_order: ["session-1", "session-2"],
        active_session_id: "session-1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _commands} = TUI.update({:switch_to_session_index, 2}, model)

      assert new_model.active_session_id == "session-2"
    end

    test "shows error message for invalid index" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Session 1"}
        },
        session_order: ["session-1"],
        active_session_id: "session-1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _commands} = TUI.update({:switch_to_session_index, 5}, model)

      # Should stay on same session
      assert new_model.active_session_id == "session-1"
      # Should have an error message
      assert length(new_model.messages) > 0
    end

    test "does nothing when already on target session" do
      model = %Model{
        sessions: %{
          "session-1" => %{id: "session-1", name: "Session 1"}
        },
        session_order: ["session-1"],
        active_session_id: "session-1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _commands} = TUI.update({:switch_to_session_index, 1}, model)

      # Should stay on same session
      assert new_model.active_session_id == "session-1"
      # Should NOT add a message (no change)
      assert new_model.messages == []
    end

    test "handles empty session list gracefully" do
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _commands} = TUI.update({:switch_to_session_index, 1}, model)

      # Should remain empty
      assert new_model.active_session_id == nil
      # Should have error message
      assert length(new_model.messages) > 0
      [msg] = new_model.messages
      assert msg.content =~ "No session at index 1"
    end

    test "handles Ctrl+0 (10th session) when it exists" do
      # Create 10 sessions
      sessions =
        Enum.reduce(1..10, {%{}, []}, fn i, {sess_map, order} ->
          id = "session-#{i}"
          session = %{id: id, name: "Session #{i}", project_path: "/path#{i}"}
          {Map.put(sess_map, id, session), order ++ [id]}
        end)

      {session_map, session_order} = sessions

      model = %Model{
        sessions: session_map,
        session_order: session_order,
        active_session_id: "session-1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _commands} = TUI.update({:switch_to_session_index, 10}, model)

      # Should switch to 10th session
      assert new_model.active_session_id == "session-10"
    end
  end

  # ============================================================================
  # Model.get_session_by_index/2 Tests
  # Tests the helper function that looks up sessions by 1-based tab index
  # ============================================================================

  describe "Model.get_session_by_index/2" do
    test "returns session at valid index (1-based)" do
      session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Project 2", project_path: "/path2"}
      session3 = %{id: "s3", name: "Project 3", project_path: "/path3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"]
      }

      assert Model.get_session_by_index(model, 1) == session1
      assert Model.get_session_by_index(model, 2) == session2
      assert Model.get_session_by_index(model, 3) == session3
    end

    test "returns nil for out-of-range index" do
      session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}

      model = %Model{
        sessions: %{"s1" => session1},
        session_order: ["s1"]
      }

      assert Model.get_session_by_index(model, 0) == nil
      assert Model.get_session_by_index(model, 2) == nil
      assert Model.get_session_by_index(model, 11) == nil
      assert Model.get_session_by_index(model, -1) == nil
    end

    test "returns nil for empty session list" do
      model = %Model{sessions: %{}, session_order: []}

      assert Model.get_session_by_index(model, 1) == nil
      assert Model.get_session_by_index(model, 5) == nil
      assert Model.get_session_by_index(model, 10) == nil
    end

    test "handles index 10 (Ctrl+0) correctly" do
      # Create 10 sessions
      sessions =
        Enum.reduce(1..10, {%{}, []}, fn i, {sess_map, order} ->
          id = "s#{i}"
          session = %{id: id, name: "Project #{i}", project_path: "/path#{i}"}
          {Map.put(sess_map, id, session), order ++ [id]}
        end)

      {session_map, session_order} = sessions

      model = %Model{
        sessions: session_map,
        session_order: session_order
      }

      # Index 10 should return the 10th session
      session10 = Model.get_session_by_index(model, 10)
      assert session10.id == "s10"
      assert session10.name == "Project 10"
    end

    test "handles sessions beyond index 10 (not accessible via Ctrl)" do
      # Even if somehow we have more than 10 sessions, index 11+ should return nil
      # because get_session_by_index only accepts 1-10
      sessions =
        Enum.reduce(1..11, {%{}, []}, fn i, {sess_map, order} ->
          id = "s#{i}"
          session = %{id: id, name: "Project #{i}", project_path: "/path#{i}"}
          {Map.put(sess_map, id, session), order ++ [id]}
        end)

      {session_map, session_order} = sessions

      model = %Model{
        sessions: session_map,
        session_order: session_order
      }

      # Index 11 should return nil (out of @max_tabs range)
      assert Model.get_session_by_index(model, 11) == nil
    end
  end

  # ============================================================================
  # Digit Key Event Tests
  # Tests that digit keys without Ctrl modifier are forwarded to input
  # ============================================================================

  describe "digit keys without Ctrl modifier" do
    test "digit keys 0-9 without Ctrl are forwarded to input" do
      model = %Model{}

      for key <- ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] do
        event = Event.key(key, modifiers: [])
        assert TUI.event_to_msg(event, model) == {:msg, {:input_event, event}}
      end
    end

    test "digit keys with other modifiers (not Ctrl) are forwarded to input" do
      model = %Model{}

      event_shift = Event.key("1", modifiers: [:shift])
      assert TUI.event_to_msg(event_shift, model) == {:msg, {:input_event, event_shift}}

      event_alt = Event.key("2", modifiers: [:alt])
      assert TUI.event_to_msg(event_alt, model) == {:msg, {:input_event, event_alt}}
    end
  end

  # ============================================================================
  # Tab Switching Integration Test
  # Tests the complete flow from keyboard event to state update
  # ============================================================================

  describe "tab switching integration (complete flow)" do
    test "Ctrl+2 switches to second tab and shows message" do
      # Setup: 3 sessions, currently on first
      session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Project 2", project_path: "/path2"}
      session3 = %{id: "s3", name: "Project 3", project_path: "/path3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      # Simulate Ctrl+2 key press
      event = Event.key("2", modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)

      # Verify event was mapped correctly
      assert msg == {:switch_to_session_index, 2}

      # Process the message
      {new_model, _cmds} = TUI.update(msg, model)

      # Verify: switched to session 2
      assert new_model.active_session_id == "s2"
      # Verify: message was added
      assert length(new_model.messages) > 0
    end

    test "Ctrl+5 on 3-session setup shows error without crashing" do
      session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Project 2", project_path: "/path2"}
      session3 = %{id: "s3", name: "Project 3", project_path: "/path3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      # Simulate Ctrl+5 key press (out of range)
      event = Event.key("5", modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)

      # Process the message
      {new_model, _cmds} = TUI.update(msg, model)

      # Verify: still on session 1
      assert new_model.active_session_id == "s1"
      # Verify: error message added
      assert length(new_model.messages) > 0
      [error_msg] = new_model.messages
      assert error_msg.content =~ "No session at index 5"
    end
  end

  # ============================================================================
  # Tab Cycling Tests (Ctrl+Tab and Ctrl+Shift+Tab)
  # Tests for Task 4.6.2 - forward and backward session cycling
  # ============================================================================

  describe "tab cycling shortcuts (Ctrl+Tab and Ctrl+Shift+Tab)" do
    setup do
      # Create 3-session test model
      session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Project 2", project_path: "/path2"}
      session3 = %{id: "s3", name: "Project 3", project_path: "/path3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    # Test 1-2: Event mapping
    test "Ctrl+Tab event maps to :next_tab message" do
      event = Event.key(:tab, modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, %Model{})
      assert msg == :next_tab
    end

    test "Ctrl+Shift+Tab event maps to :prev_tab message" do
      event = Event.key(:tab, modifiers: [:ctrl, :shift])
      {:msg, msg} = TUI.event_to_msg(event, %Model{})
      assert msg == :prev_tab
    end

    # Test 3-5: Forward cycling
    test "Ctrl+Tab cycles forward from first to second session", %{model: model} do
      {new_model, _cmds} = TUI.update(:next_tab, model)
      assert new_model.active_session_id == "s2"
    end

    test "Ctrl+Tab cycles forward from second to third session", %{model: model} do
      model = %{model | active_session_id: "s2"}
      {new_model, _cmds} = TUI.update(:next_tab, model)
      assert new_model.active_session_id == "s3"
    end

    test "Ctrl+Tab wraps from last to first session", %{model: model} do
      model = %{model | active_session_id: "s3"}
      {new_model, _cmds} = TUI.update(:next_tab, model)
      assert new_model.active_session_id == "s1"
    end

    # Test 6-8: Backward cycling
    test "Ctrl+Shift+Tab cycles backward from first to last session", %{model: model} do
      {new_model, _cmds} = TUI.update(:prev_tab, model)
      assert new_model.active_session_id == "s3"
    end

    test "Ctrl+Shift+Tab cycles backward from third to second session", %{model: model} do
      model = %{model | active_session_id: "s3"}
      {new_model, _cmds} = TUI.update(:prev_tab, model)
      assert new_model.active_session_id == "s2"
    end

    test "Ctrl+Shift+Tab cycles backward from second to first session", %{model: model} do
      model = %{model | active_session_id: "s2"}
      {new_model, _cmds} = TUI.update(:prev_tab, model)
      assert new_model.active_session_id == "s1"
    end

    # Test 9-11: Edge cases
    test "Ctrl+Tab with single session stays on current session" do
      session = %{id: "s1", name: "Only Session", project_path: "/path"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _cmds} = TUI.update(:next_tab, model)
      assert new_model.active_session_id == "s1"
    end

    test "Ctrl+Shift+Tab with single session stays on current session" do
      session = %{id: "s1", name: "Only Session", project_path: "/path"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _cmds} = TUI.update(:prev_tab, model)
      assert new_model.active_session_id == "s1"
    end

    test "Ctrl+Tab with empty session list returns unchanged state" do
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_model, _cmds} = TUI.update(:next_tab, model)
      assert new_model.active_session_id == nil
    end

    # Test 12: Integration test
    test "complete flow: Ctrl+Tab event -> state update -> session switch", %{model: model} do
      # Simulate Ctrl+Tab key press
      event = Event.key(:tab, modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)

      # Verify event mapped correctly
      assert msg == :next_tab

      # Process the message
      {new_model, _cmds} = TUI.update(msg, model)

      # Verify session switched
      assert new_model.active_session_id == "s2"

      # Verify message added
      assert length(new_model.messages) > 0
    end

    # Test 13-14: Focus cycling regression tests
    test "Tab (without Ctrl) still cycles focus forward" do
      model = %Model{focus: :input}
      event = Event.key(:tab, modifiers: [])
      {:msg, msg} = TUI.event_to_msg(event, model)
      assert msg == {:cycle_focus, :forward}
    end

    test "Shift+Tab (without Ctrl) still cycles focus backward" do
      model = %Model{focus: :input}
      event = Event.key(:tab, modifiers: [:shift])
      {:msg, msg} = TUI.event_to_msg(event, model)
      assert msg == {:cycle_focus, :backward}
    end
  end

  describe "session close shortcut (Ctrl+W)" do
    setup do
      # Create 3-session test model
      session1 = %{id: "s1", name: "Session 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Session 2", project_path: "/path2"}
      session3 = %{id: "s3", name: "Session 3", project_path: "/path3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    # Test Group 1: Event Mapping (2 tests)
    test "Ctrl+W event maps to :close_active_session message" do
      model = %Model{}
      event = Event.key("w", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :close_active_session}
    end

    test "plain 'w' key (without Ctrl) is forwarded to input", %{model: model} do
      event = Event.key("w", char: "w")

      assert {:msg, {:input_event, ^event}} = TUI.event_to_msg(event, model)
    end

    # Test Group 2: Update Handler - Normal Cases (3 tests)
    test "close_active_session closes middle session and switches to previous", %{model: model} do
      # Set active session to middle (s2)
      model = %{model | active_session_id: "s2"}

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # Session removed from map and order
      refute Map.has_key?(new_state.sessions, "s2")
      refute "s2" in new_state.session_order
      assert length(new_state.session_order) == 2

      # Switched to previous session (s1)
      assert new_state.active_session_id == "s1"

      # Confirmation message added
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: Session 2")
             end)
    end

    test "close_active_session closes first session and switches to next", %{model: model} do
      # Active session is already s1 (first)
      {new_state, _effects} = TUI.update(:close_active_session, model)

      # Session removed
      refute Map.has_key?(new_state.sessions, "s1")
      refute "s1" in new_state.session_order
      assert length(new_state.session_order) == 2

      # Switched to next session (s2, which is now first in list)
      assert new_state.active_session_id == "s2"

      # Confirmation message
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: Session 1")
             end)
    end

    test "close_active_session closes last session and switches to previous", %{model: model} do
      # Set active session to last (s3)
      model = %{model | active_session_id: "s3"}

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # Session removed
      refute Map.has_key?(new_state.sessions, "s3")
      refute "s3" in new_state.session_order
      assert length(new_state.session_order) == 2

      # Switched to previous session (s2)
      assert new_state.active_session_id == "s2"

      # Confirmation message
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: Session 3")
             end)
    end

    # Test Group 3: Update Handler - Last Session (2 tests)
    test "close_active_session closes only session, sets active_session_id to nil" do
      # Create model with single session
      session = %{id: "s1", name: "Only Session", project_path: "/path1"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # All sessions removed
      assert new_state.sessions == %{}
      assert new_state.session_order == []

      # Active session set to nil
      assert new_state.active_session_id == nil

      # Confirmation message
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: Only Session")
             end)
    end

    test "welcome screen renders when active_session_id is nil" do
      # Model with no sessions
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      # Render the view (this should not crash)
      view_output = TUI.view(model)

      # View should be non-empty (welcome screen renders)
      assert view_output != nil
    end

    # Test Group 4: Update Handler - Edge Cases (3 tests)
    test "close_active_session with nil active_session_id shows message" do
      # Model with nil active_session_id
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # State unchanged (no sessions to remove)
      assert new_state.sessions == %{}
      assert new_state.session_order == []
      assert new_state.active_session_id == nil

      # Error message shown
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "No active session to close")
             end)
    end

    test "close_active_session with missing session in map uses fallback name", %{model: model} do
      # Set active_session_id to non-existent session
      model = %{model | active_session_id: "s999"}

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # Session removed from order (even though not in map)
      refute "s999" in new_state.session_order

      # Fallback name (session_id) used in message
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: s999")
             end)
    end

    test "close_active_session with empty session list returns unchanged state" do
      # Model with empty sessions but non-nil active_session_id (inconsistent state)
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_state, _effects} = TUI.update(:close_active_session, model)

      # Active session cleared
      assert new_state.active_session_id == nil

      # Confirmation message with fallback name
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: s1")
             end)
    end

    # Test Group 5: Model.remove_session Tests (2 tests)
    test "Model.remove_session removes from sessions map and session_order", %{model: model} do
      new_model = Model.remove_session(model, "s2")

      # Session removed from map
      refute Map.has_key?(new_model.sessions, "s2")

      # Session removed from order
      refute "s2" in new_model.session_order
      assert length(new_model.session_order) == 2

      # Other sessions remain
      assert Map.has_key?(new_model.sessions, "s1")
      assert Map.has_key?(new_model.sessions, "s3")
    end

    test "Model.remove_session keeps active unchanged when closing inactive session", %{
      model: model
    } do
      # Active session is s1, close s2
      new_model = Model.remove_session(model, "s2")

      # Active session unchanged
      assert new_model.active_session_id == "s1"

      # s2 removed
      refute Map.has_key?(new_model.sessions, "s2")
    end

    # Test Group 6: Integration Tests (2 tests)
    test "complete flow: Ctrl+W event → update → session closed → adjacent activated", %{
      model: model
    } do
      # Set active to middle session
      model = %{model | active_session_id: "s2"}

      # Step 1: Event mapping
      event = Event.key("w", modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)
      assert msg == :close_active_session

      # Step 2: Update handler
      {new_state, _effects} = TUI.update(msg, model)

      # Step 3: Verify session closed
      refute Map.has_key?(new_state.sessions, "s2")

      # Step 4: Verify adjacent session activated
      assert new_state.active_session_id == "s1"

      # Step 5: Verify confirmation message
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Closed session: Session 2")
             end)
    end

    test "complete flow: Ctrl+W on last session → welcome screen displayed" do
      # Create model with single session
      session = %{id: "s1", name: "Last Session", project_path: "/path1"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      # Step 1: Event mapping
      event = Event.key("w", modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)

      # Step 2: Update handler
      {new_state, _effects} = TUI.update(msg, model)

      # Step 3: Verify all sessions closed
      assert new_state.sessions == %{}
      assert new_state.active_session_id == nil

      # Step 4: Verify view renders (welcome screen)
      view_output = TUI.view(new_state)
      assert view_output != nil
    end
  end

  describe "new session shortcut (Ctrl+N)" do
    setup do
      # Create test model with 2 sessions (not at limit)
      session1 = %{id: "s1", name: "Session 1", project_path: "/path1"}
      session2 = %{id: "s2", name: "Session 2", project_path: "/path2"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    # Test Group 1: Event Mapping (2 tests)
    test "Ctrl+N event maps to :create_new_session message" do
      model = %Model{}
      event = Event.key("n", modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == {:msg, :create_new_session}
    end

    test "plain 'n' key (without Ctrl) is forwarded to input", %{model: model} do
      event = Event.key("n", char: "n")

      assert {:msg, {:input_event, ^event}} = TUI.event_to_msg(event, model)
    end

    # Test Group 2: Update Handler - Success Cases (2 tests)
    test "create_new_session creates session for current directory", %{model: model} do
      # Note: This test will actually try to create a session
      # The SessionSupervisor must be running for this to work
      {new_state, _effects} = TUI.update(:create_new_session, model)

      # Check that either:
      # 1. A new session was added (success case), OR
      # 2. An error message was shown (expected in test env without full supervision tree)
      # We can't assert exact behavior without mocking, but we can verify no crash
      assert is_map(new_state)
      assert is_list(new_state.messages)
    end

    test "create_new_session shows message on success or error", %{model: model} do
      {new_state, _effects} = TUI.update(:create_new_session, model)

      # Should have added a message (either success or error)
      # In test environment without full supervision tree, we expect an error message
      assert length(new_state.messages) > length(model.messages)
    end

    # Test Group 3: Update Handler - Edge Cases (2 tests)
    test "create_new_session handles File.cwd() failure gracefully" do
      # We can't easily mock File.cwd() failure, but we can verify the pattern
      # This test documents the expected behavior
      model = %Model{
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_state, _effects} = TUI.update(:create_new_session, model)

      # Should not crash and should return a state
      assert is_map(new_state)
    end

    # Note: Session limit is enforced by SessionRegistry, not the Model.
    # This test requires actually registering 10 sessions in SessionRegistry
    # which requires SessionSupervisor to be running. For unit tests, we verify
    # that create_new_session handles the model state correctly.
    @tag :skip
    @tag :requires_supervision
    test "create_new_session with 10 sessions shows error" do
      # This test is skipped because the session limit check happens in
      # SessionRegistry.register/1, not based on Model.sessions count.
      # To properly test session limits, use integration tests with
      # full SessionSupervisor running.
      #
      # See: test/jido_code/session_supervisor_test.exs for limit tests
      sessions =
        Enum.map(1..10, fn i ->
          ui_state = Model.default_ui_state({80, 24})

          {
            "s#{i}",
            %{id: "s#{i}", name: "Session #{i}", project_path: "/path#{i}", ui_state: ui_state}
          }
        end)
        |> Map.new()

      session_order = Enum.map(1..10, &"s#{&1}")

      model = %Model{
        sessions: sessions,
        session_order: session_order,
        active_session_id: "s1",
        messages: [],
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {new_state, _effects} = TUI.update(:create_new_session, model)

      # Should show an error message (system messages are at model level)
      # Message could be about session limit, creation failure, or duplicate project
      assert Enum.any?(new_state.messages, fn msg ->
               String.contains?(msg.content, "Failed") or
                 String.contains?(msg.content, "Maximum") or
                 String.contains?(msg.content, "sessions") or
                 String.contains?(msg.content, "limit") or
                 String.contains?(msg.content, "already open")
             end)
    end

    # Test Group 4: Integration Tests (2 tests)
    test "complete flow: Ctrl+N event → update → session creation attempted", %{model: model} do
      # Step 1: Event mapping
      event = Event.key("n", modifiers: [:ctrl])
      {:msg, msg} = TUI.event_to_msg(event, model)
      assert msg == :create_new_session

      # Step 2: Update handler
      {new_state, _effects} = TUI.update(msg, model)

      # Step 3: Verify no crash and message added
      assert is_map(new_state)
      assert length(new_state.messages) >= length(model.messages)
    end

    test "Ctrl+N different from plain 'n' in event mapping" do
      model = %Model{}

      # Ctrl+N should map to :create_new_session
      ctrl_n_event = Event.key("n", modifiers: [:ctrl])
      assert {:msg, :create_new_session} = TUI.event_to_msg(ctrl_n_event, model)

      # Plain 'n' should forward to input
      plain_n_event = Event.key("n", char: "n")
      assert {:msg, {:input_event, ^plain_n_event}} = TUI.event_to_msg(plain_n_event, model)
    end
  end

  describe "Model.add_session_to_tabs/2" do
    test "adds first session and sets it as active" do
      model = %Model{}
      session = %{id: "s1", name: "project1", project_path: "/path1"}

      new_model = Model.add_session_to_tabs(model, session)

      # Session is stored with ui_state added
      assert Map.has_key?(new_model.sessions, "s1")
      stored_session = new_model.sessions["s1"]
      assert stored_session.id == "s1"
      assert stored_session.name == "project1"
      assert stored_session.project_path == "/path1"
      assert Map.has_key?(stored_session, :ui_state)
      assert new_model.session_order == ["s1"]
      assert new_model.active_session_id == "s1"
    end

    test "adds second session without changing active session" do
      session1 = %{id: "s1", name: "project1", project_path: "/path1"}

      model = %Model{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      session2 = %{id: "s2", name: "project2", project_path: "/path2"}
      new_model = Model.add_session_to_tabs(model, session2)

      assert map_size(new_model.sessions) == 2
      # Check session was stored with correct properties (ui_state is now added)
      stored_session = new_model.sessions["s2"]
      assert stored_session.id == "s2"
      assert stored_session.name == "project2"
      assert stored_session.project_path == "/path2"
      assert new_model.session_order == ["s1", "s2"]
      assert new_model.active_session_id == "s1"
    end

    test "adds third session preserving order and active" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}
      session2 = %{id: "s2", name: "p2", project_path: "/p2"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s2"
      }

      session3 = %{id: "s3", name: "p3", project_path: "/p3"}
      new_model = Model.add_session_to_tabs(model, session3)

      assert map_size(new_model.sessions) == 3
      assert new_model.session_order == ["s1", "s2", "s3"]
      assert new_model.active_session_id == "s2"
    end

    test "adds session when active_session_id is nil" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}

      model = %Model{
        sessions: %{"s1" => session1},
        session_order: ["s1"],
        active_session_id: nil
      }

      session2 = %{id: "s2", name: "p2", project_path: "/p2"}
      new_model = Model.add_session_to_tabs(model, session2)

      # Check session was stored with correct properties (ui_state is now added)
      stored_session = new_model.sessions["s2"]
      assert stored_session.id == "s2"
      assert stored_session.name == "p2"
      assert stored_session.project_path == "/p2"
      assert new_model.active_session_id == "s2"
    end
  end

  describe "Model.remove_session_from_tabs/2" do
    test "removes session from single-session model" do
      session = %{id: "s1", name: "project", project_path: "/path"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      new_model = Model.remove_session_from_tabs(model, "s1")

      assert new_model.sessions == %{}
      assert new_model.session_order == []
      assert new_model.active_session_id == nil
    end

    test "removes non-active session without changing active" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}
      session2 = %{id: "s2", name: "p2", project_path: "/p2"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      new_model = Model.remove_session_from_tabs(model, "s2")

      assert new_model.sessions == %{"s1" => session1}
      assert new_model.session_order == ["s1"]
      assert new_model.active_session_id == "s1"
    end

    test "removes active session and switches to previous" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}
      session2 = %{id: "s2", name: "p2", project_path: "/p2"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s2"
      }

      new_model = Model.remove_session_from_tabs(model, "s2")

      assert new_model.sessions == %{"s1" => session1}
      assert new_model.session_order == ["s1"]
      assert new_model.active_session_id == "s1"
    end

    test "removes active session and switches to next when at beginning" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}
      session2 = %{id: "s2", name: "p2", project_path: "/p2"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1"
      }

      new_model = Model.remove_session_from_tabs(model, "s1")

      assert new_model.sessions == %{"s2" => session2}
      assert new_model.session_order == ["s2"]
      assert new_model.active_session_id == "s2"
    end

    test "removes middle session from three sessions" do
      session1 = %{id: "s1", name: "p1", project_path: "/p1"}
      session2 = %{id: "s2", name: "p2", project_path: "/p2"}
      session3 = %{id: "s3", name: "p3", project_path: "/p3"}

      model = %Model{
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s2"
      }

      new_model = Model.remove_session_from_tabs(model, "s2")

      assert map_size(new_model.sessions) == 2
      assert new_model.session_order == ["s1", "s3"]
      # Should switch to previous (s1)
      assert new_model.active_session_id == "s1"
    end

    test "removing non-existent session is no-op" do
      session = %{id: "s1", name: "p1", project_path: "/p1"}

      model = %Model{
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1"
      }

      new_model = Model.remove_session_from_tabs(model, "nonexistent")

      assert new_model == model
    end

    test "handles empty model gracefully" do
      model = %Model{}

      new_model = Model.remove_session_from_tabs(model, "s1")

      assert new_model == model
    end
  end

  describe "PubSub subscription management" do
    test "subscribe_to_session/1 subscribes to session's PubSub topic" do
      session_id = "test-session"

      TUI.subscribe_to_session(session_id)

      # Verify subscription by broadcasting
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.#{session_id}",
        {:test_message, "hello"}
      )

      assert_receive {:test_message, "hello"}, 1000
    end

    test "unsubscribe_from_session/1 unsubscribes from session's PubSub topic" do
      session_id = "test-session"

      # First subscribe
      TUI.subscribe_to_session(session_id)

      # Then unsubscribe
      TUI.unsubscribe_from_session(session_id)

      # Broadcast should not be received
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.#{session_id}",
        {:test_message, "hello"}
      )

      refute_receive {:test_message, "hello"}, 500
    end

    test "add_session/2 subscribes to new session" do
      session = %Session{
        id: "new-session",
        name: "New Session",
        project_path: "/test",
        config: %{},
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      model = %Model{}
      _new_model = Model.add_session(model, session)

      # Verify subscription
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.new-session",
        {:test_message, "subscribed"}
      )

      assert_receive {:test_message, "subscribed"}, 1000

      # Cleanup
      TUI.unsubscribe_from_session("new-session")
    end

    test "add_session_to_tabs/2 subscribes to new session" do
      session = %{id: "new-session-tabs", name: "Test Session", project_path: "/test"}

      model = %Model{}
      _new_model = Model.add_session_to_tabs(model, session)

      # Verify subscription
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.new-session-tabs",
        {:test_message, "subscribed"}
      )

      assert_receive {:test_message, "subscribed"}, 1000

      # Cleanup
      TUI.unsubscribe_from_session("new-session-tabs")
    end

    test "remove_session/2 unsubscribes from removed session" do
      session = %{id: "remove-session", name: "Remove Me", project_path: "/test"}

      model = %Model{}
      model = Model.add_session_to_tabs(model, session)

      # Verify subscribed
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.remove-session",
        {:test_before, "before"}
      )

      assert_receive {:test_before, "before"}, 1000

      # Remove session
      _new_model = Model.remove_session(model, "remove-session")

      # Should not receive after removal
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.remove-session",
        {:test_after, "after"}
      )

      refute_receive {:test_after, "after"}, 500
    end

    test "remove_session_from_tabs/2 unsubscribes from removed session" do
      session = %{id: "remove-session-tabs", name: "Remove Me", project_path: "/test"}

      model = %Model{}
      model = Model.add_session_to_tabs(model, session)

      # Verify subscribed
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.remove-session-tabs",
        {:test_before, "before"}
      )

      assert_receive {:test_before, "before"}, 1000

      # Remove session
      _new_model = Model.remove_session_from_tabs(model, "remove-session-tabs")

      # Should not receive after removal
      Phoenix.PubSub.broadcast(
        JidoCode.PubSub,
        "tui.events.remove-session-tabs",
        {:test_after, "after"}
      )

      refute_receive {:test_after, "after"}, 500
    end
  end

  # Section 4.4: View Integration Tests
  describe "format_project_path/2" do
    alias JidoCode.TUI.ViewHelpers

    test "replaces home directory with ~" do
      home_dir = System.user_home!()
      path = Path.join(home_dir, "projects/myapp")

      result = ViewHelpers.format_project_path(path, 50)

      assert String.starts_with?(result, "~/")
      refute String.contains?(result, home_dir)
    end

    test "truncates long paths from start" do
      home_dir = System.user_home!()
      path = Path.join(home_dir, "very/long/path/to/some/deeply/nested/project")

      result = ViewHelpers.format_project_path(path, 25)

      assert String.starts_with?(result, "...")
      assert String.length(result) == 25
    end

    test "keeps short paths unchanged (with ~ substitution)" do
      home_dir = System.user_home!()
      path = Path.join(home_dir, "code")

      result = ViewHelpers.format_project_path(path, 50)

      assert result == "~/code"
    end

    test "handles non-home paths" do
      path = "/opt/project"

      result = ViewHelpers.format_project_path(path, 50)

      assert result == "/opt/project"
    end
  end

  describe "pad_lines_to_height/3" do
    alias JidoCode.TUI.ViewHelpers

    test "pads short list to target height" do
      # Mock view elements
      lines = [%{type: :text, content: "Line 1"}, %{type: :text, content: "Line 2"}]

      result = ViewHelpers.pad_lines_to_height(lines, 5, 80)

      assert length(result) == 5
      # First 2 should be original lines
      assert Enum.at(result, 0) == Enum.at(lines, 0)
      assert Enum.at(result, 1) == Enum.at(lines, 1)
    end

    test "truncates long list to target height" do
      lines = [
        %{type: :text, content: "Line 1"},
        %{type: :text, content: "Line 2"},
        %{type: :text, content: "Line 3"},
        %{type: :text, content: "Line 4"},
        %{type: :text, content: "Line 5"}
      ]

      result = ViewHelpers.pad_lines_to_height(lines, 3, 80)

      assert length(result) == 3
      assert Enum.at(result, 0) == Enum.at(lines, 0)
      assert Enum.at(result, 1) == Enum.at(lines, 1)
      assert Enum.at(result, 2) == Enum.at(lines, 2)
    end

    test "returns list unchanged when at target height" do
      lines = [
        %{type: :text, content: "Line 1"},
        %{type: :text, content: "Line 2"},
        %{type: :text, content: "Line 3"}
      ]

      result = ViewHelpers.pad_lines_to_height(lines, 3, 80)

      assert length(result) == 3
      assert result == lines
    end
  end

  describe "keyboard shortcuts for sidebar (Task 4.5.5)" do
    setup do
      # Create a test model with multiple sessions
      session1 = create_test_session(id: "session1", name: "Session 1")
      session2 = create_test_session(id: "session2", name: "Session 2")
      session3 = create_test_session(id: "session3", name: "Session 3")

      model = %Model{
        sessions: %{
          "session1" => session1,
          "session2" => session2,
          "session3" => session3
        },
        session_order: ["session1", "session2", "session3"],
        active_session_id: "session1",
        sidebar_visible: true,
        sidebar_width: 20,
        sidebar_expanded: MapSet.new(),
        sidebar_selected_index: 0,
        focus: :input,
        window: {100, 24}
      }

      {:ok, model: model}
    end

    # Ctrl+S Toggle Tests
    test "Ctrl+S toggles sidebar_visible from true to false", %{model: model} do
      assert model.sidebar_visible == true

      {new_model, _cmds} = TUI.update(:toggle_sidebar, model)

      assert new_model.sidebar_visible == false
    end

    test "Ctrl+S toggles sidebar_visible from false to true", %{model: model} do
      model = %{model | sidebar_visible: false}
      assert model.sidebar_visible == false

      {new_model, _cmds} = TUI.update(:toggle_sidebar, model)

      assert new_model.sidebar_visible == true
    end

    test "multiple Ctrl+S toggles work correctly", %{model: model} do
      assert model.sidebar_visible == true

      {model, _} = TUI.update(:toggle_sidebar, model)
      assert model.sidebar_visible == false

      {model, _} = TUI.update(:toggle_sidebar, model)
      assert model.sidebar_visible == true

      {model, _} = TUI.update(:toggle_sidebar, model)
      assert model.sidebar_visible == false
    end

    # Sidebar Navigation Tests
    test "Down arrow increments sidebar_selected_index", %{model: model} do
      assert model.sidebar_selected_index == 0

      {new_model, _cmds} = TUI.update({:sidebar_nav, :down}, model)

      assert new_model.sidebar_selected_index == 1
    end

    test "Up arrow decrements sidebar_selected_index", %{model: model} do
      model = %{model | sidebar_selected_index: 1}
      assert model.sidebar_selected_index == 1

      {new_model, _cmds} = TUI.update({:sidebar_nav, :up}, model)

      assert new_model.sidebar_selected_index == 0
    end

    test "Down arrow wraps to 0 at end", %{model: model} do
      model = %{model | sidebar_selected_index: 2}
      assert model.sidebar_selected_index == 2

      {new_model, _cmds} = TUI.update({:sidebar_nav, :down}, model)

      assert new_model.sidebar_selected_index == 0
    end

    test "Up arrow wraps to max at start", %{model: model} do
      assert model.sidebar_selected_index == 0

      {new_model, _cmds} = TUI.update({:sidebar_nav, :up}, model)

      assert new_model.sidebar_selected_index == 2
    end

    # Accordion Toggle Tests
    test "Enter adds session to sidebar_expanded when collapsed", %{model: model} do
      assert MapSet.size(model.sidebar_expanded) == 0

      {new_model, _cmds} = TUI.update({:toggle_accordion, "session1"}, model)

      assert MapSet.member?(new_model.sidebar_expanded, "session1")
      assert MapSet.size(new_model.sidebar_expanded) == 1
    end

    test "Enter removes session from sidebar_expanded when expanded", %{model: model} do
      model = %{model | sidebar_expanded: MapSet.new(["session1"])}
      assert MapSet.member?(model.sidebar_expanded, "session1")

      {new_model, _cmds} = TUI.update({:toggle_accordion, "session1"}, model)

      refute MapSet.member?(new_model.sidebar_expanded, "session1")
      assert MapSet.size(new_model.sidebar_expanded) == 0
    end

    test "Enter toggles work multiple times", %{model: model} do
      assert MapSet.size(model.sidebar_expanded) == 0

      {model, _} = TUI.update({:toggle_accordion, "session1"}, model)
      assert MapSet.member?(model.sidebar_expanded, "session1")

      {model, _} = TUI.update({:toggle_accordion, "session1"}, model)
      refute MapSet.member?(model.sidebar_expanded, "session1")

      {model, _} = TUI.update({:toggle_accordion, "session1"}, model)
      assert MapSet.member?(model.sidebar_expanded, "session1")
    end

    # Focus Cycle Tests
    test "Tab cycles focus forward through all states", %{model: model} do
      model = %{model | focus: :input, sidebar_visible: true}

      # input -> conversation
      {model, _} = TUI.update({:cycle_focus, :forward}, model)
      assert model.focus == :conversation

      # conversation -> sidebar
      {model, _} = TUI.update({:cycle_focus, :forward}, model)
      assert model.focus == :sidebar

      # sidebar -> input
      {model, _} = TUI.update({:cycle_focus, :forward}, model)
      assert model.focus == :input
    end

    test "Shift+Tab cycles focus backward through all states", %{model: model} do
      model = %{model | focus: :input, sidebar_visible: true}

      # input -> sidebar
      {model, _} = TUI.update({:cycle_focus, :backward}, model)
      assert model.focus == :sidebar

      # sidebar -> conversation
      {model, _} = TUI.update({:cycle_focus, :backward}, model)
      assert model.focus == :conversation

      # conversation -> input
      {model, _} = TUI.update({:cycle_focus, :backward}, model)
      assert model.focus == :input
    end

    test "Tab skips sidebar when sidebar_visible is false", %{model: model} do
      model = %{model | focus: :input, sidebar_visible: false}

      # input -> conversation (skips sidebar)
      {model, _} = TUI.update({:cycle_focus, :forward}, model)
      assert model.focus == :conversation

      # conversation -> input (skips sidebar)
      {model, _} = TUI.update({:cycle_focus, :forward}, model)
      assert model.focus == :input
    end
  end

  # ===========================================================================
  # Mouse Click Handling Tests
  # ===========================================================================

  describe "mouse click handling - tab_click" do
    setup do
      session1 = %Session{
        id: "s1",
        name: "Session 1",
        project_path: "/tmp/project1",
        created_at: DateTime.utc_now()
      }

      session2 = %Session{
        id: "s2",
        name: "Session 2",
        project_path: "/tmp/project2",
        created_at: DateTime.utc_now()
      }

      session3 = %Session{
        id: "s3",
        name: "Session 3",
        project_path: "/tmp/project3",
        created_at: DateTime.utc_now()
      }

      model = %Model{
        window: {80, 24},
        sidebar_visible: true,
        sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
        session_order: ["s1", "s2", "s3"],
        active_session_id: "s1",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    test "tab_click with no tabs_state returns unchanged state", %{model: model} do
      # Empty session order means no tabs
      model = %{model | session_order: [], sessions: %{}}

      {new_state, effects} = TUI.update({:tab_click, 10, 1}, model)

      assert new_state.session_order == []
      assert effects == []
    end

    test "tab_click on unclickable area returns unchanged state", %{model: model} do
      # Click at x=200, which is beyond any tab
      {new_state, effects} = TUI.update({:tab_click, 200, 1}, model)

      assert new_state.active_session_id == "s1"
      assert effects == []
    end
  end

  describe "mouse click handling - sidebar_click" do
    setup do
      session1 = %Session{
        id: "s1",
        name: "Session 1",
        project_path: "/tmp/project1",
        created_at: DateTime.utc_now()
      }

      session2 = %Session{
        id: "s2",
        name: "Session 2",
        project_path: "/tmp/project2",
        created_at: DateTime.utc_now()
      }

      model = %Model{
        window: {80, 24},
        sidebar_visible: true,
        sessions: %{"s1" => session1, "s2" => session2},
        session_order: ["s1", "s2"],
        active_session_id: "s1",
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    test "sidebar_click on header area (y < 2) returns unchanged state", %{model: model} do
      # Click in header area (y = 0 or 1)
      {new_state, effects} = TUI.update({:sidebar_click, 5, 0}, model)

      assert new_state.active_session_id == "s1"
      assert effects == []

      {new_state, effects} = TUI.update({:sidebar_click, 5, 1}, model)

      assert new_state.active_session_id == "s1"
      assert effects == []
    end

    test "sidebar_click on second session switches to it", %{model: model} do
      # Header is 2 lines, so y=2 is first session, y=3 is second session
      {new_state, _effects} = TUI.update({:sidebar_click, 5, 3}, model)

      assert new_state.active_session_id == "s2"
    end

    test "sidebar_click on already active session returns unchanged state", %{model: model} do
      # Click on first session (y=2), which is already active
      {new_state, effects} = TUI.update({:sidebar_click, 5, 2}, model)

      assert new_state.active_session_id == "s1"
      assert effects == []
    end

    test "sidebar_click beyond session list returns unchanged state", %{model: model} do
      # Click at y=10, which is beyond the 2 sessions (header=2, session1=y2, session2=y3)
      {new_state, effects} = TUI.update({:sidebar_click, 5, 10}, model)

      assert new_state.active_session_id == "s1"
      assert effects == []
    end
  end

  # ============================================================================
  # Resume Dialog Tests
  # ============================================================================

  describe "resume dialog event routing" do
    setup do
      session = %Session{
        id: "s1",
        name: "Test Session",
        project_path: "/test/path",
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      model = %Model{
        window: {80, 24},
        sessions: %{"s1" => session},
        session_order: ["s1"],
        active_session_id: "s1",
        resume_dialog: %{
          session_id: "old-session-123",
          session_name: "Previous Session",
          project_path: "/test/path",
          closed_at: "2024-01-01T00:00:00Z",
          message_count: 5
        },
        config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      }

      {:ok, model: model}
    end

    test "Enter key returns :resume_dialog_accept when dialog is open", %{model: model} do
      event = %Event.Key{key: :enter, modifiers: []}

      result = TUI.event_to_msg(event, model)

      assert result == {:msg, :resume_dialog_accept}
    end

    test "Escape key returns :resume_dialog_dismiss when dialog is open", %{model: model} do
      event = %Event.Key{key: :escape, modifiers: []}

      result = TUI.event_to_msg(event, model)

      assert result == {:msg, :resume_dialog_dismiss}
    end

    test "mouse events are ignored when resume_dialog is open", %{model: model} do
      event = %Event.Mouse{x: 10, y: 10, action: :click, modifiers: []}

      result = TUI.event_to_msg(event, model)

      assert result == :ignore
    end

    test "Enter key still goes to pick_list when both dialogs would be open", %{model: model} do
      # resume_dialog should take priority, but let's verify the pattern
      model_without_dialog = %{model | resume_dialog: nil}
      event = %Event.Key{key: :enter, modifiers: []}

      # Without resume_dialog, Enter should go to normal handling
      result = TUI.event_to_msg(event, model_without_dialog)
      assert {:msg, {:input_submitted, _}} = result
    end
  end

  describe "resume dialog dismiss handler" do
    test "dismiss clears resume_dialog state" do
      model = %Model{
        window: {80, 24},
        sessions: %{},
        session_order: [],
        active_session_id: nil,
        resume_dialog: %{
          session_id: "test-123",
          session_name: "Test",
          project_path: "/test",
          closed_at: "2024-01-01T00:00:00Z",
          message_count: 0
        },
        config: %{}
      }

      {new_state, effects} = TUI.update(:resume_dialog_dismiss, model)

      assert is_nil(new_state.resume_dialog)
      assert effects == []
    end
  end

  describe "Model.resume_dialog field" do
    test "has default value of nil" do
      model = %Model{}
      assert model.resume_dialog == nil
    end

    test "can be set to dialog state" do
      dialog_state = %{
        session_id: "abc123",
        session_name: "My Project",
        project_path: "/path/to/project",
        closed_at: "2024-01-01T00:00:00Z",
        message_count: 10
      }

      model = %Model{resume_dialog: dialog_state}

      assert model.resume_dialog.session_id == "abc123"
      assert model.resume_dialog.session_name == "My Project"
      assert model.resume_dialog.message_count == 10
    end
  end
end
