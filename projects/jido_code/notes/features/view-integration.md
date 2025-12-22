# Feature: Phase 4.4 View Integration

## Status: 📋 PLANNED

## Problem Statement

Phase 4 has completed the model structure (4.1), PubSub message routing (4.2), and tab rendering (4.3). Now we need to integrate these components into the main view to display:

1. **Tab bar** - Visual tabs for all sessions (already rendered, needs integration)
2. **Session-specific content** - Conversation and input for the active session
3. **Welcome screen** - Initial state when no sessions exist
4. **Status bar updates** - Session-specific information display

The current `view/1` function shows a single conversation with a generic status bar. We need to update it to be session-aware, conditionally rendering content based on whether sessions exist and which session is active.

## Solution Overview

Update the TUI's `view/1` function and ViewHelpers to:

1. **Integrate tabs into view structure** - Add `render_tabs/1` output to all three layout variants (standard, sidebar, drawer)
2. **Render session-specific content** - Fetch active session state and pass to ConversationView widget
3. **Show welcome screen when empty** - Detect no sessions and render helpful getting-started screen
4. **Update status bar** - Show active session name, project path, model, and session count

All changes follow the Elm Architecture pattern already established in the TUI.

## Current State Analysis

### Already Implemented (Sections 4.1-4.3)

**Model Structure (4.1):**
- ✅ Model has `sessions`, `session_order`, `active_session_id` fields
- ✅ `Model.get_active_session/1` returns active Session struct
- ✅ `Model.get_active_session_state/1` fetches from Session.State
- ✅ Session management helpers (add, remove, switch, rename)

**PubSub Routing (4.2):**
- ✅ Messages include session_id for routing
- ✅ `subscribe_to_session/1` and `unsubscribe_from_session/1` implemented
- ✅ MessageHandlers accept session_id parameter

**Tab Rendering (4.3):**
- ✅ `render_tabs/1` returns nil when no sessions, otherwise renders tab bar
- ✅ `format_tab_label/2` with truncation and index mapping (10 -> 0)
- ✅ Status indicators: ⟳ (processing), ✓ (idle), ✗ (error), ○ (unconfigured)
- ✅ Active tab styling: bold, underline, cyan
- ✅ Inactive tab styling: muted (bright_black)

### Current View Structure

The `view/1` function currently has three layout variants:

```elixir
def view(state) do
  main_view = render_main_view(state)
  # ... overlay modals if present
end

defp render_main_view(state) do
  content =
    if state.show_reasoning do
      # Wide terminal: side-by-side or narrow: stacked
      if width >= 100, do: render_main_content_with_sidebar(state)
      else: render_main_content_with_drawer(state)
    else
      # Standard layout
      stack(:vertical, [
        ViewHelpers.render_status_bar(state),
        ViewHelpers.render_separator(state),
        render_conversation_area(state),
        # ... input, help bars
      ])
    end

  ViewHelpers.render_with_border(state, content)
end
```

**Note:** The tabs have already been integrated into all three layouts in Task 4.3.1:
- Lines 1574-1578: Standard layout includes tabs
- Lines 1599-1603: Sidebar layout includes tabs
- Lines 1624-1628: Drawer layout includes tabs

### Current Conversation Rendering

```elixir
defp render_conversation_area(state) do
  if state.conversation_view do
    # Uses ConversationView widget
    ConversationView.render(state.conversation_view, area)
  else
    # Falls back to ViewHelpers
    ViewHelpers.render_conversation(state)
  end
end
```

Currently uses `state.conversation_view` directly without considering active session state.

### Current Status Bar

```elixir
def render_status_bar(state) do
  config_text = format_config(state.config)  # "anthropic:claude-3-5-sonnet"
  status_text = format_status(state.agent_status)  # "Idle" | "Streaming..."
  cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""

  full_text = "#{config_text} | #{status_text}#{cot_indicator}"
  # ...
end
```

Currently shows global config and status, not session-specific.

## Technical Details

### Task 4.4.1: View Structure Updates

