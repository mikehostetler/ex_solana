# Feature: Tab Bar Component (Task 4.3.1)

## Problem Statement

Tasks 4.1, 4.2.1, 4.2.2, and 4.2.3 have established the multi-session infrastructure with Model structure, initialization, PubSub subscription management, and message routing. However, there is no visual representation of the multiple sessions. Users cannot see what sessions exist or which session is currently active.

Current issues:
- No visual tab bar showing available sessions
- No indication of which session is active
- No visual representation of session order/indices
- Users must rely on commands to know what sessions exist

Without a visual tab bar, the multi-session architecture is functional but invisible to users, making it difficult to understand and navigate between sessions.

## Solution Overview

Implement visual tab rendering using the TermUI Tabs widget to display sessions as numbered tabs with names. The tab bar will appear at the top of the TUI, showing:

1. **Numbered tabs** - Each session displayed as "index:name" (e.g., "1:my-app")
2. **Active indication** - Selected tab highlighted differently
3. **Tab order** - Tabs displayed in session_order
4. **Closeable tabs** - Each tab has close button for future close functionality

Key components:
1. `render_tabs/1` - Main rendering function using TermUI.Widgets.Tabs
2. `format_tab_label/2` - Label formatting with index and truncated name
3. `truncate/2` - Helper to truncate long session names
4. Tabs widget state management in Model struct
5. View integration at top of layout
6. Unit tests for all tab rendering logic

## Agent Consultations Performed

**Plan Agent** (a50d3a5):
- Researched TermUI.Widgets.Tabs API and discovered:
  - Tabs.new/1 accepts tabs list, selected ID, callbacks
  - Widget is stateful (uses StatefulComponent pattern)
  - Supports keyboard/mouse navigation
  - Requires tab data with :id, :label, :closeable fields
- Analyzed existing widget integration patterns:
  - ConversationView and TextInput follow stateful widget pattern
  - Widgets initialized in init/1, stored in model
  - Widget events routed through event_to_msg/2 and update/2
- Identified implementation approach following existing patterns

## Technical Details

### Files to Modify

1. **lib/jido_code/tui.ex**
   - Add `tabs_widget: nil` to Model struct
   - Update `@type t()` specification
   - Initialize tabs_widget in `init/1`
   - Integrate `render_tabs/1` in view layout
   - Update session management to rebuild tabs widget

2. **lib/jido_code/tui/view_helpers.ex**
   - Add `render_tabs/1` - Render tabs widget in view
   - Add `render_tabs_props/3` - Create props for Tabs.new/1
   - Add `format_tab_label/2` - Format label as "index:name"
   - Add `truncate/2` - Truncate text with ellipsis

3. **test/jido_code/tui_test.exs**
   - Unit tests for `format_tab_label/2`
   - Unit tests for `truncate/2`
   - Unit tests for tab rendering logic

### Current State

**Model Structure** (from Phase 4.1):
```elixir
defstruct [
  sessions: %{},           # session_id => Session.t()
  session_order: [],       # List of session_ids in tab order
  active_session_id: nil,  # Currently focused session
  # ... other fields
]
```

**TermUI Tabs Widget API** (from ../term_ui/lib/term_ui/widgets/tabs.ex):
```elixir
Tabs.new(opts)
# opts:
#   tabs: [%{id: term(), label: String.t(), closeable: boolean()}]
#   selected: term()  # tab ID that's selected
#   on_change: (tab_id -> msg)
#   on_close: (tab_id -> msg)
#   tab_style: keyword
#   selected_style: keyword
```

### Implementation Approach

#### Step 1: Add tabs_widget to Model

```elixir
# In lib/jido_code/tui.ex
defstruct [
  # ... existing fields
  tabs_widget: nil,  # TermUI.Widgets.Tabs state
  # ... rest
]

@type t :: %__MODULE__{
  # ... existing types
  tabs_widget: TermUI.Widgets.Tabs.state() | nil,
  # ... rest
}
```

#### Step 2: Implement Helper Functions

**truncate/2** (ViewHelpers):
```elixir
@spec truncate(String.t(), pos_integer()) :: String.t()
defp truncate(text, max_length) when byte_size(text) <= max_length, do: text
defp truncate(text, max_length) do
  String.slice(text, 0, max_length - 3) <> "..."
end
```

**format_tab_label/2** (ViewHelpers):
```elixir
@spec format_tab_label(Session.t(), pos_integer()) :: String.t()
defp format_tab_label(session, index) do
  display_index = if index == 10, do: 0, else: index
  name = truncate(session.name, 15)
  "#{display_index}:#{name}"
end
```

#### Step 3: Implement Tab Rendering

