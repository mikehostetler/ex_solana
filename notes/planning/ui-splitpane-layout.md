# UI Layout Refactor: SplitPane with Accordion + Tabs

## Overview

Refactor the main TUI layout to use TermUI's SplitPane widget with:
- **Left pane (20%)**: Session list accordion (based on existing SessionSidebar)
- **Right pane (80%)**: FolderTabs with tab content (status bar, conversation, controls)
- **Constraint**: Minimum one tab always present

## Target Layout

```
┌──────────────────────────────────────────────────────────────────┐
│ SESSIONS          │╭───────────╮╭───────────╮╭─────────╮         │
│ ─────────────────││ Session 1 ╰│ Session 2 ╰│ New   + │         │
│                   │┌────────────────────────────────────────────┐│
│ ▼ → Session 1     ││ Status: ollama/qwen3:32b | Ready          ││
│     Info          │├────────────────────────────────────────────┤│
│       Created: 2h ││                                            ││
│       Path: ~/... ││   Conversation View (padded)               ││
│     Files         ││                                            ││
│       (empty)     ││                                            ││
│     Tools         │├────────────────────────────────────────────┤│
│       (empty)     ││ Ctrl+W Close | Ctrl+Tab Next | /help       ││
│                   │└────────────────────────────────────────────┘│
│ ▶ Session 2       │                                              │
│                   │                                              │
└──────────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Step 1: Create MainLayout Widget

Create `lib/jido_code/tui/widgets/main_layout.ex`:

- Wraps SplitPane with two panes (sidebar + content)
- Manages SplitPane state internally
- Provides API for updating sidebar and tab content
- Handles event routing to appropriate pane

```elixir
defmodule JidoCode.TUI.Widgets.MainLayout do
  @moduledoc """
  Main application layout using SplitPane with sidebar and tabs.
  """

  alias TermUI.Widgets.SplitPane, as: SP
  alias JidoCode.TUI.Widgets.{FolderTabs, SessionSidebar, Accordion}

  defstruct [
    :split_state,      # SplitPane state
    :sidebar_state,    # Accordion/SessionSidebar state
    :tabs_state,       # FolderTabs state
    :focused_pane      # :sidebar | :tabs
  ]

  def new(opts)
  def render(state, area)
  def handle_event(event, state)
  def update_sidebar(state, sidebar_state)
  def update_tabs(state, tabs_state)
end
```

### Step 2: Integrate SessionSidebar into Left Pane

Adapt existing SessionSidebar to work within SplitPane:

- SessionSidebar already renders to TermUI view tree
- Pass computed width from SplitPane pane size
- Keep accordion expand/collapse functionality
- Session selection triggers tab switch on right pane

### Step 3: Integrate FolderTabs into Right Pane

Connect FolderTabs widget to right pane:

- Each session = one tab
- Tab content includes:
  - Status bar (provider/model info)
  - Conversation view (existing ConversationView widget)
  - Controls bar (keyboard shortcuts)
- Enforce minimum 1 tab (create "New Session" tab if empty)
- Sync tab selection with sidebar active session

### Step 4: Update TUI Model

Add new fields to `JidoCode.TUI.Model`:

```elixir
defstruct [
  # ... existing fields ...

  # New layout state
  main_layout: nil,           # MainLayout state

  # Remove deprecated fields (gradual migration)
  # sidebar_visible: true,    # No longer needed - always visible
  # sidebar_width: 20,        # Now percentage-based in SplitPane
]
```

### Step 5: Update TUI View Function

Replace current layout logic in `view/1`:

```elixir
def view(state) do
  {width, height} = state.window
  area = %{x: 0, y: 0, width: width, height: height}

  # Render main layout (SplitPane with sidebar + tabs)
  main_content = MainLayout.render(state.main_layout, area)

  # Add input bar at bottom (outside SplitPane)
  stack(:vertical, [
    main_content,
    render_input_bar(state)
  ])
end
```

### Step 6: Update Event Handling

Route events to appropriate component:

```elixir
def update({:key_event, event}, state) do
  case MainLayout.handle_event(event, state.main_layout) do
    {:ok, new_layout} ->
      %{state | main_layout: new_layout}
    :ignore ->
      # Handle at TUI level (input, commands, etc.)
      handle_global_key(event, state)
  end
end
```

### Step 7: Sync Sessions with Tabs

When sessions change:

1. Session created → Add new tab
2. Session closed → Remove tab (unless last one)
3. Session switched → Select corresponding tab
4. Tab selected → Switch to corresponding session
5. Tab closed → Close session (unless last one)

```elixir
def sync_sessions_to_tabs(state) do
  tabs = Enum.map(state.session_order, fn session_id ->
    session = Map.get(state.sessions, session_id)
    %{
      id: session_id,
      label: truncate(session.name, 15),
      closeable: length(state.session_order) > 1,
      status: build_status_text(session),
      content: get_conversation_view(session_id),
      controls: "Ctrl+W Close | Ctrl+Tab Next | /help"
    }
  end)

  FolderTabs.new(tabs: tabs, selected: state.active_session_id)
end
```

### Step 8: Ensure Minimum One Tab

Add guard logic:

```elixir
def close_tab(state, tab_id) do
  if FolderTabs.tab_count(state.tabs_state) <= 1 do
    # Cannot close last tab - show message or create new session
    {:error, :last_tab}
  else
    # Proceed with close
    {:ok, FolderTabs.close_tab(state.tabs_state, tab_id)}
  end
end
```

## Files to Create/Modify

### New Files
- `lib/jido_code/tui/widgets/main_layout.ex` - Main layout widget

### Modified Files
- `lib/jido_code/tui.ex` - Update view/1 and event handling
- `lib/jido_code/tui/model.ex` - Add main_layout field
- `lib/jido_code/tui/widgets/folder_tabs.ex` - Minor adjustments if needed

### Test Files
- `test/jido_code/tui/widgets/main_layout_test.exs` - Layout tests
- Update existing TUI tests for new layout

## Migration Strategy

1. Create MainLayout widget (standalone, testable)
2. Add to TUI Model alongside existing layout
3. Feature flag to switch between old/new layout
4. Test thoroughly with new layout
5. Remove old layout code once stable

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Ctrl+Tab | Next tab |
| Ctrl+Shift+Tab | Previous tab |
| Ctrl+W | Close current tab (if not last) |
| Ctrl+1-9 | Switch to tab N |
| Ctrl+N | New session/tab |
| Tab | Cycle focus (sidebar ↔ tabs) |
| Arrow keys | Navigate within focused pane |

## Considerations

- **Performance**: SplitPane recalculates on resize, ensure smooth rendering
- **Focus management**: Clear visual indicator of which pane has focus
- **Responsive**: Handle narrow terminals gracefully (min widths)
- **Persistence**: Save/restore pane proportions across sessions