**Goal:** Update `view/1` to properly handle sessions

**Files to modify:**
- `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Changes:**

1. **Update render_main_view/1** - Add tab integration checks:
   ```elixir
   defp render_main_view(state) do
     content =
       if state.show_reasoning do
         # ... existing reasoning layouts
       else
         # Standard layout - tabs already integrated (lines 1574-1590)
         tabs_elements =
           case ViewHelpers.render_tabs(state) do
             nil -> []
             tabs -> [tabs, ViewHelpers.render_separator(state)]
           end

         stack(:vertical,
           tabs_elements ++
           [
             ViewHelpers.render_status_bar(state),
             ViewHelpers.render_separator(state),
             render_session_content(state),  # NEW: session-aware rendering
             # ... rest of layout
           ]
         )
       end

     ViewHelpers.render_with_border(state, content)
   end
   ```

2. **No changes needed to layout integration** - Tabs already integrated in all three layouts (4.3.1)

**Function signature:**
```elixir
@spec render_main_view(Model.t()) :: TermUI.View.t()
defp render_main_view(state)
```

### Task 4.4.2: Session Content Rendering

**Goal:** Render active session's conversation and input

**Files to modify:**
- `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**New function - render_session_content/1:**

```elixir
@doc false
@spec render_session_content(Model.t()) :: TermUI.View.t()
defp render_session_content(%Model{active_session_id: nil} = state) do
  # No active session - show welcome screen
  render_welcome_screen(state)
end

defp render_session_content(%Model{active_session_id: session_id} = state) do
  # Fetch session state from Session.State GenServer
  case Model.get_active_session_state(state) do
    nil ->
      # Session state not found - show error message
      render_session_error(state, session_id)

    session_state ->
      # Render conversation using session's state
      render_conversation_for_session(state, session_state)
  end
end

# Helper to render conversation with session state
defp render_conversation_for_session(state, session_state) do
  if state.conversation_view do
    # Update ConversationView with session's messages
    updated_view = ConversationView.set_messages(
      state.conversation_view,
      Map.get(session_state, :messages, [])
    )

    # Update streaming state if session is streaming
    updated_view =
      if Map.get(session_state, :is_streaming, false) do
        streaming_msg = Map.get(session_state, :streaming_message, "")
        # ConversationView handles streaming internally
        updated_view
      else
        updated_view
      end

    {width, height} = state.window
    available_height = max(height - 8, 1)
    content_width = max(width - 2, 1)
    area = %{x: 0, y: 0, width: content_width, height: available_height}

    ConversationView.render(updated_view, area)
  else
    # Fallback to ViewHelpers (shouldn't happen in normal operation)
    ViewHelpers.render_conversation(state)
  end
end

defp render_session_error(state, session_id) do
  {width, height} = state.window
  content_width = max(width - 2, 1)
  available_height = max(height - 8, 1)

  error_style = Style.new(fg: Theme.get_semantic(:error) || :red)
  muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)

  lines = [
    text("Session Error", error_style),
    text("", nil),
    text("Session #{session_id} state not found.", muted_style),
    text("Try closing and reopening the session.", muted_style)
  ]

  padded_lines = pad_lines_to_height(lines, available_height, content_width)
  stack(:vertical, padded_lines)
end
```

**Integration point:**
Replace `render_conversation_area(state)` calls with `render_session_content(state)` in:
- Line 1585: Standard layout
- Line 1611: Sidebar layout (inside horizontal stack)
- Line 1635: Drawer layout

**Dependencies:**
- `Model.get_active_session_state/1` (already implemented in 4.1.2)
- `ConversationView.set_messages/2` (already exists)
- Session.State stores messages, streaming_message, is_streaming

### Task 4.4.3: Welcome Screen

**Goal:** Create welcoming screen for empty session list

