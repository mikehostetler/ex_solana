defmodule JidoCode.TUI.Widgets.ConversationView do
  @moduledoc """
  ConversationView widget for displaying scrollable chat conversations.

  A purpose-built widget for displaying chat conversations with message-aware
  rendering, role-based styling, mouse-interactive scrollbar, and collapsible
  long messages.

  ## Usage

      ConversationView.new(
        messages: [],
        max_collapsed_lines: 15,
        show_timestamps: true
      )

  ## Features

  - Virtual scrolling for efficient rendering
  - Role-based styling (user, assistant, system)
  - Text wrapping at word boundaries
  - Collapsible long messages with truncation indicator
  - Mouse wheel and scrollbar drag support
  - Streaming message support with auto-scroll
  - Copy functionality for focused message

  ## Keyboard Controls

  - Up/Down: Scroll by line
  - PageUp/PageDown: Scroll by page
  - Home/End: Jump to top/bottom
  - Ctrl+Up/Down: Move message focus
  - Space: Toggle expand on focused message
  - e: Expand all messages
  - c: Collapse all messages
  - y: Copy focused message
  """

  use TermUI.StatefulComponent

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc "Message role indicating who sent the message"
  @type role :: :user | :assistant | :system

  @typedoc "A chat message with metadata"
  @type message :: %{
          id: String.t(),
          role: role(),
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc "Role styling configuration"
  @type role_style :: %{
          name: String.t(),
          color: atom()
        }

  @typedoc "Internal widget state"
  @type state :: %{
          # Messages
          messages: [message()],
          # Scroll state
          scroll_offset: non_neg_integer(),
          viewport_height: pos_integer(),
          viewport_width: pos_integer(),
          total_lines: non_neg_integer(),
          # Expansion state
          expanded: MapSet.t(String.t()),
          # Focus state
          cursor_message_idx: non_neg_integer(),
          # Mouse drag state
          dragging: boolean(),
          drag_start_y: non_neg_integer() | nil,
          drag_start_offset: non_neg_integer() | nil,
          # Streaming state
          streaming_id: String.t() | nil,
          was_at_bottom: boolean(),
          # Configuration
          max_collapsed_lines: pos_integer(),
          show_timestamps: boolean(),
          scrollbar_width: pos_integer(),
          indent: pos_integer(),
          scroll_lines: pos_integer(),
          role_styles: %{role() => role_style()},
          on_copy: (String.t() -> any()) | nil
        }

  @default_role_styles %{
    user: %{name: "You", color: :green},
    assistant: %{name: "Assistant", color: :cyan},
    system: %{name: "System", color: :yellow}
  }

  # ============================================================================
  # Props
  # ============================================================================

  @doc """
  Creates new ConversationView widget props.

  ## Options

  - `:messages` - Initial messages (default: [])
  - `:max_collapsed_lines` - Lines before truncation (default: 15)
  - `:show_timestamps` - Show [HH:MM] prefix (default: true)
  - `:scrollbar_width` - Scrollbar column width (default: 2)
  - `:indent` - Content indent spaces (default: 2)
  - `:scroll_lines` - Lines to scroll per wheel event (default: 3)
  - `:role_styles` - Per-role styling configuration
  - `:on_copy` - Clipboard callback function
  """
  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    %{
      messages: Keyword.get(opts, :messages, []),
      max_collapsed_lines: Keyword.get(opts, :max_collapsed_lines, 15),
      show_timestamps: Keyword.get(opts, :show_timestamps, true),
      scrollbar_width: Keyword.get(opts, :scrollbar_width, 2),
      indent: Keyword.get(opts, :indent, 2),
      scroll_lines: Keyword.get(opts, :scroll_lines, 3),
      role_styles: Keyword.get(opts, :role_styles, @default_role_styles),
      on_copy: Keyword.get(opts, :on_copy)
    }
  end

  # ============================================================================
  # StatefulComponent Callbacks
  # ============================================================================

  @impl true
  def init(props) do
    messages = props.messages

    state = %{
      # Messages
      messages: messages,
      # Scroll state
      scroll_offset: 0,
      viewport_height: 20,
      viewport_width: 80,
      total_lines: calculate_total_lines(messages, props.max_collapsed_lines, MapSet.new(), 80),
      # Expansion state
      expanded: MapSet.new(),
      # Focus state
      cursor_message_idx: 0,
      # Mouse drag state
      dragging: false,
      drag_start_y: nil,
      drag_start_offset: nil,
      # Streaming state
      streaming_id: nil,
      was_at_bottom: true,
      # Configuration (from props)
      max_collapsed_lines: props.max_collapsed_lines,
      show_timestamps: props.show_timestamps,
      scrollbar_width: props.scrollbar_width,
      indent: props.indent,
      scroll_lines: props.scroll_lines,
      role_styles: props.role_styles,
      on_copy: props.on_copy
    }

    {:ok, state}
  end

  # ============================================================================
  # Keyboard Event Handling (Section 9.4)
  # ============================================================================

  # Scroll Navigation

  @impl true
  def handle_event(%TermUI.Event.Key{key: :up, modifiers: []}, state) do
    {:ok, scroll_by(state, -1)}
  end

  def handle_event(%TermUI.Event.Key{key: :down, modifiers: []}, state) do
    {:ok, scroll_by(state, 1)}
  end

  def handle_event(%TermUI.Event.Key{key: :page_up}, state) do
    {:ok, scroll_by(state, -state.viewport_height)}
  end

  def handle_event(%TermUI.Event.Key{key: :page_down}, state) do
    {:ok, scroll_by(state, state.viewport_height)}
  end

  def handle_event(%TermUI.Event.Key{key: :home}, state) do
    {:ok, scroll_to(state, :top)}
  end

  def handle_event(%TermUI.Event.Key{key: :end}, state) do
    {:ok, scroll_to(state, :bottom)}
  end

  # Message Focus Navigation (Ctrl+Up/Down)

  def handle_event(%TermUI.Event.Key{key: :up, modifiers: [:ctrl]}, state) do
    {:ok, move_focus(state, -1)}
  end

  def handle_event(%TermUI.Event.Key{key: :up, modifiers: [:ctrl | _]}, state) do
    {:ok, move_focus(state, -1)}
  end

  def handle_event(%TermUI.Event.Key{key: :down, modifiers: [:ctrl]}, state) do
    {:ok, move_focus(state, 1)}
  end

  def handle_event(%TermUI.Event.Key{key: :down, modifiers: [:ctrl | _]}, state) do
    {:ok, move_focus(state, 1)}
  end

  # Expand/Collapse Handling

  def handle_event(%TermUI.Event.Key{key: :space}, state) do
    # Toggle expand on focused message
    case Enum.at(state.messages, state.cursor_message_idx) do
      nil ->
        {:ok, state}

      msg ->
        new_state = toggle_expand(state, msg.id)
        # Adjust scroll to keep focused message visible
        {:ok, ensure_message_visible(new_state, state.cursor_message_idx)}
    end
  end

  def handle_event(%TermUI.Event.Key{char: "e"}, state) do
    new_state = expand_all(state)
    {:ok, ensure_message_visible(new_state, state.cursor_message_idx)}
  end

  def handle_event(%TermUI.Event.Key{char: "c"}, state) do
    new_state = collapse_all(state)
    {:ok, ensure_message_visible(new_state, state.cursor_message_idx)}
  end

  # Copy Functionality

  def handle_event(%TermUI.Event.Key{char: "y"}, state) do
    case state.on_copy do
      nil ->
        {:ok, state}

      callback when is_function(callback, 1) ->
        content = get_selected_text(state)
        callback.(content)
        {:ok, state}
    end
  end

  # ============================================================================
  # Mouse Event Handling (Section 9.5)
  # ============================================================================

  # Mouse Wheel Scrolling

  def handle_event(%TermUI.Event.Mouse{action: :scroll_up}, state) do
    {:ok, scroll_by(state, -state.scroll_lines)}
  end

  def handle_event(%TermUI.Event.Mouse{action: :scroll_down}, state) do
    {:ok, scroll_by(state, state.scroll_lines)}
  end

  # Scrollbar Click Handling

  def handle_event(%TermUI.Event.Mouse{action: :click, x: x, y: y}, state) do
    handle_mouse_click(state, x, y)
  end

  def handle_event(%TermUI.Event.Mouse{action: :press, x: x, y: y}, state) do
    handle_mouse_press(state, x, y)
  end

  # Scrollbar Drag Handling

  def handle_event(%TermUI.Event.Mouse{action: :drag, y: y}, state) when state.dragging do
    handle_mouse_drag(state, y)
  end

  def handle_event(%TermUI.Event.Mouse{action: :release}, state) when state.dragging do
    {:ok, %{state | dragging: false, drag_start_y: nil, drag_start_offset: nil}}
  end

  # Catch-all handler for unrecognized events

  def handle_event(_event, state) do
    {:ok, state}
  end

  @impl true
  def render(state, area) do
    # Update viewport dimensions from area
    state = %{
      state
      | viewport_height: area.height,
        viewport_width: area.width
    }

    # Calculate content width (excluding scrollbar)
    content_width = max(10, area.width - state.scrollbar_width)

    # If no messages, show placeholder
    if Enum.empty?(state.messages) do
      text("No messages yet", Style.new(fg: :white, attrs: [:dim]))
    else
      # Calculate visible range for virtual rendering
      visible_range = calculate_visible_range(state)

      # Render only visible messages
      visible_messages =
        state.messages
        |> Enum.with_index()
        |> Enum.filter(fn {_msg, idx} ->
          idx >= visible_range.start_msg_idx and idx <= visible_range.end_msg_idx
        end)

      # Render message nodes with clipping
      message_nodes =
        visible_messages
        |> Enum.flat_map(fn {msg, idx} ->
          nodes = render_message(state, msg, idx, content_width)

          # Apply clipping for first/last visible messages
          cond do
            idx == visible_range.start_msg_idx and visible_range.start_line_offset > 0 ->
              # Skip lines from start of first message
              Enum.drop(nodes, visible_range.start_line_offset)

            idx == visible_range.end_msg_idx and
              idx == visible_range.start_msg_idx and
                visible_range.start_line_offset > 0 ->
              # Both start and end are same message - handle both clips
              nodes
              |> Enum.drop(visible_range.start_line_offset)
              |> Enum.take(state.viewport_height)

            true ->
              nodes
          end
        end)
        |> Enum.take(state.viewport_height)

      # Pad with empty lines if content < viewport height
      padding_count = max(0, state.viewport_height - length(message_nodes))

      padded_nodes =
        if padding_count > 0 do
          padding = for _ <- 1..padding_count, do: text("", nil)
          message_nodes ++ padding
        else
          message_nodes
        end

      # Render scrollbar
      scrollbar = render_scrollbar(state, area.height)

      # Combine content and scrollbar in horizontal stack
      content_stack = stack(:vertical, padded_nodes)
      stack(:horizontal, [content_stack, scrollbar])
    end
  end

  # ============================================================================
  # Public API - Message Management
  # ============================================================================

  @doc """
  Adds a message to the conversation.

  Appends the message to the end and recalculates total lines.
  If currently at the bottom, auto-scrolls to show the new message.
  """
  @spec add_message(state(), message()) :: state()
  def add_message(state, message) do
    messages = state.messages ++ [message]
    was_at_bottom = at_bottom?(state)

    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        state.expanded,
        state.viewport_width
      )

    state = %{state | messages: messages, total_lines: new_total_lines}

    # Auto-scroll if was at bottom
    if was_at_bottom do
      scroll_to(state, :bottom)
    else
      state
    end
  end

  @doc """
  Replaces all messages in the conversation.

  Resets scroll position to the top.
  """
  @spec set_messages(state(), [message()]) :: state()
  def set_messages(state, messages) do
    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        MapSet.new(),
        state.viewport_width
      )

    %{
      state
      | messages: messages,
        total_lines: new_total_lines,
        scroll_offset: 0,
        cursor_message_idx: 0,
        expanded: MapSet.new()
    }
  end

  @doc """
  Clears all messages from the conversation.

  Resets all state to initial values.
  """
  @spec clear(state()) :: state()
  def clear(state) do
    %{
      state
      | messages: [],
        total_lines: 0,
        scroll_offset: 0,
        cursor_message_idx: 0,
        expanded: MapSet.new(),
        streaming_id: nil
    }
  end

  @doc """
  Updates the viewport dimensions.

  Recalculates total lines and adjusts scroll position to ensure
  it remains valid with the new dimensions.
  """
  @spec set_viewport_size(state(), pos_integer(), pos_integer()) :: state()
  def set_viewport_size(state, width, height) do
    # Recalculate total lines with new width (affects text wrapping)
    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        state.expanded,
        width
      )

    # Clamp scroll offset to valid range with new dimensions
    max_offset = max(0, new_total_lines - height)
    new_offset = min(state.scroll_offset, max_offset)

    %{
      state
      | viewport_width: width,
        viewport_height: height,
        total_lines: new_total_lines,
        scroll_offset: new_offset
    }
  end

  @doc """
  Appends content to an existing message by ID.

  Used for streaming responses where content arrives incrementally.
  Auto-scrolls if `was_at_bottom` is true in state.
  """
  @spec append_to_message(state(), String.t(), String.t()) :: state()
  def append_to_message(state, message_id, content) do
    messages =
      Enum.map(state.messages, fn msg ->
        if msg.id == message_id do
          %{msg | content: msg.content <> content}
        else
          msg
        end
      end)

    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        state.expanded,
        state.viewport_width
      )

    state = %{state | messages: messages, total_lines: new_total_lines}

    # Auto-scroll if was at bottom when streaming started
    if state.was_at_bottom do
      scroll_to(state, :bottom)
    else
      state
    end
  end

  # ============================================================================
  # Public API - Expansion
  # ============================================================================

  @doc """
  Toggles the expanded state for a message.

  Expanded messages show full content; collapsed messages are truncated.
  """
  @spec toggle_expand(state(), String.t()) :: state()
  def toggle_expand(state, message_id) do
    expanded =
      if MapSet.member?(state.expanded, message_id) do
        MapSet.delete(state.expanded, message_id)
      else
        MapSet.put(state.expanded, message_id)
      end

    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        expanded,
        state.viewport_width
      )

    %{state | expanded: expanded, total_lines: new_total_lines}
  end

  @doc """
  Expands all messages that are currently truncated.
  """
  @spec expand_all(state()) :: state()
  def expand_all(state) do
    expanded = state.messages |> Enum.map(& &1.id) |> MapSet.new()

    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        expanded,
        state.viewport_width
      )

    %{state | expanded: expanded, total_lines: new_total_lines}
  end

  @doc """
  Collapses all expanded messages.
  """
  @spec collapse_all(state()) :: state()
  def collapse_all(state) do
    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        MapSet.new(),
        state.viewport_width
      )

    # Also clamp scroll offset since total_lines decreased
    max_offset = max_scroll_offset(%{state | total_lines: new_total_lines})
    scroll_offset = min(state.scroll_offset, max_offset)

    %{state | expanded: MapSet.new(), total_lines: new_total_lines, scroll_offset: scroll_offset}
  end

  # ============================================================================
  # Public API - Scrolling
  # ============================================================================

  @doc """
  Scrolls to a specific position.

  ## Positions

  - `:top` - Scroll to the beginning
  - `:bottom` - Scroll to the end
  - `{:message, id}` - Scroll to make a specific message visible
  """
  @spec scroll_to(state(), :top | :bottom | {:message, String.t()}) :: state()
  def scroll_to(state, :top) do
    %{state | scroll_offset: 0}
  end

  def scroll_to(state, :bottom) do
    max_offset = max_scroll_offset(state)
    %{state | scroll_offset: max_offset}
  end

  def scroll_to(state, {:message, message_id}) do
    # Find the message index
    case Enum.find_index(state.messages, &(&1.id == message_id)) do
      nil ->
        state

      idx ->
        # Calculate cumulative lines to this message
        lines_before =
          state.messages
          |> Enum.take(idx)
          |> Enum.reduce(0, fn msg, acc ->
            acc +
              message_line_count(
                msg,
                state.max_collapsed_lines,
                state.expanded,
                state.viewport_width
              )
          end)

        # Scroll to put message at top of viewport
        offset = min(lines_before, max_scroll_offset(state))
        %{state | scroll_offset: offset, cursor_message_idx: idx}
    end
  end

  @doc """
  Scrolls by a relative number of lines.

  Positive values scroll down, negative values scroll up.
  """
  @spec scroll_by(state(), integer()) :: state()
  def scroll_by(state, delta) do
    new_offset = state.scroll_offset + delta
    clamped_offset = clamp_scroll(new_offset, state)
    %{state | scroll_offset: clamped_offset}
  end

  # ============================================================================
  # Public API - Selection
  # ============================================================================

  @doc """
  Gets the content of the currently focused message.

  Returns empty string if no message is focused.
  """
  @spec get_selected_text(state()) :: String.t()
  def get_selected_text(state) do
    case Enum.at(state.messages, state.cursor_message_idx) do
      nil -> ""
      msg -> msg.content
    end
  end

  # ============================================================================
  # Public API - Streaming
  # ============================================================================

  @doc """
  Starts streaming mode for a new message.

  Creates a placeholder message and tracks streaming state.
  """
  @spec start_streaming(state(), role()) :: {state(), String.t()}
  def start_streaming(state, role) do
    message_id = generate_id()

    message = %{
      id: message_id,
      role: role,
      content: "",
      timestamp: DateTime.utc_now()
    }

    was_at_bottom = at_bottom?(state)
    state = add_message(state, message)

    {%{state | streaming_id: message_id, was_at_bottom: was_at_bottom}, message_id}
  end

  @doc """
  Ends streaming mode.

  Clears the streaming_id and resets was_at_bottom.
  """
  @spec end_streaming(state()) :: state()
  def end_streaming(state) do
    %{state | streaming_id: nil, was_at_bottom: false}
  end

  @doc """
  Appends a chunk to the currently streaming message.

  No-op if not in streaming mode.
  """
  @spec append_chunk(state(), String.t()) :: state()
  def append_chunk(state, chunk) do
    case state.streaming_id do
      nil -> state
      id -> append_to_message(state, id, chunk)
    end
  end

  # ============================================================================
  # Public API - Accessors
  # ============================================================================

  @doc """
  Returns whether the view is currently at the bottom.
  """
  @spec at_bottom?(state()) :: boolean()
  def at_bottom?(state) do
    state.scroll_offset >= max_scroll_offset(state)
  end

  @doc """
  Returns the maximum scroll offset.
  """
  @spec max_scroll_offset(state()) :: non_neg_integer()
  def max_scroll_offset(state) do
    max(0, state.total_lines - state.viewport_height)
  end

  @doc """
  Returns whether a message is currently expanded.
  """
  @spec expanded?(state(), String.t()) :: boolean()
  def expanded?(state, message_id) do
    MapSet.member?(state.expanded, message_id)
  end

  @doc """
  Returns the number of messages.
  """
  @spec message_count(state()) :: non_neg_integer()
  def message_count(state) do
    length(state.messages)
  end

  # ============================================================================
  # Public API - Focus Navigation
  # ============================================================================

  @doc """
  Moves the message focus by delta positions.

  Positive delta moves down, negative moves up. Clamps to valid range.
  Ensures the focused message is visible after moving.
  """
  @spec move_focus(state(), integer()) :: state()
  def move_focus(state, delta) do
    message_count = length(state.messages)

    if message_count == 0 do
      state
    else
      new_idx = state.cursor_message_idx + delta
      clamped_idx = max(0, min(new_idx, message_count - 1))
      state = %{state | cursor_message_idx: clamped_idx}
      ensure_message_visible(state, clamped_idx)
    end
  end

  @doc """
  Ensures a message at the given index is visible in the viewport.

  Adjusts scroll offset if the message is above or below the visible area.
  """
  @spec ensure_message_visible(state(), non_neg_integer()) :: state()
  def ensure_message_visible(state, message_idx) do
    if Enum.empty?(state.messages) or message_idx >= length(state.messages) do
      state
    else
      # Calculate cumulative lines to find the message's position
      line_info = get_message_line_info(state)
      {msg_start_line, msg_line_count} = Enum.at(line_info, message_idx, {0, 0})
      msg_end_line = msg_start_line + msg_line_count

      # Check if message is above visible area
      cond do
        msg_start_line < state.scroll_offset ->
          # Scroll up to show message at top
          %{state | scroll_offset: msg_start_line}

        msg_end_line > state.scroll_offset + state.viewport_height ->
          # Scroll down to show message at bottom
          new_offset = max(0, msg_end_line - state.viewport_height)
          %{state | scroll_offset: new_offset}

        true ->
          # Message is already visible
          state
      end
    end
  end

  @doc """
  Returns the currently focused message, or nil if none.
  """
  @spec get_focused_message(state()) :: message() | nil
  def get_focused_message(state) do
    Enum.at(state.messages, state.cursor_message_idx)
  end

  # ============================================================================
  # Public API - Viewport Calculation
  # ============================================================================

  @typedoc """
  Visible range information for virtual rendering.

  - `start_msg_idx` - Index of first visible message
  - `start_line_offset` - Lines to skip from start of first message
  - `end_msg_idx` - Index of last visible message
  - `end_line_offset` - Lines to show from last message
  """
  @type visible_range :: %{
          start_msg_idx: non_neg_integer(),
          start_line_offset: non_neg_integer(),
          end_msg_idx: non_neg_integer(),
          end_line_offset: non_neg_integer()
        }

  @doc """
  Calculates the visible range of messages based on scroll offset and viewport height.

  Returns a map with:
  - `start_msg_idx` - Index of first visible message
  - `start_line_offset` - Lines to skip from start of first message
  - `end_msg_idx` - Index of last visible message
  - `end_line_offset` - Lines to show from last message

  For empty message lists, returns a range covering index 0.
  """
  @spec calculate_visible_range(state()) :: visible_range()
  def calculate_visible_range(state) do
    if Enum.empty?(state.messages) do
      %{start_msg_idx: 0, start_line_offset: 0, end_msg_idx: 0, end_line_offset: 0}
    else
      # Build cumulative line counts for each message
      {cumulative, _} =
        state.messages
        |> Enum.with_index()
        |> Enum.map_reduce(0, fn {msg, _idx}, acc ->
          lines =
            message_line_count(
              msg,
              state.max_collapsed_lines,
              state.expanded,
              state.viewport_width
            )

          {{acc, lines}, acc + lines}
        end)

      # Find first visible message
      {start_msg_idx, start_line_offset} = find_message_at_line(cumulative, state.scroll_offset)

      # Find last visible message
      end_line = state.scroll_offset + state.viewport_height
      {end_msg_idx, end_line_offset} = find_message_at_line(cumulative, end_line)

      # Clamp end_msg_idx to valid range
      last_idx = length(state.messages) - 1
      end_msg_idx = min(end_msg_idx, last_idx)

      %{
        start_msg_idx: start_msg_idx,
        start_line_offset: start_line_offset,
        end_msg_idx: end_msg_idx,
        end_line_offset: end_line_offset
      }
    end
  end

  @doc """
  Returns the cumulative line counts for each message.

  Each entry is `{start_line, line_count}` for that message.
  """
  @spec get_message_line_info(state()) :: [{non_neg_integer(), non_neg_integer()}]
  def get_message_line_info(state) do
    {cumulative, _} =
      state.messages
      |> Enum.map_reduce(0, fn msg, acc ->
        lines =
          message_line_count(msg, state.max_collapsed_lines, state.expanded, state.viewport_width)

        {{acc, lines}, acc + lines}
      end)

    cumulative
  end

  # Find which message contains a given line number
  defp find_message_at_line(cumulative, target_line) do
    cumulative
    |> Enum.with_index()
    |> Enum.reduce_while({0, 0}, fn {{start_line, line_count}, idx}, _acc ->
      end_line = start_line + line_count

      if target_line < end_line do
        {:halt, {idx, target_line - start_line}}
      else
        # Default to last message if we pass all
        {:cont, {idx, line_count}}
      end
    end)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp calculate_total_lines(messages, max_collapsed, expanded, viewport_width) do
    Enum.reduce(messages, 0, fn msg, acc ->
      acc + message_line_count(msg, max_collapsed, expanded, viewport_width)
    end)
  end

  defp message_line_count(msg, max_collapsed, expanded, viewport_width) do
    # Header line + content lines + separator
    content_lines = count_wrapped_lines(msg.content, viewport_width - 4)

    display_lines =
      if MapSet.member?(expanded, msg.id) or content_lines <= max_collapsed do
        content_lines
      else
        # Show truncated version: max_collapsed - 1 lines + truncation indicator
        max_collapsed
      end

    # 1 for header + display_lines + 1 for separator
    1 + display_lines + 1
  end

  defp count_wrapped_lines("", _width), do: 1

  defp count_wrapped_lines(_text, width) when width <= 0, do: 1

  defp count_wrapped_lines(text, width) do
    text
    |> String.split("\n")
    |> Enum.reduce(0, fn line, acc ->
      line_len = String.length(line)

      if line_len == 0 do
        acc + 1
      else
        acc + ceil(line_len / width)
      end
    end)
  end

  defp clamp_scroll(offset, state) do
    max_offset = max_scroll_offset(state)
    max(0, min(offset, max_offset))
  end

  # ============================================================================
  # Mouse Event Helpers
  # ============================================================================

  defp handle_mouse_click(state, x, y) do
    content_width = state.viewport_width - state.scrollbar_width

    if x >= content_width do
      # Click on scrollbar
      handle_scrollbar_click(state, y)
    else
      # Click on content - set focus to clicked message
      handle_content_click(state, x, y)
    end
  end

  defp handle_mouse_press(state, x, y) do
    content_width = state.viewport_width - state.scrollbar_width

    if x >= content_width do
      # Press on scrollbar - check if on thumb to start drag
      handle_scrollbar_press(state, y)
    else
      # Press on content is handled same as click
      handle_content_click(state, x, y)
    end
  end

  defp handle_scrollbar_click(state, y) do
    # Calculate thumb position
    {thumb_size, thumb_pos} = calculate_scrollbar_metrics(state, state.viewport_height)

    cond do
      # Click above thumb - page up
      y < thumb_pos ->
        {:ok, scroll_by(state, -state.viewport_height)}

      # Click below thumb - page down
      y >= thumb_pos + thumb_size ->
        {:ok, scroll_by(state, state.viewport_height)}

      # Click on thumb - no action on simple click (drag handled by press)
      true ->
        {:ok, state}
    end
  end

  defp handle_scrollbar_press(state, y) do
    # Calculate thumb position
    {thumb_size, thumb_pos} = calculate_scrollbar_metrics(state, state.viewport_height)

    if y >= thumb_pos and y < thumb_pos + thumb_size do
      # Press on thumb - start drag
      {:ok, %{state | dragging: true, drag_start_y: y, drag_start_offset: state.scroll_offset}}
    else
      # Press above/below thumb - same as click
      handle_scrollbar_click(state, y)
    end
  end

  defp handle_mouse_drag(state, y) do
    # Calculate proportional scroll based on drag distance
    track_height = state.viewport_height
    max_offset = max_scroll_offset(state)

    if track_height > 0 and max_offset > 0 do
      delta_y = y - state.drag_start_y
      # Each pixel of drag corresponds to max_offset / track_height scroll
      offset_change = round(delta_y * max_offset / track_height)
      new_offset = clamp_scroll(state.drag_start_offset + offset_change, state)
      {:ok, %{state | scroll_offset: new_offset}}
    else
      {:ok, state}
    end
  end

  defp handle_content_click(state, _x, y) do
    # Calculate which message was clicked based on y position and scroll offset
    if Enum.empty?(state.messages) do
      {:ok, state}
    else
      # Get absolute line position (viewport y + scroll offset)
      absolute_line = y + state.scroll_offset

      # Find which message contains this line
      line_info = get_message_line_info(state)
      message_idx = find_message_index_at_line(line_info, absolute_line)

      # Clamp to valid range
      message_idx = max(0, min(message_idx, length(state.messages) - 1))

      {:ok, %{state | cursor_message_idx: message_idx}}
    end
  end

  defp find_message_index_at_line(line_info, target_line) do
    line_info
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {{start_line, line_count}, idx}, _acc ->
      end_line = start_line + line_count

      if target_line < end_line do
        {:halt, idx}
      else
        {:cont, idx}
      end
    end)
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # ============================================================================
  # Rendering Helpers
  # ============================================================================

  @doc false
  defp render_message(state, message, idx, width) do
    is_focused = idx == state.cursor_message_idx
    is_streaming = message.id == state.streaming_id
    role_style = get_role_style(state, message.role)

    # Build header
    header = render_message_header(state, message, role_style, is_focused)

    # Calculate content width (accounting for indent)
    content_width = max(1, width - state.indent)

    # Wrap and potentially truncate content
    wrapped_lines = wrap_text(message.content, content_width)

    {display_lines, truncated?} =
      truncate_content(wrapped_lines, state.max_collapsed_lines, state.expanded, message.id)

    # Add streaming cursor if this is the streaming message
    display_lines =
      if is_streaming and length(display_lines) > 0 do
        last_idx = length(display_lines) - 1
        List.update_at(display_lines, last_idx, &(&1 <> "▌"))
      else
        display_lines
      end

    # Render content lines with indent and role color
    indent_str = String.duplicate(" ", state.indent)
    content_style = Style.new(fg: role_style.color)

    content_nodes =
      Enum.map(display_lines, fn line ->
        text(indent_str <> line, content_style)
      end)

    # Add truncation indicator if truncated
    content_nodes =
      if truncated? do
        hidden_count = length(wrapped_lines) - (state.max_collapsed_lines - 1)
        indicator = "#{indent_str}┄┄┄ #{hidden_count} more lines ┄┄┄"
        indicator_style = Style.new(fg: :white, attrs: [:dim])
        content_nodes ++ [text(indicator, indicator_style)]
      else
        content_nodes
      end

    # Add separator (blank line)
    separator = text("", nil)

    [header] ++ content_nodes ++ [separator]
  end

  defp render_message_header(state, message, role_style, is_focused) do
    # Build timestamp prefix if enabled
    timestamp_str =
      if state.show_timestamps do
        time = Calendar.strftime(message.timestamp, "%H:%M")
        "[#{time}] "
      else
        ""
      end

    # Role name with styling
    role_name = role_style.name

    # Build header text
    header_text = "#{timestamp_str}#{role_name}:"

    # Apply styling - bold for role, with background highlight if focused
    header_style =
      if is_focused do
        Style.new(fg: role_style.color, attrs: [:bold], bg: :black)
      else
        Style.new(fg: role_style.color, attrs: [:bold])
      end

    text(header_text, header_style)
  end

  # ============================================================================
  # Text Wrapping
  # ============================================================================

  @doc """
  Wraps text to fit within a maximum width, respecting word boundaries.

  - Preserves explicit newlines in the content
  - Wraps at word boundaries when possible
  - Force-breaks words that exceed max_width
  - Returns a list of wrapped lines
  """
  @spec wrap_text(String.t(), pos_integer()) :: [String.t()]
  def wrap_text("", _max_width), do: [""]
  def wrap_text(text, max_width) when max_width <= 0, do: [text]

  def wrap_text(text, max_width) do
    text
    |> String.split("\n")
    |> Enum.flat_map(&wrap_line(&1, max_width))
  end

  defp wrap_line("", _max_width), do: [""]

  defp wrap_line(line, max_width) do
    words = String.split(line, ~r/\s+/, trim: false)

    # Handle whitespace-only lines
    if Enum.all?(words, &(&1 == "")) do
      [""]
    else
      wrap_words(words, max_width, [], "")
    end
  end

  defp wrap_words([], _max_width, lines, current) do
    Enum.reverse([current | lines])
  end

  defp wrap_words([word | rest], max_width, lines, current) do
    word_len = String.length(word)
    current_len = String.length(current)

    cond do
      # Empty word (from consecutive spaces) - skip
      word == "" ->
        wrap_words(rest, max_width, lines, current)

      # Word fits on current line
      current == "" ->
        # First word on line - handle long words
        if word_len > max_width do
          # Break long word
          {broken_lines, remainder} = break_long_word(word, max_width)
          wrap_words(rest, max_width, Enum.reverse(broken_lines) ++ lines, remainder)
        else
          wrap_words(rest, max_width, lines, word)
        end

      current_len + 1 + word_len <= max_width ->
        # Word fits with space
        wrap_words(rest, max_width, lines, current <> " " <> word)

      true ->
        # Word doesn't fit - start new line
        if word_len > max_width do
          # Break long word
          {broken_lines, remainder} = break_long_word(word, max_width)
          wrap_words(rest, max_width, Enum.reverse(broken_lines) ++ [current | lines], remainder)
        else
          wrap_words(rest, max_width, [current | lines], word)
        end
    end
  end

  defp break_long_word(word, max_width) do
    chunks =
      word
      |> String.graphemes()
      |> Enum.chunk_every(max_width)
      |> Enum.map(&Enum.join/1)

    case chunks do
      [] ->
        {[], ""}

      [single] ->
        {[], single}

      _ ->
        {init, [last]} = Enum.split(chunks, -1)
        {init, last}
    end
  end

  # ============================================================================
  # Content Truncation
  # ============================================================================

  @doc """
  Truncates content if it exceeds max_collapsed_lines.

  Returns `{display_lines, truncated?}` where:
  - `display_lines` is the list of lines to display
  - `truncated?` is true if content was truncated
  """
  @spec truncate_content([String.t()], pos_integer(), MapSet.t(), String.t()) ::
          {[String.t()], boolean()}
  def truncate_content(lines, max_lines, expanded, message_id) do
    line_count = length(lines)
    is_expanded = MapSet.member?(expanded, message_id)

    if is_expanded or line_count <= max_lines do
      {lines, false}
    else
      # Show max_lines - 1 lines (reserving 1 for truncation indicator)
      display_count = max(1, max_lines - 1)
      {Enum.take(lines, display_count), true}
    end
  end

  # ============================================================================
  # Role Styling
  # ============================================================================

  @doc """
  Gets the style configuration for a role.

  Returns the role style from state.role_styles, falling back to defaults.
  """
  @spec get_role_style(state(), role()) :: role_style()
  def get_role_style(state, role) do
    Map.get(state.role_styles, role, %{name: to_string(role), color: :white})
  end

  @doc """
  Gets the display name for a role.
  """
  @spec get_role_name(state(), role()) :: String.t()
  def get_role_name(state, role) do
    get_role_style(state, role).name
  end

  # ============================================================================
  # Scrollbar Rendering
  # ============================================================================

  @doc """
  Renders the scrollbar for the given viewport height.

  Returns a list of render nodes representing the scrollbar column.
  The scrollbar shows:
  - Track using `░` character
  - Thumb using `█` character
  - Position proportional to scroll offset
  """
  @spec render_scrollbar(state(), pos_integer()) :: TermUI.Component.RenderNode.t()
  def render_scrollbar(state, height) do
    scrollbar_style = Style.new(fg: :white, attrs: [:dim])
    thumb_style = Style.new(fg: :white)

    if state.total_lines <= state.viewport_height do
      # No scrolling needed - show full track as thumb
      lines = for _ <- 1..height, do: text("█", thumb_style)
      stack(:vertical, lines)
    else
      # Calculate thumb size and position
      {thumb_size, thumb_pos} = calculate_scrollbar_metrics(state, height)

      # Build scrollbar lines
      lines =
        for y <- 0..(height - 1) do
          if y >= thumb_pos and y < thumb_pos + thumb_size do
            text("█", thumb_style)
          else
            text("░", scrollbar_style)
          end
        end

      stack(:vertical, lines)
    end
  end

  @doc """
  Calculates scrollbar thumb size and position.

  Returns `{thumb_size, thumb_position}` where both are in lines.
  """
  @spec calculate_scrollbar_metrics(state(), pos_integer()) ::
          {pos_integer(), non_neg_integer()}
  def calculate_scrollbar_metrics(state, height) do
    if state.total_lines <= state.viewport_height do
      {height, 0}
    else
      # Thumb size proportional to viewport / total content
      thumb_size = max(1, round(height * state.viewport_height / state.total_lines))

      # Thumb position proportional to scroll offset
      max_offset = max_scroll_offset(state)
      scroll_fraction = if max_offset > 0, do: state.scroll_offset / max_offset, else: 0.0
      thumb_pos = round((height - thumb_size) * scroll_fraction)

      {thumb_size, thumb_pos}
    end
  end
end
