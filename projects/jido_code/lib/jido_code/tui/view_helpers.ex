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
    vertical: "║"
  }

  @modal_border_chars %{
    top_left: "┌",
    top_right: "┐",
    bottom_left: "└",
    bottom_right: "┘",
    horizontal: "─",
    vertical: "│"
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
    content_height = max(height - 2, 1)
    content_width = max(width - 2, 1)

    # Build the border lines
    top_border = render_top_border(width, border_style)
    bottom_border = render_bottom_border(width, border_style)

    # Create middle section with side borders and content
    middle_rows = render_middle_rows(content, content_width, content_height, border_style)

    # Use a box with explicit dimensions to fill the terminal
    box([
      stack(:vertical, [top_border | middle_rows] ++ [bottom_border])
    ], width: width, height: height)
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
    box([
      stack(:vertical, top_padding ++ [padded_modal] ++ bottom_padding)
    ], width: width, height: height)
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
    line = @modal_border_chars.top_left <> String.duplicate(@modal_border_chars.horizontal, inner_width) <> @modal_border_chars.top_right
    text(line, style)
  end

  defp render_modal_bottom_border(width, style) do
    inner_width = max(width - 2, 0)
    line = @modal_border_chars.bottom_left <> String.duplicate(@modal_border_chars.horizontal, inner_width) <> @modal_border_chars.bottom_right
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

  # Convert TermUI.Style to TermUI.Renderer.Style
  # Theme returns TermUI.Style structs but the renderer expects TermUI.Renderer.Style
  defp theme_to_renderer_style(nil), do: nil
  defp theme_to_renderer_style(%TermUI.Style{fg: fg, bg: bg, attrs: attrs}) do
    Style.new(fg: fg, bg: bg, attrs: MapSet.to_list(attrs))
  end

  defp render_top_border(width, style) do
    inner_width = max(width - 2, 0)
    line = @border_chars.top_left <> String.duplicate(@border_chars.horizontal, inner_width) <> @border_chars.top_right
    text(line, style)
  end

  defp render_bottom_border(width, style) do
    inner_width = max(width - 2, 0)
    line = @border_chars.bottom_left <> String.duplicate(@border_chars.horizontal, inner_width) <> @border_chars.bottom_right
    text(line, style)
  end

  # Renders all middle rows (between top and bottom border)
  # Each row has: left border | content/padding | right border
  defp render_middle_rows(content, content_width, content_height, border_style) do
    left_border = text(@border_chars.vertical, border_style)
    right_border = text(@border_chars.vertical, border_style)

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
  Connects to the outer double-line border.
  """
  @spec render_separator(Model.t()) :: TermUI.View.t()
  def render_separator(state) do
    {width, _height} = state.window
    content_width = max(width - 2, 1)

    separator_style = Style.new(fg: Theme.get_color(:secondary) || :bright_black)

    # Use single-line horizontal character for the separator
    separator_line = String.duplicate("─", content_width)
    text(separator_line, separator_style)
  end

  # ============================================================================
  # Status Bar
  # ============================================================================

  @doc """
  Renders the top status bar with provider/model info and agent status.
  Pads or truncates to fit the available width (window width - 2 for borders).
  """
  @spec render_status_bar(Model.t()) :: TermUI.View.t()
  def render_status_bar(state) do
    {width, _height} = state.window
    content_width = max(width - 2, 1)

    config_text = format_config(state.config)
    status_text = format_status(state.agent_status)
    cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""

    full_text = "#{config_text} | #{status_text}#{cot_indicator}"
    # Pad or truncate to fill the content width exactly
    padded_text = pad_or_truncate(full_text, content_width)
    bar_style = build_status_bar_style(state)

    text(padded_text, bar_style)
  end

  @doc """
  Renders the bottom help bar with keyboard shortcuts.
  Pads or truncates to fit the available width (window width - 2 for borders).
  """
  @spec render_help_bar(Model.t()) :: TermUI.View.t()
  def render_help_bar(state) do
    {width, _height} = state.window
    content_width = max(width - 2, 1)

    reasoning_hint = if state.show_reasoning, do: "Ctrl+R: Hide", else: "Ctrl+R: Reasoning"
    tools_hint = if state.show_tool_details, do: "Ctrl+T: Hide", else: "Ctrl+T: Tools"
    hints = "#{reasoning_hint} | #{tools_hint} | Ctrl+M: Model | Ctrl+C: Quit"

    padded_text = pad_or_truncate(hints, content_width)
    bar_style = Style.new(fg: Theme.get_color(:foreground) || :white, bg: :black)

    text(padded_text, bar_style)
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
    fg_color =
      cond do
        state.agent_status == :error -> Theme.get_semantic(:error) || :red
        state.agent_status == :unconfigured -> Theme.get_semantic(:error) || :red
        state.config.provider == nil -> Theme.get_semantic(:error) || :red
        state.config.model == nil -> Theme.get_semantic(:warning) || :yellow
        state.agent_status == :processing -> Theme.get_semantic(:warning) || :yellow
        has_active_reasoning?(state) -> Theme.get_color(:accent) || :magenta
        true -> Theme.get_color(:foreground) || :white
      end

    Style.new(fg: fg_color, bg: :black)
  end

  defp has_active_reasoning?(state) do
    state.reasoning_steps != [] and
      Enum.any?(state.reasoning_steps, fn step ->
        Map.get(step, :status) == :active
      end)
  end

  defp format_status(:idle), do: "Idle"
  defp format_status(:processing), do: "Streaming..."
  defp format_status(:error), do: "Error"
  defp format_status(:unconfigured), do: "Not Configured"

  defp format_config(%{provider: nil}), do: "No provider"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  # ============================================================================
  # Conversation Area
  # ============================================================================

  @doc """
  Renders the conversation area with messages, tool calls, and streaming content.
  Fills the available height between status bar and input/help bars.
  """
  @spec render_conversation(Model.t()) :: TermUI.View.t()
  def render_conversation(state) do
    {width, height} = state.window
    # Available height: total height - 2 (borders) - 1 (status bar) - 3 (separators) - 1 (input bar) - 1 (help bar)
    available_height = max(height - 8, 1)
    content_width = max(width - 2, 1)
    has_content = state.messages != [] or state.tool_calls != [] or state.is_streaming

    lines = if has_content do
      render_conversation_lines(state, available_height, content_width)
    else
      render_empty_conversation_lines(content_width)
    end

    # Pad with empty lines to fill the available height
    padded_lines = pad_lines_to_height(lines, available_height, content_width)

    stack(:vertical, padded_lines)
  end

  defp render_empty_conversation_lines(content_width) do
    muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

    [
      text(pad_or_truncate("", content_width), nil),
      text(pad_or_truncate("No messages yet. Type a message and press Enter.", content_width), muted_style)
    ]
  end

  # Pad lines list with empty lines to fill the target height
  defp pad_lines_to_height(lines, target_height, content_width) do
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
    # Messages are stored in reverse order (newest first), so reverse for display
    message_lines = Enum.flat_map(Enum.reverse(state.messages), &format_message(&1, width))

    # Tool calls are stored in reverse order (newest first), so reverse for display
    tool_call_lines =
      state.tool_calls
      |> Enum.reverse()
      |> Enum.flat_map(&format_tool_call_entry(&1, state.show_tool_details))

    # Build streaming message line if streaming
    streaming_lines =
      if state.is_streaming and state.streaming_message != nil do
        format_streaming_message(state.streaming_message, width)
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

  defp format_message(%{role: role, content: content, timestamp: timestamp}, width) do
    ts = TUI.format_timestamp(timestamp)
    prefix = role_prefix(role)
    style = role_style(role)

    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)
    lines = TUI.wrap_text(content, content_width)

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
  defp tool_result_style(:timeout), do: {"⏱", Style.new(fg: Theme.get_semantic(:warning) || :yellow)}

  # ============================================================================
  # Input Bar
  # ============================================================================

  @doc """
  Renders the input bar using the TextInput widget.
  Shows a prompt indicator followed by the input area.
  """
  @spec render_input_bar(Model.t()) :: TermUI.View.t()
  def render_input_bar(state) do
    {width, _height} = state.window
    content_width = max(width - 4, 20)

    prompt_style = Style.new(fg: Theme.get_color(:secondary) || :green)

    # Render TextInput widget
    input_area = %{width: content_width, height: 1}
    text_input_node = TextInput.render(state.text_input, input_area)

    stack(:horizontal, [
      text("> ", prompt_style),
      text_input_node
    ])
  end

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
    case state.reasoning_steps do
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

  defp step_indicator(:pending), do: {"○", Style.new(fg: Theme.get_semantic(:muted) || :bright_black)}
  defp step_indicator(:active), do: {"●", Style.new(fg: Theme.get_semantic(:warning) || :yellow, attrs: [:bold])}
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
    case state.agent_status do
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
end
