defmodule JidoCode.TUI.ViewHelpers do
  @moduledoc """
  View helper functions for TUI rendering.

  This module extracts view rendering logic from the main TUI module to improve
  maintainability. It provides functions for rendering the status bar, conversation
  area, tool calls, reasoning panel, and input bar.

  ## Rendering Components

  - Status bar: Provider/model info, agent status, keyboard hints
  - Conversation: Message history with timestamps and role indicators
  - Tool calls: Formatted tool execution entries with results
  - Reasoning: Chain-of-Thought steps with status indicators
  - Input bar: Prompt and current input buffer
  """

  import TermUI.Component.Helpers

  alias JidoCode.Tools.Display
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias TermUI.Renderer.Style
  alias TermUI.Theme
  alias TermUI.Widgets.TextInput

  # Double-line box drawing characters
  @border_chars %{
    top_left: "╔",
    top_right: "╗",
    bottom_left: "╚",
    bottom_right: "╝",
    horizontal: "═",
    vertical: "║",
    # T-connectors for single-line horizontal meeting double-line vertical
    t_left: "╟",
    t_right: "╢"
  }

  @modal_border_chars %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─",
    vertical: "│"
  }

  # Status indicator characters for tab rendering
  @status_indicators %{
    # Rotating arrow (U+27F3)
    processing: "⟳",
    # Check mark (U+2713)
    idle: "✓",
    # X mark (U+2717)
    error: "✗",
    # Use same as idle when unconfigured
    unconfigured: "✓"
  }

  # ============================================================================
  # Border / Frame
  # ============================================================================

  @doc """
  Wraps content in a double-line border that fills the window.

  The border adapts to the window size and the content is rendered inside.
  """
  @spec render_with_border(Model.t(), TermUI.View.t()) :: TermUI.View.t()
  def render_with_border(state, content) do
    {width, height} = state.window
    # Use same color as separators for consistent appearance
    border_style = Style.new(fg: Theme.get_color(:secondary) || :bright_black)

    # Content area is inside the border (width - 2 for side borders, height - 2 for top/bottom)
    # Individual elements handle their own padding; separators span full width
    content_height = max(height - 2, 1)
    content_width = max(width - 2, 1)

    # Build the border lines
    top_border = render_top_border(width, border_style)
    bottom_border = render_bottom_border(width, border_style)

    # Create middle section with side borders and content
    middle_rows = render_middle_rows(content, content_width, content_height, border_style)

    # Use a box with explicit dimensions to fill the terminal
    box(
      [
        stack(:vertical, [top_border | middle_rows] ++ [bottom_border])
      ],
      width: width,
      height: height
    )
  end

  @doc """
  Renders content in a modal dialog with single-line border and padding.
  Uses a lighter color than the main TUI border.

  Options:
  - `:modal_width` - Width of the modal (default: 60% of window width, max 80)
  - `:modal_height` - Height of the modal (default: 60% of window height, max 20)
  """
  @spec render_modal_with_border(Model.t(), TermUI.View.t(), keyword()) :: TermUI.View.t()
  def render_modal_with_border(state, content, opts \\ []) do
    {width, height} = state.window
    border_style = Style.new(fg: :bright_black)

    # Calculate modal dimensions - centered dialog, not full screen
    default_modal_width = min(div(width * 60, 100), 80)
    default_modal_height = min(div(height * 60, 100), 20)

    modal_width = Keyword.get(opts, :modal_width, default_modal_width) |> max(20)
    modal_height = Keyword.get(opts, :modal_height, default_modal_height) |> max(8)

    # Content area is inside the modal border
    content_height = max(modal_height - 2, 1)
    content_width = max(modal_width - 2, 1)

    # Build the modal border lines
    top_border = render_modal_top_border(modal_width, border_style)
    bottom_border = render_modal_bottom_border(modal_width, border_style)

    # Create middle section with side borders and content
    middle_rows = render_modal_middle_rows(content, content_width, content_height, border_style)

    # Build the modal box
    modal_box = stack(:vertical, [top_border | middle_rows] ++ [bottom_border])

    # Calculate padding to center the modal
    h_padding = div(width - modal_width, 2)
    v_padding = div(height - modal_height, 2)

    # Create padding rows (empty lines above and below the modal)
    padding_row = text(String.duplicate(" ", width), nil)
    top_padding = List.duplicate(padding_row, v_padding)
    bottom_padding = List.duplicate(padding_row, max(height - modal_height - v_padding, 0))

    # Wrap modal with horizontal padding using spaces
    left_pad = text(String.duplicate(" ", h_padding), nil)
    right_pad = text(String.duplicate(" ", max(width - modal_width - h_padding, 0)), nil)
    padded_modal = stack(:horizontal, [left_pad, modal_box, right_pad])

    # Stack everything vertically
    box(
      [
        stack(:vertical, top_padding ++ [padded_modal] ++ bottom_padding)
      ],
      width: width,
      height: height
    )
  end

  @doc """
  Renders a dialog box with single-line border at the specified dimensions.
  Used for overlay dialogs that are positioned separately.
  """
  @spec render_dialog_box(TermUI.View.t(), pos_integer(), pos_integer()) :: TermUI.View.t()
  def render_dialog_box(content, width, height) do
    border_style = Style.new(fg: :bright_black)

    # Content area is inside the border
    content_height = max(height - 2, 1)
    content_width = max(width - 2, 1)

    # Build the border lines
    top_border = render_modal_top_border(width, border_style)
    bottom_border = render_modal_bottom_border(width, border_style)

    # Create middle section with side borders and content
    middle_rows = render_modal_middle_rows(content, content_width, content_height, border_style)

    # Build the dialog box
    stack(:vertical, [top_border | middle_rows] ++ [bottom_border])
  end

  defp render_modal_top_border(width, style) do
    inner_width = max(width - 2, 0)

    line =
      @modal_border_chars.top_left <>
        String.duplicate(@modal_border_chars.horizontal, inner_width) <>
        @modal_border_chars.top_right

    text(line, style)
  end

  defp render_modal_bottom_border(width, style) do
    inner_width = max(width - 2, 0)

    line =
      @modal_border_chars.bottom_left <>
        String.duplicate(@modal_border_chars.horizontal, inner_width) <>
        @modal_border_chars.bottom_right

    text(line, style)
  end

  defp render_modal_middle_rows(content, content_width, content_height, border_style) do
    left_border = text(@modal_border_chars.vertical, border_style)
    right_border = text(@modal_border_chars.vertical, border_style)

    # Create a box for the content area with fixed dimensions
    content_box = box([content], width: content_width, height: content_height)

    # Single row containing left border, content box, and right border
    [stack(:horizontal, [left_border, content_box, right_border])]
  end

  defp render_top_border(width, style) do
    inner_width = max(width - 2, 0)
    horizontal = String.duplicate(@border_chars.horizontal, inner_width)
    line = @border_chars.top_left <> horizontal <> @border_chars.top_right
    text(line, style)
  end

  defp render_bottom_border(width, style) do
    inner_width = max(width - 2, 0)
    horizontal = String.duplicate(@border_chars.horizontal, inner_width)
    line = @border_chars.bottom_left <> horizontal <> @border_chars.bottom_right
    text(line, style)
  end

  # Renders all middle rows (between top and bottom border)
  # Each row has: left border | content | right border
  # Individual content elements handle their own padding; separators span full width
  defp render_middle_rows(content, content_width, content_height, border_style) do
    # Create multi-line border strings that span the full height
    left_border_str =
      (@border_chars.vertical <> "\n")
      |> String.duplicate(content_height)
      |> String.trim_trailing("\n")

    right_border_str =
      (@border_chars.vertical <> "\n")
      |> String.duplicate(content_height)
      |> String.trim_trailing("\n")

    left_border = text(left_border_str, border_style)
    right_border = text(right_border_str, border_style)

    # Create a box for the content area with fixed dimensions
    content_box = box([content], width: content_width, height: content_height)

    # Single row containing left border, content box, and right border
    [stack(:horizontal, [left_border, content_box, right_border])]
  end

  # ============================================================================
  # Separator
  # ============================================================================

  @doc """
  Renders a horizontal separator line using single-line box characters.
  Connects to the outer double-line border using T-connectors.
  """
  @spec render_separator(Model.t()) :: TermUI.View.t()
  def render_separator(state) do
    {width, _height} = state.window
    # Full width between borders (width - 2 for the side borders)
    inner_width = max(width - 2, 1)
    # Horizontal line width (excluding T-connectors)
    line_width = max(inner_width - 2, 0)

    separator_style = Style.new(fg: Theme.get_color(:secondary) || :bright_black)

    # Use T-connectors at edges to connect to the double-line vertical border
    separator_line =
      @border_chars.t_left <> String.duplicate("─", line_width) <> @border_chars.t_right

    text(separator_line, separator_style)
  end

  # ============================================================================
  # Status Bar
  # ============================================================================

  @doc """
  Renders the top status bar with provider/model info and agent status.
  Includes 1-char padding on each side. Content width is window width - 4.
  """
  @spec render_status_bar(Model.t()) :: TermUI.View.t()
  def render_status_bar(state) do
    {width, _height} = state.window
    # Content width excludes borders (2) and padding (2)
    content_width = max(width - 4, 1)

    case Model.get_active_session(state) do
      nil ->
        # No active session - show simplified status
        render_status_bar_no_session(state, content_width)

      session ->
        # Active session - show full session info
        render_status_bar_with_session(state, session, content_width)
    end
  end

  # Status bar when no active session
  defp render_status_bar_no_session(state, content_width) do
    config_text = format_config(state.config)
    status_text = format_status(Model.get_active_agent_status(state))

    full_text = "No active session | #{config_text} | #{status_text}"
    padded_text = pad_or_truncate(full_text, content_width)

    bar_style = build_status_bar_style(state)
    # Add 1-char padding on each side
    stack(:horizontal, [text(" "), text(padded_text, bar_style), text(" ")])
  end

  # Status bar with active session info
  defp render_status_bar_with_session(state, session, content_width) do
    alias JidoCode.TUI.MessageHandlers

    # Session count and position
    session_count = Model.session_count(state)
    session_index = Enum.find_index(state.session_order, &(&1 == session.id))
    position_text = "[#{session_index + 1}/#{session_count}]"

    # Session name (truncated)
    session_name = truncate(session.name, 20)

    # Project path (truncated, show last 2 segments)
    path_text = format_project_path(session.project_path, 25)

    # Programming language (with icon)
    language = Map.get(session, :language, :elixir)
    language_text = JidoCode.Language.display_name(language)

    # Model info from session config or global config
    session_config = Map.get(session, :config) || %{}
    provider = Map.get(session_config, :provider) || state.config.provider
    model = Map.get(session_config, :model) || state.config.model
    model_text = format_model(provider, model)

    # Get cumulative usage from session UI state
    ui_state = Model.get_active_ui_state(state)
    usage = if ui_state, do: Map.get(ui_state, :usage), else: nil
    usage_text = MessageHandlers.format_usage_compact(usage)

    # Agent status for this session
    session_status = Model.get_session_status(session.id)
    status_text = format_status(session_status)

    # CoT indicator
    cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""

    # Build full text: "[1/3] project-name | ~/path | Language | model | usage | status"
    full_text =
      "#{position_text} #{session_name} | #{path_text} | #{language_text} | #{model_text} | #{usage_text} | #{status_text}#{cot_indicator}"

    padded_text = pad_or_truncate(full_text, content_width)

    bar_style = build_status_bar_style_for_session(state, session_status)
    # Add 1-char padding on each side
    stack(:horizontal, [text(" "), text(padded_text, bar_style), text(" ")])
  end

  @doc """
  Formats a project path for display, replacing home directory with ~ and truncating if needed.
  """
  def format_project_path(path, max_length) do
    # Replace home directory with ~
    home_dir = System.user_home!()
    display_path = String.replace_prefix(path, home_dir, "~")

    # Truncate from start if too long
    if String.length(display_path) > max_length do
      "..." <> String.slice(display_path, -(max_length - 3)..-1//1)
    else
      display_path
    end
  end

  # Format model text
  defp format_model(provider, model) do
    provider_text = if provider, do: "#{provider}", else: "none"
    model_text = if model, do: "#{model}", else: "none"
    "⬢ #{provider_text} | ◆ #{model_text}"
  end

  # Build status bar style based on session status
  defp build_status_bar_style_for_session(state, session_status) do
    fg_color =
      cond do
        session_status == :error -> Theme.get_semantic(:error) || :red
        session_status == :processing -> Theme.get_semantic(:warning) || :yellow
        has_active_reasoning?(state) -> Theme.get_color(:accent) || :magenta
        true -> Theme.get_color(:foreground) || :white
      end

    Style.new(fg: fg_color, bg: :black)
  end

  @doc """
  Renders the bottom help bar with keyboard shortcuts.
  Includes 1-char padding on each side. Content width is window width - 4.
  """
  @spec render_help_bar(Model.t()) :: TermUI.View.t()
  def render_help_bar(state) do
    {width, _height} = state.window
    # Content width excludes borders (2) and padding (2)
    content_width = max(width - 4, 1)

    reasoning_hint = if state.show_reasoning, do: "Ctrl+R: Hide", else: "Ctrl+R: Reasoning"
    tools_hint = if state.show_tool_details, do: "Ctrl+T: Hide", else: "Ctrl+T: Tools"
    hints = "#{reasoning_hint} | #{tools_hint} | Ctrl+M: Model | Ctrl+X: Quit"

    padded_text = pad_or_truncate(hints, content_width)
    bar_style = Style.new(fg: Theme.get_color(:foreground) || :white, bg: :black)

    # Add 1-char padding on each side
    stack(:horizontal, [text(" "), text(padded_text, bar_style), text(" ")])
  end

  # Pad with spaces or truncate text to exact width
  defp pad_or_truncate(text, width) do
    len = String.length(text)

    cond do
      len == width -> text
      len < width -> text <> String.duplicate(" ", width - len)
      true -> String.slice(text, 0, width)
    end
  end

  defp build_status_bar_style(state) do
    agent_status = Model.get_active_agent_status(state)

    fg_color =
      cond do
        agent_status == :error -> Theme.get_semantic(:error) || :red
        agent_status == :processing -> Theme.get_semantic(:warning) || :yellow
        has_active_reasoning?(state) -> Theme.get_color(:accent) || :magenta
        true -> Theme.get_color(:foreground) || :white
      end

    Style.new(fg: fg_color, bg: :black)
  end

  defp has_active_reasoning?(state) do
    ui_state = Model.get_active_ui_state(state)
    reasoning_steps = if ui_state, do: ui_state.reasoning_steps, else: []

    reasoning_steps != [] and
      Enum.any?(reasoning_steps, fn step ->
        Map.get(step, :status) == :active
      end)
  end

  defp format_status(:idle), do: "⚙  Idle"
  defp format_status(:processing), do: "⚙  Streaming..."
  defp format_status(:error), do: "⚙  Error"
  defp format_status(:unconfigured), do: "⚙  Idle"

  defp format_config(config) do
    provider = config[:provider] || "none"
    model = config[:model] || "none"
    "⬢ #{provider} | ◆ #{model}"
  end

  # ============================================================================
  # Conversation Area
  # ============================================================================

  @doc """
  Renders the conversation area with messages, tool calls, and streaming content.
  Fills the available height between status bar and input/help bars.
  Includes 1-char padding on each side.
  """
  @spec render_conversation(Model.t()) :: TermUI.View.t()
  def render_conversation(state) do
    {width, height} = state.window
    ui_state = Model.get_active_ui_state(state)

    # Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
    available_height = max(height - 8, 1)
    # Content width excludes borders (2) and padding (2)
    content_width = max(width - 4, 1)

    # Check if there's content using session's UI state
    messages = if ui_state, do: ui_state.messages, else: []
    tool_calls = if ui_state, do: ui_state.tool_calls, else: []
    is_streaming = if ui_state, do: ui_state.is_streaming, else: false
    has_content = messages != [] or tool_calls != [] or is_streaming

    lines =
      if has_content do
        render_conversation_lines(state, available_height, content_width)
      else
        render_empty_conversation_lines(content_width)
      end

    # Pad with empty lines to fill the available height
    padded_lines = pad_lines_to_height(lines, available_height, content_width)

    # Wrap each line with 1-char padding on each side
    padded_lines_with_margin =
      Enum.map(padded_lines, fn line ->
        stack(:horizontal, [text(" "), line, text(" ")])
      end)

    stack(:vertical, padded_lines_with_margin)
  end

  defp render_empty_conversation_lines(content_width) do
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

    [
      text(pad_or_truncate("", content_width), nil),
      text(
        pad_or_truncate("No messages yet. Type a message and press Enter.", content_width),
        muted_style
      )
    ]
  end

  # Pad lines list with empty lines to fill the target height
  @doc """
  Pads a list of view elements to reach a target height by adding empty lines.
  If the list exceeds the target height, truncates it.
  """
  def pad_lines_to_height(lines, target_height, content_width) do
    current_count = length(lines)

    if current_count >= target_height do
      Enum.take(lines, target_height)
    else
      padding_count = target_height - current_count
      padding = for _ <- 1..padding_count, do: text(pad_or_truncate("", content_width), nil)
      lines ++ padding
    end
  end

  # Returns a list of render nodes (lines) for the conversation content
  defp render_conversation_lines(state, available_height, width) do
    ui_state = Model.get_active_ui_state(state)
    messages = if ui_state, do: ui_state.messages, else: []
    tool_calls = if ui_state, do: ui_state.tool_calls, else: []
    is_streaming = if ui_state, do: ui_state.is_streaming, else: false
    streaming_message = if ui_state, do: ui_state.streaming_message, else: nil

    # Messages are stored in reverse order (newest first), so reverse for display
    message_lines = Enum.flat_map(Enum.reverse(messages), &format_message(&1, width))

    # Tool calls are stored in reverse order (newest first), so reverse for display
    tool_call_lines =
      tool_calls
      |> Enum.reverse()
      |> Enum.flat_map(&format_tool_call_entry(&1, state.show_tool_details))

    # Build streaming message line if streaming
    streaming_lines =
      if is_streaming and streaming_message != nil do
        format_streaming_message(streaming_message, width)
      else
        []
      end

    # Combine all lines (tool calls appear after messages, streaming at the end)
    all_lines = message_lines ++ tool_call_lines ++ streaming_lines
    total_lines = length(all_lines)

    # Calculate which lines to show based on scroll offset
    end_index = total_lines - state.scroll_offset
    start_index = max(end_index - available_height, 0)

    all_lines
    |> Enum.slice(start_index, available_height)
  end

  defp format_streaming_message(content, width) do
    ts = TUI.format_timestamp(DateTime.utc_now())
    prefix = "Assistant: "
    cursor = "▌"
    style = Style.new(fg: Theme.get_color(:foreground) || :white)

    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)
    content_with_cursor = content <> cursor

    lines = TUI.wrap_text(content_with_cursor, content_width)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      if index == 0 do
        text("#{ts} #{prefix}#{line}", style)
      else
        padding = String.duplicate(" ", prefix_len)
        text("#{padding}#{line}", style)
      end
    end)
  end

  defp format_message(%{role: role, content: content, timestamp: timestamp} = message, width) do
    ts = TUI.format_timestamp(timestamp)
    prefix = role_prefix(role)
    style = role_style(role)

    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)
    lines = TUI.wrap_text(content, content_width)

    message_lines =
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, index} ->
        if index == 0 do
          text("#{ts} #{prefix}#{line}", style)
        else
          padding = String.duplicate(" ", prefix_len)
          text("#{padding}#{line}", style)
        end
      end)

    # Add usage line above assistant messages if usage data is present
    case {role, Map.get(message, :usage)} do
      {:assistant, usage} when is_map(usage) ->
        usage_line = render_usage_line(usage)
        [usage_line | message_lines]

      _ ->
        message_lines
    end
  end

  # Fallback for messages without timestamp (legacy format)
  defp format_message(%{role: role, content: content}, width) do
    format_message(%{role: role, content: content, timestamp: DateTime.utc_now()}, width)
  end

  defp role_prefix(:user), do: "You: "
  defp role_prefix(:assistant), do: "Assistant: "
  defp role_prefix(:system), do: "System: "

  defp role_style(:user), do: Style.new(fg: Theme.get_semantic(:info) || :cyan)
  defp role_style(:assistant), do: Style.new(fg: Theme.get_color(:foreground) || :white)
  defp role_style(:system), do: Style.new(fg: Theme.get_semantic(:warning) || :yellow)

  # Renders a usage line for display above assistant messages
  defp render_usage_line(usage) do
    alias JidoCode.TUI.MessageHandlers
    usage_text = MessageHandlers.format_usage_detailed(usage)
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)
    text(usage_text, muted_style)
  end

  # ============================================================================
  # Tool Calls
  # ============================================================================

  @doc """
  Formats a tool call entry for display.

  Returns a list of render nodes representing the tool call and its result.
  """
  @spec format_tool_call_entry(Model.tool_call_entry(), boolean()) :: [TermUI.View.t()]
  def format_tool_call_entry(entry, show_details) do
    call_line = render_tool_call_line(entry)
    result_lines = render_tool_result_lines(entry, show_details)

    [call_line | result_lines]
  end

  defp render_tool_call_line(entry) do
    ts = TUI.format_timestamp(entry.timestamp)
    formatted = Display.format_tool_call(entry.tool_name, entry.params, entry.call_id)
    style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

    text("#{ts} #{formatted}", style)
  end

  defp render_tool_result_lines(%{result: nil}, _show_details) do
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black, attrs: [:dim])
    [text("       ⋯ executing...", muted_style)]
  end

  defp render_tool_result_lines(%{result: result}, show_details) do
    {icon, style} = tool_result_style(result.status)
    duration_text = "[#{result.duration_ms}ms]"

    content_preview =
      if show_details do
        result.content
      else
        Display.truncate_content(result.content, 80)
      end

    result_text = "       #{icon} #{result.tool_name} #{duration_text}: #{content_preview}"
    [text(result_text, style)]
  end

  defp tool_result_style(:ok), do: {"✓", Style.new(fg: Theme.get_semantic(:success) || :green)}
  defp tool_result_style(:error), do: {"✗", Style.new(fg: Theme.get_semantic(:error) || :red)}

  defp tool_result_style(:timeout),
    do: {"⏱", Style.new(fg: Theme.get_semantic(:warning) || :yellow)}

  # ============================================================================
  # Input Bar
  # ============================================================================

  @doc """
  Renders the input bar using the TextInput widget.
  Shows a prompt indicator followed by the input area.
  Includes 1-char padding on each side.
  """
  @spec render_input_bar(Model.t()) :: TermUI.View.t()
  def render_input_bar(state) do
    {width, _height} = state.window
    # Content width excludes borders (2), padding (2), and prompt "> " (2)
    input_width = max(width - 6, 20)

    prompt_style = Style.new(fg: Theme.get_color(:secondary) || :green)

    # Get text input from active session's UI state
    text_input = Model.get_active_text_input(state)

    # Render TextInput widget (or empty space if no active session)
    input_area = %{width: input_width, height: 1}

    text_input_node =
      if text_input do
        TextInput.render(text_input, input_area)
      else
        text(String.duplicate(" ", input_width))
      end

    # Add 1-char padding on left, prompt, input, padding on right
    stack(:horizontal, [
      text(" "),
      text("> ", prompt_style),
      text_input_node,
      text(" ")
    ])
  end

  # ============================================================================
  # Mode Bar
  # ============================================================================

  @doc """
  Renders the mode bar showing the current agent mode and language.
  Displays below the input bar with the active thinking/reasoning mode on the left
  and the current programming language on the right.
  """
  @spec render_mode_bar(Model.t()) :: TermUI.View.t()
  def render_mode_bar(state) do
    {width, _height} = state.window
    # Content width excludes borders (2) and padding (2)
    content_width = max(width - 4, 20)

    # Get current mode from agent_activity
    mode = get_display_mode(state)
    mode_text = format_mode_name(mode)

    # Get language from active session
    language = get_session_language(state)
    language_icon = JidoCode.Language.icon(language)
    language_name = JidoCode.Language.display_name(language)
    language_text = "#{language_icon} #{language_name}"

    # Style for mode bar
    label_style = Style.new(fg: :bright_black)
    mode_style = Style.new(fg: Theme.get_color(:accent) || :cyan)
    language_style = Style.new(fg: Theme.get_color(:accent) || :cyan)

    # Left side: "Mode: chat"
    mode_label = text("Mode: ", label_style)
    mode_display = text(mode_text, mode_style)

    # Right side: "💧 Elixir"
    language_display = text(language_text, language_style)

    # Calculate padding to fill width between mode and language
    # "Mode: " (6) + mode_text + language_text + 2 (side padding)
    left_width = 6 + String.length(mode_text)
    right_width = String.length(language_text)
    padding_width = max(content_width - left_width - right_width, 1)
    padding = text(String.duplicate(" ", padding_width))

    # Layout: " Mode: chat          💧 Elixir "
    stack(:horizontal, [
      text(" "),
      mode_label,
      mode_display,
      padding,
      language_display,
      text(" ")
    ])
  end

  # Get the language from the active session, defaulting to :elixir
  defp get_session_language(state) do
    case Model.get_active_session(state) do
      nil -> JidoCode.Language.default()
      session -> Map.get(session, :language, JidoCode.Language.default())
    end
  end

  # Get the display mode from agent activity or default to chat
  defp get_display_mode(state) do
    case Model.get_active_agent_activity(state) do
      {:thinking, mode} -> mode
      _ -> :chat
    end
  end

  # Format mode name for display
  defp format_mode_name(:chat), do: "chat"
  defp format_mode_name(:chain_of_thought), do: "chain-of-thought"
  defp format_mode_name(:react), do: "react"
  defp format_mode_name(:tree_of_thoughts), do: "tree-of-thoughts"
  defp format_mode_name(:self_consistency), do: "self-consistency"
  defp format_mode_name(:program_of_thought), do: "program-of-thought"
  defp format_mode_name(:gepa), do: "gepa"
  defp format_mode_name(other) when is_atom(other), do: Atom.to_string(other)
  defp format_mode_name(_other), do: "unknown"

  # ============================================================================
  # Reasoning Panel
  # ============================================================================

  @doc """
  Renders the reasoning panel showing Chain-of-Thought steps.

  Steps are displayed with status indicators:
  - ○ pending (dim)
  - ● active (yellow)
  - ✓ complete (green)
  """
  @spec render_reasoning(Model.t()) :: TermUI.View.t()
  def render_reasoning(state) do
    ui_state = Model.get_active_ui_state(state)
    reasoning_steps = if ui_state, do: ui_state.reasoning_steps, else: []

    case reasoning_steps do
      [] -> render_empty_reasoning()
      steps -> render_reasoning_steps(steps)
    end
  end

  defp render_empty_reasoning do
    accent_style = Style.new(fg: Theme.get_color(:accent) || :magenta, attrs: [:bold])
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

    stack(:vertical, [
      text("Reasoning (Ctrl+R to hide)", accent_style),
      text("─────────────────────────", muted_style),
      text("No reasoning steps yet.", muted_style)
    ])
  end

  defp render_reasoning_steps(steps) do
    accent_style = Style.new(fg: Theme.get_color(:accent) || :magenta, attrs: [:bold])
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

    header = [
      text("Reasoning (Ctrl+R to hide)", accent_style),
      text("─────────────────────────", muted_style)
    ]

    # Steps are stored in reverse order (newest first), so reverse for display
    step_lines = Enum.map(Enum.reverse(steps), &format_reasoning_step/1)

    stack(:vertical, header ++ step_lines)
  end

  defp format_reasoning_step(%{step: step_text, status: status} = step) do
    {indicator, style} = step_indicator(status)
    confidence_text = format_confidence(step)

    text("#{indicator} #{step_text}#{confidence_text}", style)
  end

  # Handle steps that may be maps with string keys
  defp format_reasoning_step(step) when is_map(step) do
    step_text = Map.get(step, :step) || Map.get(step, "step") || "Unknown step"
    status = Map.get(step, :status) || Map.get(step, "status") || :pending
    status_atom = normalize_status(status)

    format_reasoning_step(%{
      step: step_text,
      status: status_atom,
      confidence: Map.get(step, :confidence)
    })
  end

  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status("pending"), do: :pending
  defp normalize_status("active"), do: :active
  defp normalize_status("complete"), do: :complete
  defp normalize_status(_), do: :pending

  defp step_indicator(:pending),
    do: {"○", Style.new(fg: Theme.get_semantic(:muted) || :bright_black)}

  defp step_indicator(:active),
    do: {"●", Style.new(fg: Theme.get_semantic(:warning) || :yellow, attrs: [:bold])}

  defp step_indicator(:complete), do: {"✓", Style.new(fg: Theme.get_semantic(:success) || :green)}

  defp format_confidence(%{confidence: confidence}) when is_number(confidence) do
    " (confidence: #{Float.round(confidence, 2)})"
  end

  defp format_confidence(_), do: ""

  @doc """
  Renders reasoning steps as a compact single-line display for narrow terminals.
  """
  @spec render_reasoning_compact(Model.t()) :: TermUI.View.t()
  def render_reasoning_compact(state) do
    case state.reasoning_steps do
      [] ->
        muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)
        text("Reasoning: (none)", muted_style)

      steps ->
        # Steps are stored in reverse order (newest first), so reverse for display
        step_indicators =
          Enum.map_join(Enum.reverse(steps), " │ ", fn step ->
            status = Map.get(step, :status) || :pending
            {indicator, _style} = step_indicator(status)
            step_text = Map.get(step, :step) || "?"
            short_text = String.slice(step_text, 0, 15)
            "#{indicator} #{short_text}"
          end)

        accent_style = Style.new(fg: Theme.get_color(:accent) || :magenta)
        text("Reasoning: #{step_indicators}", accent_style)
    end
  end

  # ============================================================================
  # Configuration Screen
  # ============================================================================

  @doc """
  Renders the configuration information or unconfigured screen.
  """
  @spec render_config_info(Model.t()) :: TermUI.View.t()
  def render_config_info(state) do
    case Model.get_active_agent_status(state) do
      :unconfigured ->
        warning_style = Style.new(fg: Theme.get_semantic(:warning) || :yellow, attrs: [:bold])
        muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

        stack(:vertical, [
          text("Configuration Required", warning_style),
          text("", nil),
          text("No provider or model configured.", nil),
          text("Create ~/.jido_code/settings.json with:", nil),
          text("", nil),
          text("  {", muted_style),
          text(~s(    "provider": "anthropic",), muted_style),
          text(~s(    "model": "claude-3-5-sonnet"), muted_style),
          text("  }", muted_style)
        ])

      _ ->
        success_style = Style.new(fg: Theme.get_semantic(:success) || :green, attrs: [:bold])

        stack(:vertical, [
          text("Ready", success_style),
          text("", nil),
          text("Provider: #{state.config.provider || "none"}", nil),
          text("Model: #{state.config.model || "none"}", nil)
        ])
    end
  end

  # ============================================================================
  # Tab Rendering Helpers (Task 4.3.1)
  # ============================================================================

  @doc """
  Truncates text to max_length, adding ellipsis if needed.

  If the text is longer than max_length, it is truncated to max_length - 3
  and "..." is appended. Text shorter than or equal to max_length is returned
  unchanged.

  ## Examples

      iex> truncate("short", 10)
      "short"

      iex> truncate("this is a long text", 10)
      "this is..."
  """
  @spec truncate(String.t(), pos_integer()) :: String.t()
  def truncate(text, max_length) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - 3) <> "..."
    end
  end

  @doc """
  Formats a tab label showing index and session name.

  Tab indices 1-9 are displayed as-is. Index 10 is displayed as "0" to match
  the Ctrl+0 keyboard shortcut. Session names are truncated to 15 characters
  with ellipsis if needed.

  ## Examples

      iex> session = %Session{id: "s1", name: "my-project"}
      iex> format_tab_label(session, 1)
      "1:my-project"

      iex> session = %Session{id: "s10", name: "tenth-session"}
      iex> format_tab_label(session, 10)
      "0:tenth-session"

      iex> session = %Session{id: "s1", name: "this-is-a-very-long-name"}
      iex> format_tab_label(session, 1)
      "1:this-is-a-ver..."
  """
  @spec format_tab_label(JidoCode.Session.t(), pos_integer()) :: String.t()
  def format_tab_label(session, index) do
    display_index = if index == 10, do: 0, else: index
    name = truncate(session.name, 15)
    "#{display_index}:#{name}"
  end

  @doc """
  Renders the tab bar showing all sessions.

  Returns nil if there are no sessions. Otherwise renders a horizontal row
  of tabs with the active tab highlighted.

  ## Examples

      iex> model = %Model{sessions: %{}, session_order: []}
      iex> render_tabs(model)
      nil

      iex> model = %Model{
      ...>   sessions: %{"s1" => %Session{id: "s1", name: "project"}},
      ...>   session_order: ["s1"],
      ...>   active_session_id: "s1"
      ...> }
      iex> render_tabs(model)
      # Returns tab bar view
  """
  @spec render_tabs(Model.t()) :: TermUI.View.t() | nil
  def render_tabs(%Model{sessions: sessions}) when map_size(sessions) == 0, do: nil

  def render_tabs(%Model{sessions: sessions, session_order: order, active_session_id: active_id}) do
    tabs =
      order
      |> Enum.with_index(1)
      |> Enum.map(fn {session_id, index} ->
        session = Map.get(sessions, session_id)
        label = format_tab_label(session, index)
        is_active = session_id == active_id
        # Query session status for indicator
        status = Model.get_session_status(session_id)
        render_single_tab(label, is_active, status)
      end)

    # Render tabs horizontally with separators
    tab_elements =
      tabs
      |> Enum.intersperse(
        text(" │ ", Style.new(fg: Theme.get_color(:secondary) || :bright_black))
      )

    # Add 1-char padding on each side
    stack(:horizontal, [text(" ") | tab_elements] ++ [text(" ")])
  end

  # Renders a single tab with appropriate styling and status indicator
  @spec render_single_tab(String.t(), boolean(), Model.agent_status()) :: TermUI.View.t()
  defp render_single_tab(label, is_active, status) do
    # Get status indicator character
    indicator = Map.get(@status_indicators, status, "?")

    # Build label with status: "⟳ 1:project"
    full_label = "#{indicator} #{label}"

    # Apply styling based on active state and status
    style = build_tab_style(is_active, status)

    text(" #{full_label} ", style)
  end

  # Builds tab style based on active state and status
  @spec build_tab_style(boolean(), Model.agent_status()) :: Style.t()
  defp build_tab_style(is_active, status) do
    base_style =
      if is_active do
        Style.new(fg: Theme.get_color(:primary) || :cyan, attrs: [:bold, :underline])
      else
        Style.new(fg: Theme.get_color(:secondary) || :bright_black)
      end

    # Override color for error status (always red)
    # Override color for active+processing (yellow for attention)
    case status do
      :error ->
        %{base_style | fg: Theme.get_semantic(:error) || :red}

      :processing when is_active ->
        %{base_style | fg: Theme.get_semantic(:warning) || :yellow}

      _ ->
        base_style
    end
  end
end
