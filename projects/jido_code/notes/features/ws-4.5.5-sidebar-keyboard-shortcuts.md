# Planning Document: Task 4.5.5 - Sidebar Keyboard Shortcuts

## Overview

**Task**: Add keyboard shortcuts for sidebar visibility, navigation, and interaction (Phase 4.5.5)

**Status**: ✅ Complete

**Context**: Tasks 4.5.1-4.5.4 are complete. The sidebar is integrated into the TUI layout and renders correctly. This task adds keyboard shortcuts to make the sidebar interactive: toggle visibility (Ctrl+S), navigate sessions (Up/Down), toggle expansion (Enter), and integrate sidebar into the focus cycle.

**Dependencies**:
- Phase 4.5.1: Accordion Component ✅ COMPLETE
- Phase 4.5.2: Session Sidebar Component ✅ COMPLETE
- Phase 4.5.3: Model Updates ✅ COMPLETE
- Phase 4.5.4: Layout Integration ✅ COMPLETE

**Blocks**:
- Phase 4.5.6: Visual Polish

---

## Current State Analysis

### Existing Keyboard Handling

**Location**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 682-900+)

**Current Shortcuts**:
- Ctrl+C → :quit
- Ctrl+R → :toggle_reasoning
- Ctrl+T → :toggle_tool_details
- Ctrl+1-9/0 → switch sessions
- Ctrl+Tab → cycle sessions forward
- Ctrl+Shift+Tab → cycle sessions backward
- Ctrl+W → close session
- Ctrl+N → new session
- Up/Down → scroll conversation
- Enter → submit input

### Focus System

**Current Focus States** (`@type focus`):
- `:input` - Text input has focus
- `:conversation` - Conversation area has focus (for scrolling)
- `:tabs` - Tabs have focus (not actively used)

**Missing**: `:sidebar` focus state needed for sidebar navigation

### Model State

**Sidebar Fields** (from Task 4.5.3):
- `sidebar_visible: boolean()` - Toggle with Ctrl+S
- `sidebar_width: pos_integer()` - Not modified by shortcuts
- `sidebar_expanded: MapSet.t(String.t())` - Toggle with Enter
- `sidebar_focused: boolean()` - Deprecated in favor of `focus: :sidebar`

---

## Solution Overview

### Keyboard Shortcuts to Add

1. **Ctrl+S**: Toggle sidebar visibility
   - Flips `sidebar_visible` field
   - Works regardless of focus state

2. **Up/Down Arrows** (when sidebar focused):
   - Navigate between sessions in sidebar
   - Track current selection with new field
   - Wrap around at boundaries

3. **Enter** (when sidebar focused):
   - Toggle expansion of selected session
   - Adds/removes session ID from `sidebar_expanded` MapSet

4. **Tab/Shift+Tab** (extended):
   - Add sidebar to focus cycle
   - Cycle: input → conversation → sidebar → input

### Model Changes Needed

**Add Field**:
- `sidebar_selected_index: non_neg_integer()` - Currently selected session index (0-based)
  - Default: 0
  - Used for Up/Down navigation
  - Bounds: 0 to `length(session_order) - 1`

**Modify Field**:
- `focus: :input | :conversation | :tabs | :sidebar` - Extend type to include `:sidebar`
- Remove `sidebar_focused` field (redundant with `focus: :sidebar`)

---

## Implementation Plan

### 4.5.5.1: Add Ctrl+S shortcut to toggle sidebar visibility

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `event_to_msg/2` function (around line 682+)

**Implementation**:
```elixir
# Ctrl+S to toggle sidebar
def event_to_msg(%Event.Key{key: "s", modifiers: modifiers} = _event, _state) do
  if :ctrl in modifiers do
    {:msg, :toggle_sidebar}
  else
    # Pass to text input
    :ignore
  end
end
```

### 4.5.5.2: Implement update(:toggle_sidebar, model) handler

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `update/2` function (around line 1000+)

**Implementation**:
```elixir
def update(:toggle_sidebar, model) do
  %{model | sidebar_visible: not model.sidebar_visible}
end
```

### 4.5.5.3: Add Up/Down arrow keys for sidebar navigation

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `event_to_msg/2` function

