defmodule JidoCode.TUI.Widgets.ConversationViewTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Widgets.ConversationView

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp make_message(id, role, content) do
    %{
      id: id,
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  defp init_state(opts \\ []) do
    props = ConversationView.new(opts)
    {:ok, state} = ConversationView.init(props)
    state
  end

  # Helper to extract content stack from render result
  # render/2 returns: stack(:horizontal, [box([content_stack]), scrollbar]) for messages
  # or just text node for empty messages
  defp get_content_stack(%TermUI.Component.RenderNode{
         type: :stack,
         direction: :horizontal,
         children: [content_box | _]
       }) do
    # Content is wrapped in a box, extract the inner content_stack
    case content_box do
      %TermUI.Component.RenderNode{type: :box, children: [content_stack | _]} ->
        content_stack

      _ ->
        content_box
    end
  end

  defp get_content_stack(result), do: result

  # For backwards compatibility - messages_area is just the result itself now
  defp get_messages_area(result), do: result

  # Helper to flatten nested stacks into a list of text nodes
  defp flatten_nodes(%TermUI.Component.RenderNode{type: :stack, children: children}) do
    Enum.flat_map(children, &flatten_nodes/1)
  end

  defp flatten_nodes(%TermUI.Component.RenderNode{type: :box, children: children}) do
    Enum.flat_map(children, &flatten_nodes/1)
  end

  defp flatten_nodes(%TermUI.Component.RenderNode{type: :text} = node), do: [node]
  defp flatten_nodes(_), do: []

  # ============================================================================
  # new/1 Tests
  # ============================================================================

  describe "new/1" do
    test "returns valid props with defaults" do
      props = ConversationView.new()

      assert props.messages == []
      assert props.max_collapsed_lines == 15
      assert props.show_timestamps == true
      assert props.scrollbar_width == 1
      assert props.indent == 2
      assert props.scroll_lines == 3
      assert is_map(props.role_styles)
      assert props.on_copy == nil
    end

    test "with custom messages" do
      messages = [make_message("1", :user, "Hello")]
      props = ConversationView.new(messages: messages)

      assert props.messages == messages
    end

    test "with custom max_collapsed_lines" do
      props = ConversationView.new(max_collapsed_lines: 20)

      assert props.max_collapsed_lines == 20
    end

    test "with show_timestamps disabled" do
      props = ConversationView.new(show_timestamps: false)

      assert props.show_timestamps == false
    end

    test "with custom scrollbar_width" do
      props = ConversationView.new(scrollbar_width: 3)

      assert props.scrollbar_width == 3
    end

    test "with custom indent" do
      props = ConversationView.new(indent: 4)

      assert props.indent == 4
    end

    test "with custom scroll_lines" do
      props = ConversationView.new(scroll_lines: 5)

      assert props.scroll_lines == 5
    end

    test "with custom role_styles" do
      custom_styles = %{
        user: %{name: "Me", color: :blue},
        assistant: %{name: "Bot", color: :green},
        system: %{name: "Sys", color: :red}
      }

      props = ConversationView.new(role_styles: custom_styles)

      assert props.role_styles == custom_styles
    end

    test "with on_copy callback" do
      callback = fn _text -> :ok end
      props = ConversationView.new(on_copy: callback)

      assert props.on_copy == callback
    end
  end

  # ============================================================================
  # init/1 Tests
  # ============================================================================

  describe "init/1" do
    test "creates valid state from props" do
      state = init_state()

      assert state.messages == []
      assert state.scroll_offset == 0
      assert state.viewport_height == 20
      assert state.viewport_width == 80
      assert state.expanded == MapSet.new()
      assert state.cursor_message_idx == 0
      assert state.dragging == false
      assert state.streaming_id == nil
    end

    test "initializes with provided messages" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi there!")
      ]

      state = init_state(messages: messages)

      assert state.messages == messages
      assert length(state.messages) == 2
    end

    test "calculates correct total_lines for empty messages" do
      state = init_state()

      assert state.total_lines == 0
    end

    test "calculates correct total_lines for messages" do
      # Each message = 1 header + content lines + 1 separator
      # Short message: 1 header + 1 content + 1 separator = 3 lines
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      # 2 messages * 3 lines each = 6 lines
      assert state.total_lines == 6
    end

    test "preserves config from props" do
      state =
        init_state(
          max_collapsed_lines: 10,
          show_timestamps: false,
          scrollbar_width: 3,
          indent: 4,
          scroll_lines: 5
        )

      assert state.max_collapsed_lines == 10
      assert state.show_timestamps == false
      assert state.scrollbar_width == 3
      assert state.indent == 4
      assert state.scroll_lines == 5
    end
  end

  # ============================================================================
  # add_message/2 Tests
  # ============================================================================

  describe "add_message/2" do
    test "appends message to empty state" do
      state = init_state()
      message = make_message("1", :user, "Hello")

      state = ConversationView.add_message(state, message)

      assert length(state.messages) == 1
      assert hd(state.messages).content == "Hello"
    end

    test "appends message to existing messages" do
      state = init_state(messages: [make_message("1", :user, "First")])
      message = make_message("2", :assistant, "Second")

      state = ConversationView.add_message(state, message)

      assert length(state.messages) == 2
      assert List.last(state.messages).content == "Second"
    end

    test "updates total_lines" do
      state = init_state()
      initial_lines = state.total_lines

      message = make_message("1", :user, "Hello")
      state = ConversationView.add_message(state, message)

      assert state.total_lines > initial_lines
    end

    test "auto-scrolls when at bottom" do
      state = init_state()
      # Start at bottom (scroll_offset 0 with empty messages is at bottom)
      assert ConversationView.at_bottom?(state)

      message = make_message("1", :user, "Hello")
      state = ConversationView.add_message(state, message)

      # Should still be at bottom after adding
      assert ConversationView.at_bottom?(state)
    end
  end

  # ============================================================================
  # set_messages/2 Tests
  # ============================================================================

  describe "set_messages/2" do
    test "replaces all messages" do
      state = init_state(messages: [make_message("1", :user, "Old")])

      new_messages = [
        make_message("2", :user, "New1"),
        make_message("3", :assistant, "New2")
      ]

      state = ConversationView.set_messages(state, new_messages)

      assert length(state.messages) == 2
      assert hd(state.messages).content == "New1"
    end

    test "resets scroll_offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 100}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.scroll_offset == 0
    end

    test "resets cursor_message_idx to 0" do
      state = init_state()
      state = %{state | cursor_message_idx: 5}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.cursor_message_idx == 0
    end

    test "clears expanded set" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2", "3"])}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.expanded == MapSet.new()
    end

    test "recalculates total_lines" do
      state = init_state()

      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "World")
      ]

      state = ConversationView.set_messages(state, messages)

      # Each message = 3 lines, so 2 messages = 6 lines
      assert state.total_lines == 6
    end
  end

  # ============================================================================
  # clear/1 Tests
  # ============================================================================

  describe "clear/1" do
    test "empties messages" do
      state = init_state(messages: [make_message("1", :user, "Test")])

      state = ConversationView.clear(state)

      assert state.messages == []
    end

    test "resets total_lines to 0" do
      state = init_state(messages: [make_message("1", :user, "Test")])

      state = ConversationView.clear(state)

      assert state.total_lines == 0
    end

    test "resets scroll_offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 50}

      state = ConversationView.clear(state)

      assert state.scroll_offset == 0
    end

    test "resets cursor_message_idx to 0" do
      state = init_state()
      state = %{state | cursor_message_idx: 5}

      state = ConversationView.clear(state)

      assert state.cursor_message_idx == 0
    end

    test "clears expanded set" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2"])}

      state = ConversationView.clear(state)

      assert state.expanded == MapSet.new()
    end

    test "clears streaming_id" do
      state = init_state()
      state = %{state | streaming_id: "stream-1"}

      state = ConversationView.clear(state)

      assert state.streaming_id == nil
    end
  end

  # ============================================================================
  # append_to_message/3 Tests
  # ============================================================================

  describe "append_to_message/3" do
    test "appends content to correct message" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      state = ConversationView.append_to_message(state, "2", " there!")

      msg = Enum.find(state.messages, &(&1.id == "2"))
      assert msg.content == "Hi there!"
    end

    test "does not modify other messages" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      state = ConversationView.append_to_message(state, "2", " there!")

      msg1 = Enum.find(state.messages, &(&1.id == "1"))
      assert msg1.content == "Hello"
    end

    test "updates total_lines" do
      state = init_state(messages: [make_message("1", :user, "Hi")])
      initial_lines = state.total_lines

      # Add enough content to create new lines
      long_content = String.duplicate("x", 200)
      state = ConversationView.append_to_message(state, "1", long_content)

      assert state.total_lines > initial_lines
    end

    test "no-op for non-existent message id" do
      state = init_state(messages: [make_message("1", :user, "Hello")])

      state = ConversationView.append_to_message(state, "nonexistent", "extra")

      msg = Enum.find(state.messages, &(&1.id == "1"))
      assert msg.content == "Hello"
    end
  end

  # ============================================================================
  # toggle_expand/2 Tests
  # ============================================================================

  describe "toggle_expand/2" do
    test "adds message id to expanded set" do
      state = init_state()

      state = ConversationView.toggle_expand(state, "1")

      assert MapSet.member?(state.expanded, "1")
    end

    test "removes message id from expanded set when already expanded" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1"])}

      state = ConversationView.toggle_expand(state, "1")

      refute MapSet.member?(state.expanded, "1")
    end

    test "recalculates total_lines after toggle" do
      # Create a long message that will be truncated
      long_content = String.duplicate("Line\n", 30)
      messages = [make_message("1", :user, long_content)]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      collapsed_lines = state.total_lines

      state = ConversationView.toggle_expand(state, "1")
      expanded_lines = state.total_lines

      # Expanded should have more lines
      assert expanded_lines > collapsed_lines
    end
  end

  # ============================================================================
  # expand_all/1 and collapse_all/1 Tests
  # ============================================================================

  describe "expand_all/1" do
    test "expands all messages" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)

      state = ConversationView.expand_all(state)

      assert MapSet.member?(state.expanded, "1")
      assert MapSet.member?(state.expanded, "2")
    end
  end

  describe "collapse_all/1" do
    test "collapses all expanded messages" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2", "3"])}

      state = ConversationView.collapse_all(state)

      assert state.expanded == MapSet.new()
    end

    test "clamps scroll_offset when total_lines decreases" do
      long_content = String.duplicate("Line\n", 50)
      messages = [make_message("1", :user, long_content)]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = ConversationView.expand_all(state)
      state = ConversationView.scroll_to(state, :bottom)
      expanded_offset = state.scroll_offset

      state = ConversationView.collapse_all(state)

      # Scroll offset should be clamped to valid range
      assert state.scroll_offset <= ConversationView.max_scroll_offset(state)
      assert state.scroll_offset < expanded_offset
    end
  end

  # ============================================================================
  # scroll_to/2 Tests
  # ============================================================================

  describe "scroll_to/2" do
    test "scrolls to :top sets offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 100}

      state = ConversationView.scroll_to(state, :top)

      assert state.scroll_offset == 0
    end

    test "scrolls to :bottom sets offset to max" do
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_to(state, :bottom)

      assert state.scroll_offset == ConversationView.max_scroll_offset(state)
    end

    test "scrolls to {:message, id} makes message visible" do
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_to(state, {:message, "5"})

      # Message 5 should now be visible (scroll offset adjusted)
      # 0-indexed
      assert state.cursor_message_idx == 4
    end

    test "scroll to non-existent message is no-op" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      original_offset = state.scroll_offset

      state = ConversationView.scroll_to(state, {:message, "nonexistent"})

      assert state.scroll_offset == original_offset
    end
  end

  # ============================================================================
  # scroll_by/2 Tests
  # ============================================================================

  describe "scroll_by/2" do
    test "scrolls down by positive delta" do
      messages =
        Enum.map(1..20, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_by(state, 5)

      assert state.scroll_offset == 5
    end

    test "scrolls up by negative delta" do
      messages =
        Enum.map(1..20, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 10}

      state = ConversationView.scroll_by(state, -3)

      assert state.scroll_offset == 7
    end

    test "clamps to 0 for negative scroll" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      state = %{state | scroll_offset: 2}

      state = ConversationView.scroll_by(state, -100)

      assert state.scroll_offset == 0
    end

    test "clamps to max_scroll_offset for overshooting" do
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}
      max_offset = ConversationView.max_scroll_offset(state)

      state = ConversationView.scroll_by(state, 1000)

      assert state.scroll_offset == max_offset
    end
  end

  # ============================================================================
  # get_selected_text/1 Tests
  # ============================================================================

  describe "get_selected_text/1" do
    test "returns content of focused message" do
      messages = [
        make_message("1", :user, "First message"),
        make_message("2", :assistant, "Second message")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 1}

      text = ConversationView.get_selected_text(state)

      assert text == "Second message"
    end

    test "returns empty string when no messages" do
      state = init_state()

      text = ConversationView.get_selected_text(state)

      assert text == ""
    end

    test "returns empty string for out of bounds cursor" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      state = %{state | cursor_message_idx: 100}

      text = ConversationView.get_selected_text(state)

      assert text == ""
    end
  end

  # ============================================================================
  # Streaming API Tests
  # ============================================================================

  describe "start_streaming/2" do
    test "creates a new message with empty content" do
      state = init_state()

      {state, _id} = ConversationView.start_streaming(state, :assistant)

      assert length(state.messages) == 1
      assert hd(state.messages).content == ""
      assert hd(state.messages).role == :assistant
    end

    test "returns the message id" do
      state = init_state()

      {_state, id} = ConversationView.start_streaming(state, :assistant)

      assert is_binary(id)
      assert String.length(id) > 0
    end

    test "sets streaming_id in state" do
      state = init_state()

      {state, id} = ConversationView.start_streaming(state, :assistant)

      assert state.streaming_id == id
    end

    test "captures was_at_bottom" do
      state = init_state()
      assert ConversationView.at_bottom?(state)

      {state, _id} = ConversationView.start_streaming(state, :assistant)

      assert state.was_at_bottom == true
    end
  end

  describe "end_streaming/1" do
    test "clears streaming_id" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.end_streaming(state)

      assert state.streaming_id == nil
    end

    test "resets was_at_bottom" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.end_streaming(state)

      assert state.was_at_bottom == false
    end
  end

  describe "append_chunk/2" do
    test "appends to streaming message" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.append_chunk(state, "Hello ")
      state = ConversationView.append_chunk(state, "World!")

      msg = hd(state.messages)
      assert msg.content == "Hello World!"
    end

    test "no-op when not streaming" do
      messages = [make_message("1", :user, "Test")]
      state = init_state(messages: messages)

      state = ConversationView.append_chunk(state, "extra")

      msg = hd(state.messages)
      assert msg.content == "Test"
    end

    test "updates total_lines as content grows" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      initial_lines = state.total_lines

      # Add enough content to increase line count
      long_content = String.duplicate("x", 200)
      state = ConversationView.append_chunk(state, long_content)

      assert state.total_lines > initial_lines
    end

    test "auto-scrolls when was_at_bottom is true" do
      state = init_state()
      state = %{state | viewport_height: 5}

      # Start streaming - should capture was_at_bottom as true
      {state, _id} = ConversationView.start_streaming(state, :assistant)
      assert state.was_at_bottom == true
      assert ConversationView.at_bottom?(state)

      # Append chunk
      state = ConversationView.append_chunk(state, "Some content")

      # Should still be at bottom
      assert ConversationView.at_bottom?(state)
    end

    test "does not auto-scroll when was_at_bottom is false" do
      # Create many messages to have scrollable content
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      # Scroll to top so we're not at bottom
      state = ConversationView.scroll_to(state, :top)
      refute ConversationView.at_bottom?(state)
      original_offset = state.scroll_offset

      # Manually set streaming state with was_at_bottom false
      new_msg = make_message("streaming", :assistant, "")

      state = %{
        state
        | messages: state.messages ++ [new_msg],
          streaming_id: "streaming",
          was_at_bottom: false
      }

      # Append chunk
      state = ConversationView.append_chunk(state, "Some content that grows")

      # Should NOT have auto-scrolled
      assert state.scroll_offset == original_offset
    end
  end

  # ============================================================================
  # Accessor Tests
  # ============================================================================

  describe "at_bottom?/1" do
    test "returns true when at bottom" do
      state = init_state()

      assert ConversationView.at_bottom?(state)
    end

    test "returns false when not at bottom" do
      messages =
        Enum.map(1..20, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 0}

      refute ConversationView.at_bottom?(state)
    end
  end

  describe "expanded?/2" do
    test "returns true for expanded message" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1"])}

      assert ConversationView.expanded?(state, "1")
    end

    test "returns false for collapsed message" do
      state = init_state()

      refute ConversationView.expanded?(state, "1")
    end
  end

  describe "message_count/1" do
    test "returns 0 for empty state" do
      state = init_state()

      assert ConversationView.message_count(state) == 0
    end

    test "returns correct count" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)

      assert ConversationView.message_count(state) == 2
    end
  end

  # ============================================================================
  # Section 9.2: Rendering Tests
  # ============================================================================

  describe "wrap_text/2" do
    test "returns empty string list for empty input" do
      assert ConversationView.wrap_text("", 80) == [""]
    end

    test "returns original text when it fits" do
      assert ConversationView.wrap_text("Hello world", 80) == ["Hello world"]
    end

    test "wraps at word boundary" do
      result = ConversationView.wrap_text("Hello world", 8)
      assert result == ["Hello", "world"]
    end

    test "wraps multiple words correctly" do
      result = ConversationView.wrap_text("one two three four five", 10)
      assert result == ["one two", "three four", "five"]
    end

    test "preserves explicit newlines" do
      result = ConversationView.wrap_text("Line one\nLine two\nLine three", 80)
      assert result == ["Line one", "Line two", "Line three"]
    end

    test "wraps and preserves newlines together" do
      result = ConversationView.wrap_text("Hello world\nFoo bar baz", 8)
      assert result == ["Hello", "world", "Foo bar", "baz"]
    end

    test "breaks long words that exceed max_width" do
      result = ConversationView.wrap_text("abcdefghij", 5)
      assert result == ["abcde", "fghij"]
    end

    test "breaks very long words into multiple chunks" do
      result = ConversationView.wrap_text("abcdefghijklmno", 5)
      assert result == ["abcde", "fghij", "klmno"]
    end

    test "handles mixed normal and long words" do
      result = ConversationView.wrap_text("hi abcdefghij bye", 5)
      assert result == ["hi", "abcde", "fghij", "bye"]
    end

    test "handles whitespace-only content" do
      result = ConversationView.wrap_text("   ", 80)
      assert result == [""]
    end

    test "handles empty lines in content" do
      result = ConversationView.wrap_text("Hello\n\nWorld", 80)
      assert result == ["Hello", "", "World"]
    end

    test "returns original for zero or negative width" do
      assert ConversationView.wrap_text("Hello", 0) == ["Hello"]
      assert ConversationView.wrap_text("Hello", -5) == ["Hello"]
    end
  end

  describe "truncate_content/4" do
    test "returns all lines when under max" do
      lines = ["one", "two", "three"]
      {result, truncated?} = ConversationView.truncate_content(lines, 5, MapSet.new(), "id")
      assert result == lines
      assert truncated? == false
    end

    test "returns all lines when equal to max" do
      lines = ["one", "two", "three"]
      {result, truncated?} = ConversationView.truncate_content(lines, 3, MapSet.new(), "id")
      assert result == lines
      assert truncated? == false
    end

    test "truncates when exceeding max" do
      lines = ["one", "two", "three", "four", "five"]
      {result, truncated?} = ConversationView.truncate_content(lines, 3, MapSet.new(), "id")
      # Shows max - 1 lines (reserving space for indicator)
      assert result == ["one", "two"]
      assert truncated? == true
    end

    test "does not truncate when message is expanded" do
      lines = ["one", "two", "three", "four", "five"]
      expanded = MapSet.new(["my-id"])
      {result, truncated?} = ConversationView.truncate_content(lines, 3, expanded, "my-id")
      assert result == lines
      assert truncated? == false
    end

    test "truncates other messages even when some are expanded" do
      lines = ["one", "two", "three", "four", "five"]
      expanded = MapSet.new(["other-id"])
      {result, truncated?} = ConversationView.truncate_content(lines, 3, expanded, "my-id")
      assert result == ["one", "two"]
      assert truncated? == true
    end
  end

  describe "get_role_style/2" do
    test "returns default style for user role" do
      state = init_state()
      style = ConversationView.get_role_style(state, :user)
      assert style.name == "You"
      assert style.color == :green
    end

    test "returns default style for assistant role" do
      state = init_state()
      style = ConversationView.get_role_style(state, :assistant)
      assert style.name == "Assistant"
      assert style.color == :cyan
    end

    test "returns default style for system role" do
      state = init_state()
      style = ConversationView.get_role_style(state, :system)
      assert style.name == "System"
      assert style.color == :yellow
    end

    test "returns custom style when configured" do
      custom_styles = %{
        user: %{name: "Me", color: :blue}
      }

      state = init_state(role_styles: custom_styles)
      style = ConversationView.get_role_style(state, :user)
      assert style.name == "Me"
      assert style.color == :blue
    end

    test "falls back to string name for unknown role" do
      state = init_state()
      style = ConversationView.get_role_style(state, :unknown)
      assert style.name == "unknown"
      assert style.color == :white
    end
  end

  describe "get_role_name/2" do
    test "returns display name for role" do
      state = init_state()
      assert ConversationView.get_role_name(state, :user) == "You"
      assert ConversationView.get_role_name(state, :assistant) == "Assistant"
      assert ConversationView.get_role_name(state, :system) == "System"
    end
  end

  describe "render/2" do
    # Note: render/2 returns simple structure:
    # - For empty messages: text("No messages yet", ...)
    # - For messages: stack(:horizontal, [content_stack, scrollbar])
    test "returns placeholder for empty messages" do
      state = init_state()
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)

      # Result is a simple text node for empty messages
      assert %TermUI.Component.RenderNode{type: :text, content: "No messages yet"} = result
    end

    test "renders messages with scrollbar in horizontal stack" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)

      # Result is a horizontal stack: [content, scrollbar]
      assert %TermUI.Component.RenderNode{type: :stack, direction: :horizontal} = result
      assert length(result.children) == 2
    end

    test "renders message content as vertical stack" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      content_stack = get_content_stack(result)

      # Content should be a vertical stack
      assert %TermUI.Component.RenderNode{type: :stack, direction: :vertical} = content_stack
    end

    test "renders message header with timestamp" do
      timestamp = ~U[2024-01-15 10:30:00Z]
      messages = [%{id: "1", role: :user, content: "Hello", timestamp: timestamp}]
      state = init_state(messages: messages, show_timestamps: true)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      content_stack = get_content_stack(result)

      # Find header node (first child of content stack)
      assert %TermUI.Component.RenderNode{type: :stack, children: children} = content_stack
      header = List.first(children)
      assert %TermUI.Component.RenderNode{type: :text, content: content} = header
      assert content =~ "[10:30]"
      assert content =~ "You:"
    end

    test "renders message header without timestamp when disabled" do
      timestamp = ~U[2024-01-15 10:30:00Z]
      messages = [%{id: "1", role: :user, content: "Hello", timestamp: timestamp}]
      state = init_state(messages: messages, show_timestamps: false)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      content_stack = get_content_stack(result)

      assert %TermUI.Component.RenderNode{type: :stack, children: children} = content_stack
      header = List.first(children)
      assert %TermUI.Component.RenderNode{type: :text, content: content} = header
      refute content =~ "["
      assert content == "You:"
    end

    test "renders content with indent" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages, indent: 2)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      content_stack = get_content_stack(result)

      assert %TermUI.Component.RenderNode{type: :stack, children: children} = content_stack
      # Second child should be content line
      content_node = Enum.at(children, 1)
      assert %TermUI.Component.RenderNode{type: :text, content: content} = content_node
      # 2 space indent
      assert String.starts_with?(content, "  ")
    end

    test "does not truncate conversation messages (only tool results are truncated)" do
      # Create a message with many lines - should NOT be truncated
      long_content = Enum.map_join(1..20, "\n", fn i -> "Line #{i}" end)
      messages = [make_message("1", :user, long_content)]
      state = init_state(messages: messages, max_collapsed_lines: 5)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # Should NOT have truncation indicator - conversation messages are never truncated
      indicator =
        Enum.find(all_nodes, fn node ->
          String.contains?(node.content || "", "more lines")
        end)

      assert indicator == nil
    end

    test "renders all lines for long messages without truncation" do
      long_content = Enum.map_join(1..20, "\n", fn i -> "Line #{i}" end)
      messages = [make_message("1", :user, long_content)]
      state = init_state(messages: messages, max_collapsed_lines: 5)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # All 20 lines should be present (no truncation)
      line_nodes =
        Enum.filter(all_nodes, fn node ->
          (node.content || "") =~ ~r/Line \d+/
        end)

      # Should have all 20 lines
      assert length(line_nodes) == 20
    end

    test "renders multiple messages" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi there!")
      ]

      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # Find headers
      headers =
        Enum.filter(all_nodes, fn node ->
          String.contains?(node.content || "", ":")
        end)

      # Should have at least 2 headers (one for each message)
      user_header = Enum.find(headers, &String.contains?(&1.content, "You:"))
      assistant_header = Enum.find(headers, &String.contains?(&1.content, "Assistant:"))

      assert user_header != nil
      assert assistant_header != nil
    end

    test "renders streaming cursor for streaming message" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)
      state = ConversationView.append_chunk(state, "Hello")
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # Find content node with streaming cursor
      cursor_node =
        Enum.find(all_nodes, fn node ->
          String.contains?(node.content || "", "▌")
        end)

      assert cursor_node != nil
    end

    test "streaming cursor removed after end_streaming" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)
      state = ConversationView.append_chunk(state, "Hello")

      # End streaming
      state = ConversationView.end_streaming(state)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # Should NOT find streaming cursor
      cursor_node =
        Enum.find(all_nodes, fn node ->
          String.contains?(node.content || "", "▌")
        end)

      assert cursor_node == nil
    end

    test "renders scrollbar" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)

      # Get messages_area (horizontal stack with [content, scrollbar])
      messages_area = get_messages_area(result)

      assert %TermUI.Component.RenderNode{type: :stack, children: [_content, scrollbar]} =
               messages_area

      assert %TermUI.Component.RenderNode{type: :stack, direction: :vertical} = scrollbar
    end
  end

  # ============================================================================
  # Section 9.3: Viewport and Scrolling Tests
  # ============================================================================

  describe "calculate_visible_range/1" do
    test "returns empty range for empty message list" do
      state = init_state()

      range = ConversationView.calculate_visible_range(state)

      assert range.start_msg_idx == 0
      assert range.start_line_offset == 0
      assert range.end_msg_idx == 0
      assert range.end_line_offset == 0
    end

    test "returns full range when content fits in viewport" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)
      # Content is ~6 lines
      state = %{state | viewport_height: 20}

      range = ConversationView.calculate_visible_range(state)

      assert range.start_msg_idx == 0
      assert range.start_line_offset == 0
      assert range.end_msg_idx == 1
    end

    test "calculates visible range with scroll offset" do
      # Create many messages so content exceeds viewport
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 6}

      range = ConversationView.calculate_visible_range(state)

      # First message should be after scroll offset
      assert range.start_msg_idx >= 1
    end

    test "handles single message" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)

      range = ConversationView.calculate_visible_range(state)

      assert range.start_msg_idx == 0
      assert range.end_msg_idx == 0
    end

    test "handles partial message visibility at edges" do
      # Create messages that span multiple lines
      long_content = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"

      messages = [
        make_message("1", :user, long_content),
        make_message("2", :user, long_content)
      ]

      state = init_state(messages: messages)
      # Scroll so first message is partially visible
      state = %{state | viewport_height: 5, scroll_offset: 3}

      range = ConversationView.calculate_visible_range(state)

      # Should have a non-zero start_line_offset
      assert range.start_line_offset > 0 or range.start_msg_idx > 0
    end
  end

  describe "get_message_line_info/1" do
    test "returns empty list for empty messages" do
      state = init_state()

      info = ConversationView.get_message_line_info(state)

      assert info == []
    end

    test "returns line info for each message" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "World")
      ]

      state = init_state(messages: messages)

      info = ConversationView.get_message_line_info(state)

      assert length(info) == 2
      # First message starts at line 0
      assert {0, _} = Enum.at(info, 0)
      # Second message starts after first
      {start, _} = Enum.at(info, 1)
      assert start > 0
    end

    test "accumulates line counts correctly" do
      messages = [
        make_message("1", :user, "Short"),
        make_message("2", :user, "Also short")
      ]

      state = init_state(messages: messages)

      info = ConversationView.get_message_line_info(state)

      {start1, lines1} = Enum.at(info, 0)
      {start2, _lines2} = Enum.at(info, 1)

      # Second message should start at first message's start + lines
      assert start2 == start1 + lines1
    end
  end

  describe "render_scrollbar/2" do
    test "renders full thumb when content fits in viewport" do
      state = init_state(messages: [make_message("1", :user, "Hi")])
      state = %{state | viewport_height: 20, total_lines: 5}

      scrollbar = ConversationView.render_scrollbar(state, 10)

      assert %TermUI.Component.RenderNode{type: :stack, children: children} = scrollbar
      # All children should be thumb (█)
      assert Enum.all?(children, fn node ->
               node.content == "█"
             end)
    end

    test "renders proportional thumb for long content" do
      # Create state with more content than viewport
      state = init_state()
      state = %{state | viewport_height: 10, total_lines: 50}

      scrollbar = ConversationView.render_scrollbar(state, 10)

      assert %TermUI.Component.RenderNode{type: :stack, children: children} = scrollbar
      # Should have mix of track and thumb
      thumb_count = Enum.count(children, &(&1.content == "█"))
      track_count = Enum.count(children, &(&1.content == "░"))

      assert thumb_count > 0
      assert track_count > 0
      assert thumb_count < length(children)
    end

    test "thumb position reflects scroll offset" do
      state = init_state()
      state = %{state | viewport_height: 10, total_lines: 50, scroll_offset: 0}

      scrollbar_top = ConversationView.render_scrollbar(state, 10)

      # Near bottom
      state = %{state | scroll_offset: 40}
      scrollbar_bottom = ConversationView.render_scrollbar(state, 10)

      # Extract thumb positions
      top_children = scrollbar_top.children
      bottom_children = scrollbar_bottom.children

      # Find first thumb position in each
      top_thumb_pos = Enum.find_index(top_children, &(&1.content == "█"))
      bottom_thumb_pos = Enum.find_index(bottom_children, &(&1.content == "█"))

      # Thumb should be lower (higher index) when scrolled down
      assert bottom_thumb_pos > top_thumb_pos
    end
  end

  describe "calculate_scrollbar_metrics/2" do
    test "returns full height when content fits" do
      state = init_state()
      state = %{state | viewport_height: 20, total_lines: 10}

      {thumb_size, thumb_pos} = ConversationView.calculate_scrollbar_metrics(state, 10)

      assert thumb_size == 10
      assert thumb_pos == 0
    end

    test "thumb size proportional to viewport/total ratio" do
      state = init_state()
      state = %{state | viewport_height: 10, total_lines: 50}

      {thumb_size, _} = ConversationView.calculate_scrollbar_metrics(state, 10)

      # Thumb should be about 20% of height (10/50 ratio)
      assert thumb_size == 2
    end

    test "thumb size is at least 1" do
      state = init_state()
      state = %{state | viewport_height: 5, total_lines: 500}

      {thumb_size, _} = ConversationView.calculate_scrollbar_metrics(state, 10)

      assert thumb_size >= 1
    end

    test "thumb position at top when scroll_offset is 0" do
      state = init_state()
      state = %{state | viewport_height: 10, total_lines: 50, scroll_offset: 0}

      {_, thumb_pos} = ConversationView.calculate_scrollbar_metrics(state, 10)

      assert thumb_pos == 0
    end

    test "thumb position at bottom when at max scroll" do
      state = init_state()
      # total_lines - viewport_height = 50 - 10
      max_offset = 40
      state = %{state | viewport_height: 10, total_lines: 50, scroll_offset: max_offset}

      {thumb_size, thumb_pos} = ConversationView.calculate_scrollbar_metrics(state, 10)

      # Thumb should be at the bottom
      assert thumb_pos + thumb_size == 10
    end
  end

  describe "virtual rendering" do
    test "only renders visible messages" do
      # Create many messages
      messages =
        Enum.map(1..20, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 10, scroll_offset: 0}
      area = %{x: 0, y: 0, width: 80, height: 10}

      result = ConversationView.render(state, area)
      all_nodes = flatten_nodes(result)

      # Should have limited number of nodes (not all 20 messages)
      headers = Enum.filter(all_nodes, &String.contains?(&1.content || "", "You:"))

      # With 10 line viewport and ~3 lines per message, we should see ~3-4 messages
      assert length(headers) <= 10
    end

    test "pads content when shorter than viewport" do
      messages = [make_message("1", :user, "Short")]
      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 80, height: 24}

      result = ConversationView.render(state, area)
      content_stack = get_content_stack(result)

      # Content stack should have area.height children (full height)
      assert length(content_stack.children) == 24
    end

    test "updates viewport dimensions from area" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)
      area = %{x: 0, y: 0, width: 120, height: 30}

      # The render function updates state internally
      # We verify by checking the scrollbar height
      result = ConversationView.render(state, area)

      # Result is a horizontal stack: [content, scrollbar]
      assert %TermUI.Component.RenderNode{type: :stack, children: [_, scrollbar]} = result
      # scrollbar height = area.height (full height)
      assert length(scrollbar.children) == 30
    end
  end

  describe "scroll position management" do
    test "max_scroll_offset returns 0 when content fits" do
      state = init_state()
      state = %{state | viewport_height: 20, total_lines: 10}

      assert ConversationView.max_scroll_offset(state) == 0
    end

    test "max_scroll_offset returns difference when content exceeds viewport" do
      state = init_state()
      state = %{state | viewport_height: 10, total_lines: 30}

      assert ConversationView.max_scroll_offset(state) == 20
    end

    test "scroll_by clamps to valid range" do
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      # Scroll past maximum
      state = ConversationView.scroll_by(state, 1000)
      max_offset = ConversationView.max_scroll_offset(state)

      assert state.scroll_offset == max_offset

      # Scroll before minimum
      state = ConversationView.scroll_by(state, -2000)

      assert state.scroll_offset == 0
    end

    test "add_message auto-scrolls when at bottom" do
      state = init_state()
      # Verify we start at bottom
      assert ConversationView.at_bottom?(state)

      # Add message
      state = ConversationView.add_message(state, make_message("1", :user, "Hello"))

      # Should still be at bottom
      assert ConversationView.at_bottom?(state)
    end

    test "add_message does not auto-scroll when scrolled up" do
      # Create initial messages to have scrollable content
      messages =
        Enum.map(1..10, fn i ->
          make_message("#{i}", :user, "Message #{i}")
        end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      # Scroll up (not at bottom)
      state = ConversationView.scroll_to(state, :top)
      refute ConversationView.at_bottom?(state)
      original_offset = state.scroll_offset

      # Add message
      state = ConversationView.add_message(state, make_message("new", :user, "New message"))

      # Should maintain scroll position (not auto-scroll)
      assert state.scroll_offset == original_offset
    end

    test "collapse_all clamps scroll offset" do
      # Create long content that will have many lines when expanded
      long_content = String.duplicate("Line\n", 50)
      messages = [make_message("1", :user, long_content)]
      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = %{state | viewport_height: 10}

      # Expand and scroll down
      state = ConversationView.expand_all(state)
      state = ConversationView.scroll_to(state, :bottom)
      expanded_offset = state.scroll_offset

      # Collapse - should clamp scroll
      state = ConversationView.collapse_all(state)

      # Offset should be reduced
      assert state.scroll_offset <= ConversationView.max_scroll_offset(state)
      assert state.scroll_offset < expanded_offset
    end
  end

  # ============================================================================
  # Section 9.4: Keyboard Event Handling Tests
  # ============================================================================

  describe "handle_event/2 - scroll navigation" do
    # Note: Arrow key scroll only works when input_focused: false
    # When input_focused: true, arrow keys go to TextInput
    test ":up key decreases scroll_offset by 1 (when input not focused)" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 10, input_focused: false}

      event = %TermUI.Event.Key{key: :up, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 9
    end

    test ":down key increases scroll_offset by 1 (when input not focused)" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 5, input_focused: false}

      event = %TermUI.Event.Key{key: :down, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 6
    end

    test ":page_up decreases scroll_offset by viewport_height (works even with input focused)" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 20}

      event = %TermUI.Event.Key{key: :page_up, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 15
    end

    test ":page_down increases scroll_offset by viewport_height (works even with input focused)" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 0}

      event = %TermUI.Event.Key{key: :page_down, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 5
    end

    test ":home sets scroll_offset to 0 (when input not focused)" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 20, input_focused: false}

      event = %TermUI.Event.Key{key: :home, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 0
    end

    test ":end sets scroll_offset to max (when input not focused)" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 0, input_focused: false}

      event = %TermUI.Event.Key{key: :end, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == ConversationView.max_scroll_offset(new_state)
    end

    test "scroll respects lower bound (no negative)" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      state = %{state | scroll_offset: 0, input_focused: false}

      event = %TermUI.Event.Key{key: :up, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 0
    end

    test "scroll respects upper bound" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, input_focused: false}
      max_offset = ConversationView.max_scroll_offset(state)
      state = %{state | scroll_offset: max_offset}

      event = %TermUI.Event.Key{key: :down, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == max_offset
    end
  end

  describe "handle_event/2 - message focus navigation" do
    # Note: Ctrl+Up/Down only work when input_focused: false
    # When input_focused: true, these keys go to TextInput
    test "Ctrl+Up moves cursor_message_idx up" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second"),
        make_message("3", :user, "Third")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 2, input_focused: false}

      event = %TermUI.Event.Key{key: :up, modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 1
    end

    test "Ctrl+Down moves cursor_message_idx down" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second"),
        make_message("3", :user, "Third")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 0, input_focused: false}

      event = %TermUI.Event.Key{key: :down, modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 1
    end

    test "focus navigation clamps to first message" do
      messages = [make_message("1", :user, "First")]
      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 0, input_focused: false}

      event = %TermUI.Event.Key{key: :up, modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 0
    end

    test "focus navigation clamps to last message" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 1, input_focused: false}

      event = %TermUI.Event.Key{key: :down, modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 1
    end

    test "focus navigation adjusts scroll to keep message visible" do
      # Create many messages
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)

      state = %{
        state
        | viewport_height: 5,
          cursor_message_idx: 0,
          scroll_offset: 0,
          input_focused: false
      }

      # Move focus down several times
      event = %TermUI.Event.Key{key: :down, modifiers: [:ctrl]}

      state =
        Enum.reduce(1..10, state, fn _, acc ->
          {:ok, new_state} = ConversationView.handle_event(event, acc)
          new_state
        end)

      # Focus should be at message 10 and it should be visible
      assert state.cursor_message_idx == 10
      # Scroll should have adjusted to keep the message visible
      visible_range = ConversationView.calculate_visible_range(state)
      assert state.cursor_message_idx >= visible_range.start_msg_idx
      assert state.cursor_message_idx <= visible_range.end_msg_idx
    end
  end

  describe "handle_event/2 - expand/collapse" do
    # Note: Expand/collapse keys only work when input_focused: false
    # When input_focused: true, these keys go to TextInput
    test "Space toggles expansion of focused message" do
      long_content = String.duplicate("Line\n", 30)
      messages = [make_message("1", :user, long_content)]
      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = %{state | cursor_message_idx: 0, input_focused: false}

      # Initially collapsed
      refute ConversationView.expanded?(state, "1")

      # Press space to expand
      event = %TermUI.Event.Key{key: :space, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert ConversationView.expanded?(new_state, "1")

      # Press space again to collapse
      {:ok, collapsed_state} = ConversationView.handle_event(event, new_state)

      refute ConversationView.expanded?(collapsed_state, "1")
    end

    test "e key expands all messages" do
      messages = [
        make_message("1", :user, String.duplicate("Line\n", 20)),
        make_message("2", :assistant, String.duplicate("Line\n", 20))
      ]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = %{state | input_focused: false}

      event = %TermUI.Event.Key{key: nil, char: "e", modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert ConversationView.expanded?(new_state, "1")
      assert ConversationView.expanded?(new_state, "2")
    end

    test "c key collapses all messages" do
      messages = [
        make_message("1", :user, String.duplicate("Line\n", 20)),
        make_message("2", :assistant, String.duplicate("Line\n", 20))
      ]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = ConversationView.expand_all(state)
      state = %{state | input_focused: false}

      # Both expanded
      assert ConversationView.expanded?(state, "1")
      assert ConversationView.expanded?(state, "2")

      # Press c to collapse all
      event = %TermUI.Event.Key{key: nil, char: "c", modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      refute ConversationView.expanded?(new_state, "1")
      refute ConversationView.expanded?(new_state, "2")
    end

    test "expansion recalculates total_lines" do
      long_content = String.duplicate("Line\n", 30)
      messages = [make_message("1", :user, long_content)]
      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = %{state | input_focused: false}

      collapsed_lines = state.total_lines

      # Expand via space key
      event = %TermUI.Event.Key{key: :space, modifiers: []}
      {:ok, expanded_state} = ConversationView.handle_event(event, state)

      # Expanded should have more lines
      assert expanded_state.total_lines > collapsed_lines
    end
  end

  describe "handle_event/2 - copy functionality" do
    # Note: Copy key only works when input_focused: false
    # When input_focused: true, these keys go to TextInput
    test "y key calls on_copy with message content" do
      # Track copy callback invocations
      test_pid = self()

      callback = fn content ->
        send(test_pid, {:copied, content})
        :ok
      end

      messages = [make_message("1", :user, "Hello World")]
      state = init_state(messages: messages, on_copy: callback)
      state = %{state | cursor_message_idx: 0, input_focused: false}

      event = %TermUI.Event.Key{key: nil, char: "y", modifiers: []}
      {:ok, _new_state} = ConversationView.handle_event(event, state)

      assert_receive {:copied, "Hello World"}
    end

    test "y key is no-op when on_copy is nil" do
      messages = [make_message("1", :user, "Hello")]
      state = init_state(messages: messages)
      state = %{state | input_focused: false}
      # on_copy is nil by default

      event = %TermUI.Event.Key{key: nil, char: "y", modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # State unchanged
      assert new_state == state
    end
  end

  describe "handle_event/2 - catch-all" do
    test "unhandled events return unchanged state" do
      state = init_state()
      state = %{state | input_focused: false}

      # Some random event
      event = %TermUI.Event.Key{key: :f1, modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state == state
    end

    test "character keys not handled return unchanged state" do
      state = init_state()
      state = %{state | input_focused: false}

      event = %TermUI.Event.Key{key: nil, char: "x", modifiers: []}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state == state
    end
  end

  describe "move_focus/2" do
    test "moves focus down" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)

      new_state = ConversationView.move_focus(state, 1)

      assert new_state.cursor_message_idx == 1
    end

    test "moves focus up" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 1}

      new_state = ConversationView.move_focus(state, -1)

      assert new_state.cursor_message_idx == 0
    end

    test "clamps to valid range" do
      messages = [make_message("1", :user, "Only message")]
      state = init_state(messages: messages)

      # Try to move past end
      new_state = ConversationView.move_focus(state, 10)
      assert new_state.cursor_message_idx == 0

      # Try to move before start
      new_state = ConversationView.move_focus(state, -10)
      assert new_state.cursor_message_idx == 0
    end

    test "no-op for empty messages" do
      state = init_state()

      new_state = ConversationView.move_focus(state, 1)

      assert new_state.cursor_message_idx == 0
    end
  end

  describe "ensure_message_visible/2" do
    test "scrolls up when message is above visible area" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 30}

      # Message 0 is at line 0, which is above visible area (scroll 30)
      new_state = ConversationView.ensure_message_visible(state, 0)

      # Should scroll up to show message 0
      assert new_state.scroll_offset < 30
    end

    test "scrolls down when message is below visible area" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 0}

      # Message 15 is below visible area (scroll 0, viewport 5)
      new_state = ConversationView.ensure_message_visible(state, 15)

      # Should scroll down
      assert new_state.scroll_offset > 0
    end

    test "no change when message is already visible" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 20, scroll_offset: 0}

      original_offset = state.scroll_offset
      new_state = ConversationView.ensure_message_visible(state, 0)

      assert new_state.scroll_offset == original_offset
    end
  end

  describe "get_focused_message/1" do
    test "returns focused message" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 1}

      msg = ConversationView.get_focused_message(state)

      assert msg.id == "2"
      assert msg.content == "Second"
    end

    test "returns nil for empty messages" do
      state = init_state()

      msg = ConversationView.get_focused_message(state)

      assert msg == nil
    end
  end

  # ============================================================================
  # Section 9.5: Mouse Event Handling Tests
  # ============================================================================

  describe "handle_event/2 - mouse wheel scrolling" do
    test "scroll_up decreases scroll_offset by scroll_lines" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages, scroll_lines: 3)
      state = %{state | viewport_height: 5, scroll_offset: 15}

      event = %TermUI.Event.Mouse{action: :scroll_up, x: 0, y: 0}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 12
    end

    test "scroll_down increases scroll_offset by scroll_lines" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages, scroll_lines: 3)
      state = %{state | viewport_height: 5, scroll_offset: 5}

      event = %TermUI.Event.Mouse{action: :scroll_down, x: 0, y: 0}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 8
    end

    test "wheel scroll respects lower bound" do
      messages = [make_message("1", :user, "Test")]
      state = init_state(messages: messages, scroll_lines: 3)
      state = %{state | scroll_offset: 1}

      event = %TermUI.Event.Mouse{action: :scroll_up, x: 0, y: 0}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 0
    end

    test "wheel scroll respects upper bound" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages, scroll_lines: 3)
      state = %{state | viewport_height: 5}
      max_offset = ConversationView.max_scroll_offset(state)
      state = %{state | scroll_offset: max_offset - 1}

      event = %TermUI.Event.Mouse{action: :scroll_down, x: 0, y: 0}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == max_offset
    end

    test "scroll_lines is configurable" do
      messages = Enum.map(1..20, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages, scroll_lines: 5)
      state = %{state | viewport_height: 5, scroll_offset: 20}

      event = %TermUI.Event.Mouse{action: :scroll_up, x: 0, y: 0}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.scroll_offset == 15
    end
  end

  describe "handle_event/2 - scrollbar click handling" do
    # Note: scrollbar_width is now 1, so scrollbar is at x >= viewport_width - 1
    test "click above thumb triggers page up" do
      messages = Enum.map(1..30, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 10, viewport_width: 82, scroll_offset: 50}

      # Click above thumb (y = 0) on scrollbar (x >= content_width = 81)
      # Thumb is somewhere in the middle, so y=0 is always above it
      event = %TermUI.Event.Mouse{action: :click, x: 81, y: 0, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Should have scrolled up by viewport_height
      assert new_state.scroll_offset < 50
    end

    test "click below thumb triggers page down" do
      messages = Enum.map(1..30, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 10, viewport_width: 82, scroll_offset: 10}

      # Click at bottom of scrollbar (x >= content_width = 81)
      event = %TermUI.Event.Mouse{action: :click, x: 81, y: 9, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Should have scrolled down
      assert new_state.scroll_offset > 10
    end
  end

  describe "handle_event/2 - scrollbar drag handling" do
    # Note: scrollbar_width is now 1, so scrollbar is at x >= viewport_width - 1
    test "press on thumb starts drag state" do
      messages = Enum.map(1..30, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 10, viewport_width: 82, scroll_offset: 20}

      # Calculate thumb position
      {_thumb_size, thumb_pos} = ConversationView.calculate_scrollbar_metrics(state, 10)

      # Press on thumb (x >= content_width = 81)
      event = %TermUI.Event.Mouse{action: :press, x: 81, y: thumb_pos, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.dragging == true
      assert new_state.drag_start_y == thumb_pos
      assert new_state.drag_start_offset == 20
    end

    test "drag updates scroll offset proportionally" do
      messages = Enum.map(1..30, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 10, viewport_width: 82, scroll_offset: 20}

      # Start drag
      state = %{state | dragging: true, drag_start_y: 2, drag_start_offset: 20}

      # Drag down 3 pixels
      event = %TermUI.Event.Mouse{action: :drag, x: 80, y: 5, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Scroll offset should have increased
      assert new_state.scroll_offset > 20
    end

    test "release ends drag state" do
      state = init_state()
      state = %{state | dragging: true, drag_start_y: 5, drag_start_offset: 10}

      event = %TermUI.Event.Mouse{action: :release, x: 80, y: 8, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.dragging == false
      assert new_state.drag_start_y == nil
      assert new_state.drag_start_offset == nil
    end

    test "drag respects scroll bounds" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}
      max_offset = ConversationView.max_scroll_offset(state)

      # Start drag near bottom
      state = %{state | dragging: true, drag_start_y: 0, drag_start_offset: max_offset}

      # Try to drag way down
      event = %TermUI.Event.Mouse{action: :drag, x: 80, y: 100, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Should be clamped to max
      assert new_state.scroll_offset == max_offset
    end
  end

  describe "handle_event/2 - content click handling" do
    test "content click sets cursor_message_idx" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second"),
        make_message("3", :user, "Third")
      ]

      state = init_state(messages: messages)
      state = %{state | viewport_height: 20, viewport_width: 82}

      # Get line info to calculate click position for second message
      line_info = ConversationView.get_message_line_info(state)
      {second_msg_start, _} = Enum.at(line_info, 1)

      # Click on content area (x < content_width) at second message's line
      event = %TermUI.Event.Mouse{action: :click, x: 10, y: second_msg_start, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 1
    end

    test "content click with scroll offset" do
      messages = Enum.map(1..10, &make_message("#{&1}", :user, "Message #{&1}"))
      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, viewport_width: 82, scroll_offset: 10}

      # Click at y=2 with scroll_offset=10 means absolute line 12
      event = %TermUI.Event.Mouse{action: :click, x: 10, y: 2, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # cursor should be set to the message at that line
      assert new_state.cursor_message_idx >= 0
      assert new_state.cursor_message_idx < 10
    end

    test "content click on empty messages is no-op" do
      state = init_state()
      state = %{state | viewport_width: 82}

      event = %TermUI.Event.Mouse{action: :click, x: 10, y: 5, button: :left}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state.cursor_message_idx == 0
    end
  end

  describe "mouse event catch-all" do
    test "drag without dragging state is ignored" do
      state = init_state()
      # dragging is false by default

      event = %TermUI.Event.Mouse{action: :drag, x: 80, y: 5}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state == state
    end

    test "release without dragging state is ignored" do
      state = init_state()
      # dragging is false by default

      event = %TermUI.Event.Mouse{action: :release, x: 80, y: 5}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      assert new_state == state
    end
  end

  # ============================================================================
  # Interactive Element Navigation Tests
  # ============================================================================

  describe "interactive element navigation" do
    test "Ctrl+B enters interactive mode when code blocks exist" do
      markdown_with_code = """
      Here's some code:

      ```elixir
      def hello, do: :world
      ```
      """

      messages = [make_message("1", :assistant, markdown_with_code)]
      state = init_state(messages: messages)

      # Initially not in interactive mode
      refute state.interactive_mode

      # Press Ctrl+B
      event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Should now be in interactive mode with focused element
      assert new_state.interactive_mode
      assert new_state.focused_element_id != nil
      assert length(new_state.interactive_elements) == 1
    end

    test "Ctrl+B does nothing when no code blocks exist" do
      messages = [make_message("1", :assistant, "Just plain text, no code")]
      state = init_state(messages: messages)

      event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, new_state} = ConversationView.handle_event(event, state)

      # Should remain out of interactive mode
      refute new_state.interactive_mode
    end

    test "Ctrl+B cycles through multiple code blocks" do
      markdown_with_multiple = """
      First block:

      ```elixir
      def first, do: 1
      ```

      Second block:

      ```elixir
      def second, do: 2
      ```
      """

      messages = [make_message("1", :assistant, markdown_with_multiple)]
      state = init_state(messages: messages)

      # Enter interactive mode
      event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, state1} = ConversationView.handle_event(event, state)
      assert state1.interactive_mode
      first_id = state1.focused_element_id

      # Ctrl+B again to move to next element
      {:ok, state2} = ConversationView.handle_event(event, state1)
      second_id = state2.focused_element_id

      # Should have moved to different element
      assert first_id != second_id

      # Ctrl+B again should cycle back to first
      {:ok, state3} = ConversationView.handle_event(event, state2)
      assert state3.focused_element_id == first_id
    end

    test "Escape exits interactive mode" do
      markdown_with_code = """
      ```elixir
      def hello, do: :world
      ```
      """

      messages = [make_message("1", :assistant, markdown_with_code)]
      state = init_state(messages: messages)

      # Enter interactive mode
      ctrl_b_event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, state1} = ConversationView.handle_event(ctrl_b_event, state)
      assert state1.interactive_mode

      # Press Escape
      esc_event = %TermUI.Event.Key{key: :escape}
      {:ok, state2} = ConversationView.handle_event(esc_event, state1)

      # Should exit interactive mode
      refute state2.interactive_mode
      assert state2.focused_element_id == nil
    end

    test "get_focused_element returns focused element when in interactive mode" do
      markdown_with_code = """
      ```elixir
      def hello, do: :world
      ```
      """

      messages = [make_message("1", :assistant, markdown_with_code)]
      state = init_state(messages: messages)

      # Not in interactive mode - no focused element
      assert ConversationView.get_focused_element(state) == nil

      # Enter interactive mode
      event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, state1} = ConversationView.handle_event(event, state)

      # Should return the focused element
      element = ConversationView.get_focused_element(state1)
      assert element != nil
      assert element.type == :code_block
      assert element.content == "def hello, do: :world"
    end

    test "Enter copies focused element and exits interactive mode" do
      markdown_with_code = """
      ```elixir
      def hello, do: :world
      ```
      """

      # Use a callback to capture copied content
      messages = [make_message("1", :assistant, markdown_with_code)]

      state =
        init_state(
          messages: messages,
          on_copy: fn text ->
            send(self(), {:copied, text})
          end
        )

      # Enter interactive mode
      ctrl_b_event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, state1} = ConversationView.handle_event(ctrl_b_event, state)
      assert state1.interactive_mode

      # Press Enter to copy
      enter_event = %TermUI.Event.Key{key: :enter}
      {:ok, state2} = ConversationView.handle_event(enter_event, state1)

      # Should have copied and exited interactive mode
      refute state2.interactive_mode

      # Verify callback was called
      assert_receive {:copied, "def hello, do: :world"}
    end

    test "interactive_mode?/1 returns correct boolean" do
      messages = [make_message("1", :assistant, "```elixir\ncode\n```")]
      state = init_state(messages: messages)

      refute ConversationView.interactive_mode?(state)

      event = %TermUI.Event.Key{char: "b", modifiers: [:ctrl]}
      {:ok, state1} = ConversationView.handle_event(event, state)

      assert ConversationView.interactive_mode?(state1)
    end
  end
end