**render_tabs_props/3** (ViewHelpers):
```elixir
@spec render_tabs_props(%{String.t() => Session.t()}, [String.t()], String.t() | nil) :: keyword()
defp render_tabs_props(sessions, session_order, active_session_id) do
  tabs =
    session_order
    |> Enum.with_index(1)
    |> Enum.map(fn {session_id, index} ->
      session = Map.get(sessions, session_id)
      %{
        id: session_id,
        label: format_tab_label(session, index),
        closeable: true
      }
    end)

  [
    tabs: tabs,
    selected: active_session_id,
    on_change: fn tab_id -> {:select_session, tab_id} end,
    on_close: fn tab_id -> {:close_session, tab_id} end
  ]
end
```

**render_tabs/1** (ViewHelpers):
```elixir
@spec render_tabs(Model.t()) :: TermUI.View.t() | nil
def render_tabs(%{sessions: sessions}) when map_size(sessions) == 0, do: nil
def render_tabs(%{tabs_widget: nil}), do: nil
def render_tabs(%{tabs_widget: tabs_widget, window: {width, _height}}) do
  # Render the tabs widget
  TermUI.Widgets.Tabs.render(tabs_widget, %{width: width, height: 3})
end
```

#### Step 4: Initialize Tabs Widget

**In init/1** (TUI.ex):
```elixir
def init(_opts) do
  # ... load sessions

  # Initialize tabs widget
  tabs_widget =
    if map_size(sessions) > 0 do
      tabs_props = ViewHelpers.render_tabs_props(sessions, session_order, active_id)
      {:ok, widget_state} = TermUI.Widgets.Tabs.init(tabs_props)
      widget_state
    else
      nil
    end

  %Model{
    sessions: sessions,
    session_order: session_order,
    active_session_id: active_id,
    tabs_widget: tabs_widget,
    # ... other fields
  }
end
```

#### Step 5: Integrate in View

**Update render_main_view/1**:
```elixir
defp render_main_view(state) do
  content =
    stack(:vertical, [
      # Add tabs at top if sessions exist
      if map_size(state.sessions) > 0 do
        [
          ViewHelpers.render_tabs(state),
          ViewHelpers.render_separator(state)
        ]
      else
        []
      end,
      ViewHelpers.render_status_bar(state),
      ViewHelpers.render_separator(state),
      render_conversation_area(state),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_input_bar(state),
      ViewHelpers.render_separator(state),
      ViewHelpers.render_help_bar(state)
    ] |> List.flatten())

  ViewHelpers.render_with_border(state, content)
end
```

#### Step 6: Update Session Management

**Update add_session_to_tabs/2**:
```elixir
def add_session_to_tabs(%__MODULE__{} = model, session) do
  # ... existing logic

  # Rebuild tabs widget
  tabs_props = ViewHelpers.render_tabs_props(new_sessions, new_order, new_active_id)
  {:ok, new_tabs_widget} =
    if model.tabs_widget do
      TermUI.Widgets.Tabs.update(tabs_props, model.tabs_widget)
    else
      TermUI.Widgets.Tabs.init(tabs_props)
    end

  %{model | tabs_widget: new_tabs_widget}
end
```

## Success Criteria

All success criteria from phase-04.md Task 4.3.1:

1. ✅ `render_tabs/1` creates tabs from model.sessions and model.session_order
2. ✅ `format_tab_label/2` formats labels as "index:name"
3. ✅ Tab 10 shows as "0:" (index mapping for Ctrl+0 shortcut)
4. ✅ Active tab is properly indicated (via selected parameter)
5. ✅ All tabs marked as closeable: true
6. ✅ Tab names truncated at 15 characters with ellipsis
7. ✅ Empty sessions case handled (no tabs rendered)
8. ✅ Tabs widget state stored in model
9. ✅ Unit tests cover all tab rendering logic
10. ✅ All tests pass

## Implementation Plan

### Phase 1: Research and Planning ✅
- [x] Read TermUI.Widgets.Tabs API
- [x] Understand tab data structure requirements
- [x] Review existing widget integration patterns
- [x] Create comprehensive feature plan

### Phase 2: Core Tab Rendering Functions
- [ ] 2.1 Add tabs_widget field to Model struct
- [ ] 2.2 Implement truncate/2 helper (TDD: write tests first)
- [ ] 2.3 Implement format_tab_label/2 (TDD: write tests first)
- [ ] 2.4 Implement render_tabs_props/3 helper
- [ ] 2.5 Implement render_tabs/1 function

### Phase 3: Widget State Management
- [ ] 3.1 Initialize tabs widget in init/1
- [ ] 3.2 Update add_session_to_tabs/2 to rebuild tabs
- [ ] 3.3 Update remove_session_from_tabs/2 to rebuild tabs
- [ ] 3.4 Handle session rename (if function exists)

### Phase 4: View Integration
- [ ] 4.1 Update render_main_view/1 to include tabs
- [ ] 4.2 Add separator after tabs
- [ ] 4.3 Handle empty sessions case (no tabs)
- [ ] 4.4 Test visual layout with tabs