**Implementation**:
```elixir
# Up/Down arrows when sidebar focused
def event_to_msg(%Event.Key{key: :up}, %Model{focus: :sidebar} = _state) do
  {:msg, {:sidebar_nav, :up}}
end

def event_to_msg(%Event.Key{key: :down}, %Model{focus: :sidebar} = _state) do
  {:msg, {:sidebar_nav, :down}}
end
```

### 4.5.5.4: Implement update({:sidebar_nav, direction}, model) handler

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `update/2` function

**Implementation**:
```elixir
def update({:sidebar_nav, :up}, model) do
  max_index = length(model.session_order) - 1

  new_index =
    if model.sidebar_selected_index == 0 do
      max_index  # Wrap to bottom
    else
      model.sidebar_selected_index - 1
    end

  %{model | sidebar_selected_index: new_index}
end

def update({:sidebar_nav, :down}, model) do
  max_index = length(model.session_order) - 1

  new_index =
    if model.sidebar_selected_index >= max_index do
      0  # Wrap to top
    else
      model.sidebar_selected_index + 1
    end

  %{model | sidebar_selected_index: new_index}
end
```

### 4.5.5.5: Add Enter key to toggle accordion section

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `event_to_msg/2` function

**Implementation**:
```elixir
# Enter key when sidebar focused
def event_to_msg(%Event.Key{key: :enter}, %Model{focus: :sidebar} = state) do
  # Get currently selected session ID
  if state.sidebar_selected_index < length(state.session_order) do
    session_id = Enum.at(state.session_order, state.sidebar_selected_index)
    {:msg, {:toggle_accordion, session_id}}
  else
    :ignore
  end
end
```

### 4.5.5.6: Implement update({:toggle_accordion, session_id}, model) handler

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `update/2` function

**Implementation**:
```elixir
def update({:toggle_accordion, session_id}, model) do
  expanded =
    if MapSet.member?(model.sidebar_expanded, session_id) do
      MapSet.delete(model.sidebar_expanded, session_id)
    else
      MapSet.put(model.sidebar_expanded, session_id)
    end

  %{model | sidebar_expanded: expanded}
end
```

### 4.5.5.7: Add sidebar to focus cycle

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `event_to_msg/2` and `update/2` functions

**Implementation**:

Update focus type:
```elixir
@type focus :: :input | :conversation | :tabs | :sidebar
```

Handle Tab key:
```elixir
# Tab to cycle focus forward
def event_to_msg(%Event.Key{key: :tab, modifiers: modifiers}, state) do
  if :shift in modifiers do
    {:msg, {:cycle_focus, :backward}}
  else
    {:msg, {:cycle_focus, :forward}}
  end
end
```

Update focus cycle logic:
```elixir
def update({:cycle_focus, :forward}, model) do
  new_focus =
    case model.focus do
      :input -> :conversation
      :conversation -> if model.sidebar_visible, do: :sidebar, else: :input
      :sidebar -> :input
      _ -> :input
    end

  # Update text input focus state
  text_input =
    if new_focus == :input do
      TextInput.set_focused(model.text_input, true)
    else
      TextInput.set_focused(model.text_input, false)
    end

  %{model | focus: new_focus, text_input: text_input}
end

def update({:cycle_focus, :backward}, model) do
  new_focus =
    case model.focus do
      :input -> if model.sidebar_visible, do: :sidebar, else: :conversation
      :conversation -> :input
      :sidebar -> :conversation
      _ -> :input
    end

  # Update text input focus state
  text_input =
    if new_focus == :input do
      TextInput.set_focused(model.text_input, true)
    else
      TextInput.set_focused(model.text_input, false)
    end

  %{model | focus: new_focus, text_input: text_input}
end
```

### 4.5.5.8: Update Model struct and init/1

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Changes**:

1. Add `sidebar_selected_index` to Model struct:
```elixir
defstruct [
  # ...
  # Sidebar state (Phase 4.5)
  sidebar_visible: true,
  sidebar_width: 20,
  sidebar_expanded: MapSet.new(),
  sidebar_selected_index: 0,  # NEW
  # ...
]
```

2. Update Model typespec:
```elixir
@type t :: %__MODULE__{
  # ...
  # Sidebar state (Phase 4.5)
  sidebar_visible: boolean(),
  sidebar_width: pos_integer(),
  sidebar_expanded: MapSet.t(String.t()),
  sidebar_selected_index: non_neg_integer(),  # NEW
  # ...
}
```