**Files to modify:**
- `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**New function - render_welcome_screen/1:**

```elixir
@doc false
@spec render_welcome_screen(Model.t()) :: TermUI.View.t()
defp render_welcome_screen(state) do
  {width, height} = state.window
  content_width = max(width - 2, 1)
  available_height = max(height - 8, 1)

  # Styling
  title_style = Style.new(fg: Theme.get_color(:primary) || :cyan, attrs: [:bold])
  accent_style = Style.new(fg: Theme.get_color(:accent) || :magenta)
  muted_style = Style.new(fg: Theme.get_semantic(:muted) || :bright_black)
  info_style = Style.new(fg: Theme.get_semantic(:info) || :white)

  lines = [
    text("", nil),
    text("Welcome to JidoCode", title_style),
    text("", nil),
    text("No active sessions. Create a new session to get started:", info_style),
    text("", nil),
    text("Commands:", accent_style),
    text("  /session new <path>        Create session for project", muted_style),
    text("  /session new .             Create session for current directory", muted_style),
    text("  /resume                    List and resume saved sessions", muted_style),
    text("", nil),
    text("Keyboard Shortcuts:", accent_style),
    text("  Ctrl+N                     Create new session (future)", muted_style),
    text("  Ctrl+1 - Ctrl+0            Switch between sessions", muted_style),
    text("  Ctrl+W                     Close current session", muted_style),
    text("", nil)
  ]

  # Pad to fill available height
  padded_lines = pad_lines_to_height(lines, available_height, content_width)

  stack(:vertical, padded_lines)
end
```

**Helper function (if not already exists):**

```elixir
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
```

**Note:** Check if `pad_lines_to_height/3` already exists in ViewHelpers (it does at line 380-390), so we can use it.

### Task 4.4.4: Status Bar Updates

**Goal:** Show active session info in status bar

**Files to modify:**
- `/home/ducky/code/jido_code/lib/jido_code/tui/view_helpers.ex`

**Update render_status_bar/1:**

```elixir
@doc """
Renders the top status bar with session info, provider/model, and agent status.

Format when session active:
  [1/3] project-name | ~/path/to/project | anthropic:claude-3-5-sonnet | Idle

Format when no session:
  No active session | anthropic:claude-3-5-sonnet | Not Configured

Pads or truncates to fit the available width (window width - 2 for borders).
"""
@spec render_status_bar(Model.t()) :: TermUI.View.t()
def render_status_bar(state) do
  {width, _height} = state.window
  content_width = max(width - 2, 1)

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
  status_text = format_status(state.agent_status)

  full_text = "No active session | #{config_text} | #{status_text}"
  padded_text = pad_or_truncate(full_text, content_width)

  bar_style = build_status_bar_style(state)
  text(padded_text, bar_style)
end

# Status bar with active session info
defp render_status_bar_with_session(state, session, content_width) do
  # Session count and position
  session_count = Model.session_count(state)
  session_index = Enum.find_index(state.session_order, &(&1 == session.id))
  position_text = "[#{session_index + 1}/#{session_count}]"

  # Session name (truncated)
  session_name = truncate(session.name, 20)

  # Project path (truncated, show last 2 segments)
  path_text = format_project_path(session.project_path, 25)

  # Model info from session config or global config
  session_config = Map.get(session, :config, %{})
  provider = Map.get(session_config, :provider) || state.config.provider
  model = Map.get(session_config, :model) || state.config.model
  model_text = format_model(provider, model)

  # Agent status for this session
  session_status = Model.get_session_status(session.id)
  status_text = format_status(session_status)

  # CoT indicator
  cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""

  # Build full text: "[1/3] project-name | ~/path/to/project | anthropic:claude-3-5-sonnet | Idle"
  full_text = "#{position_text} #{session_name} | #{path_text} | #{model_text} | #{status_text}#{cot_indicator}"
  padded_text = pad_or_truncate(full_text, content_width)

  bar_style = build_status_bar_style_for_session(state, session_status)
  text(padded_text, bar_style)
end

