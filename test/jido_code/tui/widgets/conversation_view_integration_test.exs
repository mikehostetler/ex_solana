defmodule JidoCode.TUI.Widgets.ConversationViewIntegrationTest do
  @moduledoc """
  Integration tests for ConversationView widget.

  These tests validate end-to-end functionality including:
  - Conversation display flow
  - Scrolling integration
  - Message truncation
  - Streaming support
  - Clipboard integration
  - Resize handling
  - TUI lifecycle integration
  """

  use ExUnit.Case, async: true

  alias JidoCode.TUI.Widgets.ConversationView
  alias TermUI.Event

  # Helper to create a test message
  defp create_message(id, role, content) do
    %{
      id: id,
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  # Helper to create messages list
  defp create_messages(count, role \\ :user) do
    Enum.map(1..count, fn i ->
      create_message("msg_#{i}", role, "Message #{i} content")
    end)
  end

  # Helper to create a long message (for truncation tests)
  defp create_long_message(id, role, line_count) do
    content = Enum.map_join(1..line_count, "\n", fn i -> "Line #{i} of the message" end)
    create_message(id, role, content)
  end

  # Helper to initialize ConversationView with defaults
  defp init_conversation_view(opts \\ []) do
    messages = Keyword.get(opts, :messages, [])
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 20)
    max_collapsed_lines = Keyword.get(opts, :max_collapsed_lines, 15)

    props =
      ConversationView.new(
        messages: messages,
        viewport_width: width,
        viewport_height: height,
        max_collapsed_lines: max_collapsed_lines
      )

    {:ok, state} = ConversationView.init(props)
    state
  end

  # ============================================================================
  # Conversation Display Flow Tests
  # ============================================================================

  describe "conversation display flow" do
    test "empty conversation returns valid empty state" do
      state = init_conversation_view(messages: [])

      assert state.messages == []
      assert state.total_lines == 0
      assert state.scroll_offset == 0
    end

    test "single message displays with correct structure" do
      message = create_message("1", :user, "Hello, world!")
      state = init_conversation_view(messages: [message])

      assert length(state.messages) == 1
      assert hd(state.messages).content == "Hello, world!"
      assert hd(state.messages).role == :user
      assert state.total_lines > 0
    end

    test "multiple messages display in correct order" do
      messages = [
        create_message("1", :user, "First message"),
        create_message("2", :assistant, "Second message"),
        create_message("3", :user, "Third message")
      ]

      state = init_conversation_view(messages: messages)

      assert length(state.messages) == 3
      assert Enum.at(state.messages, 0).content == "First message"
      assert Enum.at(state.messages, 1).content == "Second message"
      assert Enum.at(state.messages, 2).content == "Third message"
    end

    test "user/assistant/system messages have distinct roles" do
      messages = [
        create_message("1", :user, "User message"),
        create_message("2", :assistant, "Assistant message"),
        create_message("3", :system, "System message")
      ]

      state = init_conversation_view(messages: messages)

      roles = Enum.map(state.messages, & &1.role)
      assert roles == [:user, :assistant, :system]
    end

    test "long conversation has correct total_lines for scrolling" do
      # Create 50 messages that will exceed viewport
      messages = create_messages(50)
      state = init_conversation_view(messages: messages, height: 20)

      # Each message has header + content + separator, so total should be > viewport
      assert state.total_lines > state.viewport_height
      # Max scroll should allow scrolling to see all content
      max_scroll = ConversationView.max_scroll_offset(state)
      assert max_scroll > 0
    end
  end

  # ============================================================================
  # Scrolling Integration Tests
  # ============================================================================

  describe "scrolling integration" do
    setup do
      messages = create_messages(50)
      state = init_conversation_view(messages: messages, height: 20)
      # Set input_focused: false so arrow keys control scrolling instead of text input
      state = %{state | input_focused: false}
      {:ok, state: state}
    end

    test "keyboard down arrow scrolls view", %{state: state} do
      event = Event.key(:down)
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 1
    end

    test "keyboard up arrow scrolls view when not at top", %{state: state} do
      # First scroll down
      {:ok, scrolled} = ConversationView.handle_event(Event.key(:down), state)
      {:ok, scrolled} = ConversationView.handle_event(Event.key(:down), scrolled)

      # Then scroll up
      {:ok, new_state} = ConversationView.handle_event(Event.key(:up), scrolled)

      assert new_state.scroll_offset == 1
    end

    test "mouse wheel scroll_down scrolls view", %{state: state} do
      event = %Event.Mouse{action: :scroll_down, x: 10, y: 10}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Default scroll_lines is 3
      assert new_state.scroll_offset == 3
    end

    test "scroll bounds enforced at top", %{state: state} do
      # Try scrolling up from offset 0
      event = Event.key(:up)
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 0
    end

    test "scroll bounds enforced at bottom", %{state: state} do
      max_scroll = ConversationView.max_scroll_offset(state)

      # Scroll to bottom
      state = ConversationView.scroll_to(state, :bottom)
      assert state.scroll_offset == max_scroll

      # Try scrolling past bottom
      {:ok, new_state} = ConversationView.handle_event(Event.key(:down), state)

      assert new_state.scroll_offset == max_scroll
    end

    test "auto-scroll when new message added at bottom" do
      messages = create_messages(30)
      state = init_conversation_view(messages: messages, height: 20)

      # Scroll to bottom
      state = ConversationView.scroll_to(state, :bottom)
      old_offset = state.scroll_offset

      # Add new message
      new_message = create_message("new", :assistant, "New message")
      new_state = ConversationView.add_message(state, new_message)

      # Should have auto-scrolled to keep bottom visible
      assert new_state.scroll_offset >= old_offset
    end
  end

  # ============================================================================
  # Message Truncation Integration Tests
  # ============================================================================

  describe "message truncation integration" do
    test "long message is truncated by default" do
      # Create message with 30 lines (exceeds default 15)
      message = create_long_message("1", :assistant, 30)
      state = init_conversation_view(messages: [message], max_collapsed_lines: 15)

      # Message should not be in expanded set
      refute MapSet.member?(state.expanded, "1")

      # Total lines should be less than full content
      # (truncated to ~15 lines + header + separator + truncation indicator)
      assert state.total_lines < 35
    end

    test "space key expands truncated message" do
      message = create_long_message("1", :assistant, 30)
      state = init_conversation_view(messages: [message], max_collapsed_lines: 15)
      # Set input_focused: false so space key expands message instead of going to text input
      state = %{state | input_focused: false}

      # Focus is on message 0 by default, press space to expand
      event = Event.key(:space)
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert MapSet.member?(new_state.expanded, "1")
    end

    test "expanded message shows full content" do
      message = create_long_message("1", :assistant, 30)
      state = init_conversation_view(messages: [message], max_collapsed_lines: 15)

      truncated_lines = state.total_lines

      # Expand the message
      new_state = ConversationView.toggle_expand(state, "1")

      # Total lines should now be greater (full content shown)
      assert new_state.total_lines > truncated_lines
    end

    test "scroll adjusts after expansion" do
      messages = [
        create_long_message("1", :assistant, 30),
        create_message("2", :user, "Short message")
      ]

      state = init_conversation_view(messages: messages, max_collapsed_lines: 15, height: 20)

      # Scroll to see second message
      state = ConversationView.scroll_to(state, :bottom)

      # Expand first message
      new_state = ConversationView.toggle_expand(state, "1")

      # Max scroll should have increased
      new_max = ConversationView.max_scroll_offset(new_state)
      old_max = ConversationView.max_scroll_offset(state)

      assert new_max > old_max
    end
  end

  # ============================================================================
  # Streaming Integration Tests
  # ============================================================================

  describe "streaming integration" do
    test "streaming message appears immediately" do
      state = init_conversation_view(messages: [])

      {new_state, message_id} = ConversationView.start_streaming(state, :assistant)

      assert new_state.streaming_id == message_id
      assert length(new_state.messages) == 1
      assert hd(new_state.messages).content == ""
    end

    test "streaming chunks append correctly" do
      state = init_conversation_view(messages: [])

      {state, _id} = ConversationView.start_streaming(state, :assistant)
      state = ConversationView.append_chunk(state, "Hello ")
      state = ConversationView.append_chunk(state, "world!")

      assert hd(state.messages).content == "Hello world!"
    end

    test "streaming cursor indicator visible during streaming" do
      state = init_conversation_view(messages: [])

      {state, _id} = ConversationView.start_streaming(state, :assistant)
      state = ConversationView.append_chunk(state, "Hello")

      # streaming_id should be set
      assert state.streaming_id != nil
    end

    test "auto-scroll during streaming when at bottom" do
      messages = create_messages(30)
      state = init_conversation_view(messages: messages, height: 20)

      # Scroll to bottom
      state = ConversationView.scroll_to(state, :bottom)
      old_offset = state.scroll_offset

      # Start streaming
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      # Append chunks that grow the message
      state = ConversationView.append_chunk(state, "Line 1\n")
      state = ConversationView.append_chunk(state, "Line 2\n")
      state = ConversationView.append_chunk(state, "Line 3\n")

      # Should have scrolled to keep content visible
      assert state.scroll_offset >= old_offset
    end

    test "message finalizes on stream end" do
      state = init_conversation_view(messages: [])

      {state, message_id} = ConversationView.start_streaming(state, :assistant)
      state = ConversationView.append_chunk(state, "Final content")
      new_state = ConversationView.end_streaming(state)

      assert new_state.streaming_id == nil
      # Message should still exist with content
      msg = Enum.find(new_state.messages, &(&1.id == message_id))
      assert msg.content == "Final content"
    end
  end

  # ============================================================================
  # Clipboard Integration Tests
  # ============================================================================

  describe "clipboard integration" do
    test "y key triggers copy callback" do
      copied_content = :ets.new(:copied_content, [:set, :public])

      on_copy = fn content ->
        :ets.insert(copied_content, {:content, content})
        :ok
      end

      message = create_message("1", :user, "Copy this content")

      props =
        ConversationView.new(
          messages: [message],
          viewport_width: 80,
          viewport_height: 20,
          on_copy: on_copy
        )

      {:ok, state} = ConversationView.init(props)
      # Set input_focused: false so 'y' key triggers copy instead of going to text input
      state = %{state | input_focused: false}

      # Press 'y' to copy
      event = %Event.Key{char: "y"}
      {:ok, _new_state} = ConversationView.handle_event(event, state)

      # Verify callback was called
      assert [{:content, "Copy this content"}] = :ets.lookup(copied_content, :content)

      :ets.delete(copied_content)
    end

    test "copied content matches focused message" do
      copied_content = :ets.new(:copied_content, [:set, :public])

      on_copy = fn content ->
        :ets.insert(copied_content, {:content, content})
        :ok
      end

      messages = [
        create_message("1", :user, "First message"),
        create_message("2", :assistant, "Second message")
      ]

      props =
        ConversationView.new(
          messages: messages,
          viewport_width: 80,
          viewport_height: 20,
          on_copy: on_copy
        )

      {:ok, state} = ConversationView.init(props)
      # Set input_focused: false so 'y' key triggers copy instead of going to text input
      state = %{state | input_focused: false}

      # Move focus to second message (Ctrl+Down)
      event = %Event.Key{key: :down, modifiers: [:ctrl]}
      {:ok, state} = ConversationView.handle_event(event, state)

      # Press 'y' to copy
      event = %Event.Key{char: "y"}
      {:ok, _new_state} = ConversationView.handle_event(event, state)

      # Should have copied second message
      assert [{:content, "Second message"}] = :ets.lookup(copied_content, :content)

      :ets.delete(copied_content)
    end

    test "copy works with multiline messages" do
      copied_content = :ets.new(:copied_content, [:set, :public])

      on_copy = fn content ->
        :ets.insert(copied_content, {:content, content})
        :ok
      end

      multiline_content = "Line 1\nLine 2\nLine 3"
      message = create_message("1", :user, multiline_content)

      props =
        ConversationView.new(
          messages: [message],
          viewport_width: 80,
          viewport_height: 20,
          on_copy: on_copy
        )

      {:ok, state} = ConversationView.init(props)
      # Set input_focused: false so 'y' key triggers copy instead of going to text input
      state = %{state | input_focused: false}

      # Press 'y' to copy
      event = %Event.Key{char: "y"}
      {:ok, _new_state} = ConversationView.handle_event(event, state)

      # Should have copied full multiline content
      assert [{:content, ^multiline_content}] = :ets.lookup(copied_content, :content)

      :ets.delete(copied_content)
    end
  end

  # ============================================================================
  # Resize Integration Tests
  # ============================================================================

  describe "resize integration" do
    test "widget adapts to terminal width change" do
      messages = create_messages(10)
      state = init_conversation_view(messages: messages, width: 80, height: 20)

      old_width = state.viewport_width

      # Resize to narrower width
      new_state = ConversationView.set_viewport_size(state, 60, 20)

      assert new_state.viewport_width == 60
      assert new_state.viewport_width < old_width
    end

    test "widget adapts to terminal height change" do
      messages = create_messages(10)
      state = init_conversation_view(messages: messages, width: 80, height: 20)

      old_height = state.viewport_height

      # Resize to taller height
      new_state = ConversationView.set_viewport_size(state, 80, 30)

      assert new_state.viewport_height == 30
      assert new_state.viewport_height > old_height
    end

    test "scroll position preserved on resize when within bounds" do
      messages = create_messages(50)
      state = init_conversation_view(messages: messages, width: 80, height: 20)

      # Scroll down a bit
      state = ConversationView.scroll_by(state, 10)
      old_offset = state.scroll_offset

      # Resize height slightly (should preserve position)
      new_state = ConversationView.set_viewport_size(state, 80, 25)

      # Offset should be preserved (or clamped if necessary)
      assert new_state.scroll_offset <= old_offset
    end

    test "text rewrapping on width change affects total_lines" do
      # Create message with long content that will wrap differently at different widths
      long_content = String.duplicate("word ", 50)
      message = create_message("1", :user, long_content)

      state = init_conversation_view(messages: [message], width: 80, height: 20)
      old_total = state.total_lines

      # Resize to narrower width - should have more wrapped lines
      new_state = ConversationView.set_viewport_size(state, 40, 20)

      # Narrower width should result in more lines due to wrapping
      assert new_state.total_lines > old_total
    end
  end

  # ============================================================================
  # TUI Lifecycle Integration Tests
  # ============================================================================

  describe "TUI lifecycle integration" do
    test "ConversationView initializes with correct defaults" do
      state = init_conversation_view()

      assert state.viewport_width == 80
      assert state.viewport_height == 20
      assert state.scroll_offset == 0
      assert state.messages == []
      assert state.expanded == MapSet.new()
      assert state.streaming_id == nil
    end

    test "messages sync correctly via add_message" do
      state = init_conversation_view(messages: [])

      # Add messages one by one (simulating TUI message sync)
      msg1 = create_message("1", :user, "Hello")
      state = ConversationView.add_message(state, msg1)

      msg2 = create_message("2", :assistant, "Hi there!")
      state = ConversationView.add_message(state, msg2)

      assert length(state.messages) == 2
      assert Enum.at(state.messages, 0).content == "Hello"
      assert Enum.at(state.messages, 1).content == "Hi there!"
    end

    test "event routing returns :ok tuple for handled events" do
      state = init_conversation_view(messages: create_messages(10))

      # Scroll event should be handled
      result = ConversationView.handle_event(Event.key(:down), state)
      assert {:ok, _new_state} = result

      # Unknown event should also return :ok (no-op)
      result = ConversationView.handle_event(Event.key(:f12), state)
      assert {:ok, _new_state} = result
    end

    test "render returns valid render node" do
      messages = create_messages(5)
      state = init_conversation_view(messages: messages)

      # Create an area for rendering
      area = %{x: 0, y: 0, width: 80, height: 20}

      # Render should return a valid render structure (TermUI RenderNode)
      rendered = ConversationView.render(state, area)

      # TermUI render nodes are %TermUI.Component.RenderNode{} structs
      assert %TermUI.Component.RenderNode{type: :stack} = rendered
      assert is_list(rendered.children)
    end
  end
end