3. Update `init/1`:
```elixir
%Model{
  # ...
  sidebar_visible: true,
  sidebar_width: 20,
  sidebar_expanded: MapSet.new(),
  sidebar_selected_index: 0,  # NEW
  # ...
}
```

4. Remove `sidebar_focused` field (deprecated)

### 4.5.5.9: Write unit tests for keyboard shortcuts

**File**: `test/jido_code/tui_test.exs`

**Test Categories**:

1. **Ctrl+S Toggle Tests** (3 tests)
   - Toggle from true to false
   - Toggle from false to true
   - Multiple toggles

2. **Sidebar Navigation Tests** (4 tests)
   - Navigate down increments index
   - Navigate up decrements index
   - Wrap around at bottom (down)
   - Wrap around at top (up)

3. **Accordion Toggle Tests** (3 tests)
   - Enter expands collapsed session
   - Enter collapses expanded session
   - Multiple toggles

4. **Focus Cycle Tests** (4 tests)
   - Tab cycles forward (input → conversation → sidebar → input)
   - Shift+Tab cycles backward (input → sidebar → conversation → input)
   - Sidebar skipped when not visible
   - Focus state updates correctly

**Total**: ~14 tests

---

## Test Plan

### Unit Tests (14 tests)

**Ctrl+S Toggle**:
```elixir
test "Ctrl+S toggles sidebar_visible from true to false"
test "Ctrl+S toggles sidebar_visible from false to true"
test "multiple Ctrl+S toggles work correctly"
```

**Sidebar Navigation**:
```elixir
test "Down arrow increments sidebar_selected_index"
test "Up arrow decrements sidebar_selected_index"
test "Down arrow wraps to 0 at end"
test "Up arrow wraps to max at start"
```

**Accordion Toggle**:
```elixir
test "Enter adds session to sidebar_expanded when collapsed"
test "Enter removes session from sidebar_expanded when expanded"
test "Enter toggles work multiple times"
```

**Focus Cycle**:
```elixir
test "Tab cycles focus forward through all states"
test "Shift+Tab cycles focus backward through all states"
test "Tab skips sidebar when sidebar_visible is false"
test "focus changes update text_input focused state"
```

---

## Success Criteria

### Functional Requirements
- ✅ Ctrl+S toggles `sidebar_visible` field
- ✅ Up/Down arrows navigate sessions when sidebar focused
- ✅ Enter toggles session expansion when sidebar focused
- ✅ Tab cycles through focus states including sidebar
- ✅ Focus cycle skips sidebar when not visible
- ✅ Navigation wraps at boundaries

### Technical Requirements
- ✅ 14+ unit tests covering all shortcuts
- ✅ All tests passing
- ✅ No breaking changes to existing shortcuts
- ✅ Type specs updated

---

## Implementation Notes

### Simplifications from Original Plan

**Removed `sidebar_focused` Field**:
- Original plan had separate `sidebar_focused: boolean()` field
- Simplified to use `focus: :sidebar` instead
- Less state to manage, clearer semantics

**Tab Key Integration**:
- Original plan didn't specify Tab integration
- Added focus cycling for better UX
- Sidebar becomes part of natural Tab flow

### Edge Cases

1. **Empty Session List**: Navigation should handle gracefully (no-op)
2. **Single Session**: Up/Down should stay on same session
3. **Sidebar Hidden**: Navigation shortcuts should be ignored
4. **Focus on Sidebar, Then Hide**: Focus should reset to input

---

## Estimated Implementation Time

- Model updates: 30 minutes
- Event handlers: 1 hour
- Update handlers: 1 hour
- Focus cycle logic: 1 hour
- Unit tests: 1.5 hours
- Testing/debugging: 30 minutes

**Total**: ~5.5 hours

---

## Next Steps (Phase 4.5.6)

After completing Task 4.5.5, proceed to Task 4.5.6 (Visual Polish):
- Style sidebar header
- Add focus indicators
- Improve separator styling
- Add visual feedback for selected session

---

## References

- **Phase Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md` (lines 505-524)
- **Existing Shortcuts**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (event_to_msg/2 and update/2)
- **Model Definition**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 157-237)