# Format project path to show last N characters with ~/ for home
defp format_project_path(path, max_length) do
  # Replace home directory with ~
  home_dir = System.user_home!()
  display_path = String.replace_prefix(path, home_dir, "~")

  # Truncate from start if too long
  if String.length(display_path) > max_length do
    "..." <> String.slice(display_path, -(max_length - 3)..-1)
  else
    display_path
  end
end

# Format model text
defp format_model(nil, _), do: "No provider"
defp format_model(_, nil), do: "No model"
defp format_model(provider, model), do: "#{provider}:#{model}"

# Build status bar style based on session status
defp build_status_bar_style_for_session(state, session_status) do
  fg_color =
    cond do
      session_status == :error -> Theme.get_semantic(:error) || :red
      session_status == :unconfigured -> Theme.get_semantic(:error) || :red
      session_status == :processing -> Theme.get_semantic(:warning) || :yellow
      has_active_reasoning?(state) -> Theme.get_color(:accent) || :magenta
      true -> Theme.get_color(:foreground) || :white
    end

  Style.new(fg: fg_color, bg: :black)
end

# Existing helper (keep)
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
```

**New dependency:**
- `Model.session_count/1` (already implemented in 4.1.3, line 477)

## Success Criteria

### Functional Requirements

1. **View shows tabs** ✅ (Already done in 4.3.1)
   - Tab bar appears at top of TUI when sessions exist
   - No tab bar when sessions list is empty

2. **Session content renders**
   - Active session's conversation displays using ConversationView widget
   - Session's messages, streaming state correctly passed to widget
   - Switching sessions updates conversation view

3. **Welcome screen displays**
   - Shows when no sessions exist (active_session_id is nil)
   - Provides helpful commands and keyboard shortcuts
   - Styled consistently with TUI theme

4. **Status bar shows session info**
   - When session active: `[1/3] project-name | ~/path | provider:model | status`
   - When no session: `No active session | provider:model | status`
   - Session position, count displayed correctly
   - Project path truncated appropriately
   - Session-specific agent status shown

### Testing Requirements

**Unit Tests (Task 4.4.1):**
- [ ] Test `render_main_view/1` includes tabs when sessions exist
- [ ] Test `render_main_view/1` has no tabs when sessions empty
- [ ] Test tabs integrated in all 3 layouts (standard, sidebar, drawer) ✅ (Already done)

**Unit Tests (Task 4.4.2):**
- [ ] Test `render_session_content/1` shows welcome when active_session_id is nil
- [ ] Test `render_session_content/1` fetches session state via Model.get_active_session_state/1
- [ ] Test `render_session_content/1` passes session messages to ConversationView
- [ ] Test `render_session_content/1` shows error when session state not found

**Unit Tests (Task 4.4.3):**
- [ ] Test `render_welcome_screen/1` returns render tree
- [ ] Test welcome screen includes "Welcome to JidoCode" text
- [ ] Test welcome screen includes session creation commands
- [ ] Test welcome screen styled with theme colors

**Unit Tests (Task 4.4.4):**
- [ ] Test `render_status_bar/1` with no session shows "No active session"
- [ ] Test `render_status_bar/1` with session shows position "[1/3]"
- [ ] Test status bar shows session name (truncated to 20 chars)
- [ ] Test status bar shows project path (truncated to 25 chars)
- [ ] Test status bar shows session's model config
- [ ] Test status bar shows session-specific agent status
- [ ] Test `format_project_path/2` replaces home with ~
- [ ] Test `format_project_path/2` truncates long paths from start
- [ ] Test status bar color matches session status (error=red, processing=yellow)

## Implementation Plan

### Step 1: View Structure (Task 4.4.1) - 1 hour

**Actions:**
1. Update `render_main_view/1` to use `render_session_content(state)` instead of `render_conversation_area(state)`
2. Verify tabs already integrated in all layouts (lines 1574-1628)
3. Write unit tests for view structure

**Test coverage:**
- View structure with/without sessions
- Tab integration in all layouts

**Completion criteria:**
- View conditionally renders based on session existence
- All tests pass

### Step 2: Session Content Rendering (Task 4.4.2) - 2 hours

**Actions:**
1. Implement `render_session_content/1` with nil check
2. Implement `render_conversation_for_session/2` fetching session state
3. Implement `render_session_error/2` for edge case
4. Update conversation rendering to use session state
5. Write unit tests for content rendering

**Test coverage:**
- render_session_content with nil active_session_id
- render_session_content with valid session
- render_session_content with missing session state
- Conversation view receives session messages

**Completion criteria:**
- Active session conversation renders correctly
- Session state properly fetched and passed to widget
- All tests pass

### Step 3: Welcome Screen (Task 4.4.3) - 1 hour

**Actions:**
1. Implement `render_welcome_screen/1`
2. Add helpful text about session creation
3. Style with theme colors
4. Write unit tests for welcome screen

**Test coverage:**
- Welcome screen renders when no sessions
- Welcome text content correct
- Theme styling applied

**Completion criteria:**
- Welcome screen displays helpful information
- Styled consistently with TUI
- All tests pass

### Step 4: Status Bar Updates (Task 4.4.4) - 2 hours

**Actions:**
1. Update `render_status_bar/1` to check for active session
2. Implement `render_status_bar_no_session/2`
3. Implement `render_status_bar_with_session/3`
4. Implement `format_project_path/2` helper
5. Implement `format_model/2` helper
6. Implement `build_status_bar_style_for_session/2`
7. Write unit tests for status bar

**Test coverage:**
- Status bar with no session
- Status bar with active session
- Session position and count display
- Project path truncation
- Model config display
- Session status color

**Completion criteria:**
- Status bar shows session-specific information
- Path truncation works correctly
- Color reflects session status
- All tests pass

### Step 5: Integration and Manual Testing - 1 hour

**Actions:**
1. Run full test suite
2. Manual TUI testing:
   - Start with no sessions → welcome screen
   - Create session → tabs appear, status bar updates
   - Switch sessions → content and status bar update
   - Close last session → welcome screen
3. Fix any issues found

**Completion criteria:**
- All unit tests pass
- Manual testing confirms correct behavior
- No visual glitches or rendering issues

## Dependencies

**Phase 4 Prerequisites:**
- ✅ Section 4.1: Model structure with sessions, session_order, active_session_id
- ✅ Section 4.2: PubSub message routing with session_id
- ✅ Section 4.3: Tab rendering (render_tabs/1, format_tab_label/2)

**External Dependencies:**
- ✅ Session.State stores messages, streaming state
- ✅ Model.get_active_session/1 helper
- ✅ Model.get_active_session_state/1 helper
- ✅ Model.get_session_status/1 helper
- ✅ Model.session_count/1 helper
- ✅ ConversationView.set_messages/2
- ✅ ConversationView.render/2

**Blocks:**
- Section 4.5: Keyboard navigation (depends on this for view to update correctly on tab switch)

## Risk Assessment

### Low Risk
- **View structure changes** - Simple refactoring, well-defined interfaces
- **Welcome screen** - Standalone component, no complex state
- **Tab integration** - Already implemented in 4.3.1

### Medium Risk
- **Status bar complexity** - Multiple format variations, path truncation edge cases
  - *Mitigation:* Comprehensive unit tests for format_project_path/2

- **ConversationView integration** - Must correctly pass session state
  - *Mitigation:* Test with mock session state, verify messages passed correctly

### Monitoring
- Watch for rendering glitches during session switch
- Verify status bar doesn't overflow on narrow terminals
- Check welcome screen readability on small windows

## Future Enhancements (Out of Scope)

- Session-specific themes or color schemes
- Rich welcome screen with ASCII art
- Status bar customization via settings
- Session thumbnails/previews in tab bar
- Multiple active sessions (split panes)

## Notes

- This section completes the visual integration of multi-session support
- After this, Phase 4.5 will add keyboard shortcuts for navigation
- The welcome screen can be enhanced with more features in future phases
- Status bar format is intentionally concise to fit in typical terminal widths