### Phase 5: Testing
- [ ] 5.1 Write unit tests for truncate/2
- [ ] 5.2 Write unit tests for format_tab_label/2 (indices 1-10)
- [ ] 5.3 Write unit tests for render_tabs_props/3
- [ ] 5.4 Write unit tests for render_tabs/1 (empty, single, multiple)
- [ ] 5.5 Write integration tests for tab rendering in view
- [ ] 5.6 Verify all tests pass

### Phase 6: Documentation and Completion
- [ ] 6.1 Update phase-04.md to mark Task 4.3.1 complete
- [ ] 6.2 Write summary document in notes/summaries
- [ ] 6.3 Request commit approval

## Notes/Considerations

### Design Decisions

**Decision 1**: Tabs widget stored in model vs recreated on each render
- **Choice**: Store in model (follow ConversationView pattern)
- **Rationale**: Stateful widget needs persistent state for event handling

**Decision 2**: Tab content field
- **Choice**: Don't use content field (only show tab bar)
- **Rationale**: Content panels not needed - sessions render in main area

**Decision 3**: Where to place rendering functions
- **Choice**: ViewHelpers.ex for rendering, TUI.ex for state management
- **Rationale**: Clean separation of concerns, follows existing pattern

**Decision 4**: Tab 10 index display
- **Choice**: Show as "0:" instead of "10:"
- **Rationale**: Matches Ctrl+0 keyboard shortcut (Task 4.5.1)

**Decision 5**: Event routing for tabs
- **Choice**: Defer to Phase 4.5 (keyboard shortcuts)
- **Rationale**: Task 4.3.1 focuses on visual rendering only

### Edge Cases

1. **Empty sessions** - Don't render tabs widget (return nil)
2. **Single session** - Render single tab (no special handling)
3. **10 sessions** - 10th tab shows "0:" label
4. **Long session names** - Truncate at 15 chars with "..."
5. **nil active_session_id** - Tabs widget handles (no selection)

### Testing Strategy

**Unit Tests** (test/jido_code/tui_test.exs):
- `truncate/2`: short text, long text, exact length, unicode
- `format_tab_label/2`: indices 1-9, index 10, truncation
- `render_tabs/1`: empty sessions, single, multiple, nil tabs_widget

**Integration Tests** (future Phase 4.7):
- Tabs render correctly in full view
- Active tab matches active_session_id
- Tab order matches session_order
- 10th tab accessible via Ctrl+0

### Future Work (Not in 4.3.1)

- **Task 4.3.2**: Tab indicator for 10th session
- **Task 4.3.3**: Tab status indicators (spinner, error)
- **Phase 4.4**: Welcome screen when no sessions
- **Phase 4.5**: Keyboard shortcuts (Ctrl+1-9, Ctrl+0, Ctrl+Tab, Ctrl+W)
- **Phase 4.6**: Event routing (mouse clicks on tabs)

### Potential Challenges

**Challenge 1**: TermUI Tabs API differs from expected
- **Mitigation**: Research completed, API documented above
- **Fallback**: Adjust implementation to match actual API

**Challenge 2**: Tabs widget requires content field
- **Mitigation**: Research shows content is optional
- **Fallback**: Pass empty content if required

**Challenge 3**: Widget state updates are complex
- **Mitigation**: Follow ConversationView pattern closely
- **Fallback**: Recreate widget on each change (less efficient)

**Challenge 4**: Height calculations affected by tabs
- **Mitigation**: Tabs use fixed height of 3 lines
- **Adjustment**: Reduce conversation area height by 4 (tabs + separator)

## Current Status

**Branch**: feature/tab-bar-component
**Phase**: 1 (Research and Planning) - COMPLETE
**Next Step**: Begin Phase 2.1 - Add tabs_widget to Model struct

## Files to Change

```
M  lib/jido_code/tui.ex                    # Add tabs_widget to Model, init
M  lib/jido_code/tui/view_helpers.ex        # Add rendering functions
M  test/jido_code/tui_test.exs              # Add unit tests
M  notes/planning/work-session/phase-04.md  # Mark task complete
A  notes/summaries/tab-bar-component.md     # Summary document
```

## Dependencies

**Completed**:
- Phase 4.1: Model structure (sessions, session_order, active_session_id)
- Phase 4.2.1: Init updates for multi-session
- Phase 4.2.2: PubSub subscription management
- Phase 4.2.3: Message routing with session_id

**Concurrent**:
- Task 4.3.1: This task (visual rendering only)

**Future**:
- Task 4.3.2: 10th tab indicator
- Task 4.3.3: Status indicators
- Phase 4.4: View integration and welcome screen
- Phase 4.5: Keyboard navigation
