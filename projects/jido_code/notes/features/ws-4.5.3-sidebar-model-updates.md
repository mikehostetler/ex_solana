# Planning Document: Task 4.5.3 - Sidebar Model Updates

## Overview

**Task**: Add sidebar state to TUI Model for visibility, width, and expanded sections (Phase 4.5.3)

**Status**: ✅ Complete

**Context**: This task is part of Phase 4.5 (Left Sidebar Integration). Tasks 4.5.1 (Accordion Component) and 4.5.2 (Session Sidebar Component) are complete. The SessionSidebar widget has been implemented and tested, and now requires Model state integration to support user interaction and persistence.

**Dependencies**:
- Phase 4.5.1: Accordion Component (COMPLETE)
- Phase 4.5.2: Session Sidebar Component (COMPLETE)

**Blocks**:
- Phase 4.5.4: Layout Integration
- Phase 4.5.5: Keyboard Shortcuts
- Phase 4.5.6: Visual Polish

---

## Current State Analysis

### 1. Existing Model Structure

Location: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 103-227)

The current `Model` struct in `JidoCode.TUI.Model` contains:

**Session Management Fields** (Phase 4.1):
- `sessions: %{}` - Map of session_id to Session.t()
- `session_order: []` - List of session_ids in tab order
- `active_session_id: nil` - Currently focused session

**UI State Fields**:
- `text_input: nil` - TextInput widget state
- `tabs_widget: nil` - Tabs widget state (not currently used)
- `focus: :input` - Focus state (:input | :conversation | :tabs)
- `window: {80, 24}` - Terminal dimensions
- `show_reasoning: false` - Whether reasoning panel is visible
- `show_tool_details: false` - Whether tool details are expanded
- `agent_status: :unconfigured` - Agent status
- `config: %{provider: nil, model: nil}` - LLM config

**Modal Fields** (shared across sessions):
- `shell_dialog: nil` - Shell output modal
- `shell_viewport: nil` - Viewport for shell dialog
- `pick_list: nil` - Interactive picker widget

**Legacy Per-Session Fields** (for backwards compatibility):
- `messages: []`
- `reasoning_steps: []`
- `tool_calls: []`
- `message_queue: []`
- `scroll_offset: 0`
- `agent_name: :llm_agent`
- `streaming_message: nil`
- `is_streaming: false`
- `session_topic: nil`
- `conversation_view: nil` - ConversationView widget state

**Missing**: No sidebar-related state fields exist.

### 2. SessionSidebar Widget Requirements

Location: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/session_sidebar.ex`

The `SessionSidebar.new/1` constructor expects:
```elixir
SessionSidebar.new(
  sessions: [Session.t()],      # List of session structs
  order: [String.t()],           # Session IDs in display order
  active_id: String.t() | nil,   # Active session ID
  expanded: MapSet.t(),          # Set of expanded session IDs
  width: pos_integer()           # Sidebar width (default: 20)
)
```

The widget uses:
- `sessions`, `order`, `active_id` - Already available in Model
- `expanded` - **MISSING** - needs to be added to Model
- `width` - **MISSING** - needs to be added to Model

### 3. Integration Points

The sidebar will be integrated into the view via a future `render_with_sidebar/1` function (Task 4.5.4), which will need:
- `sidebar_visible` field to toggle display (Ctrl+S shortcut)
- `sidebar_width` field for responsive layout calculation
- `sidebar_expanded` field to track which sessions are expanded
- `sidebar_focused` field for keyboard navigation (future enhancement)

---

## Implementation Plan

### 4.5.3.1: Add sidebar_visible field to Model struct

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: Model defstruct (currently lines 195-226)

**Changes**:

Add new field group after "UI state" section and before "Modals":
```elixir
# Sidebar state (Phase 4.5)
sidebar_visible: true,     # Ctrl+S to toggle
sidebar_width: 20,         # Character width (20-25)
sidebar_expanded: MapSet.new(),  # Set of expanded session IDs
sidebar_focused: false,    # For keyboard navigation
```

**Rationale**:
- Default `sidebar_visible: true` - sidebar shown by default on wide terminals
- Default `sidebar_width: 20` - matches SessionSidebar default and fits session name + badge
- Default `sidebar_expanded: MapSet.new()` - all sessions collapsed initially (clean view)
- Default `sidebar_focused: false` - input has focus by default

**Testing Strategy**:
- Unit test: Model struct has `sidebar_visible` field
- Unit test: Default value is `true`
- Unit test: Can be set to `false`

---

### 4.5.3.2: Add sidebar_width field to Model struct

**File**: Same as above

**Location**: Same defstruct, added in same section

**Implementation**: See 4.5.3.1 above

**Rationale**:
- Width of 20 chars supports: "1:MySession (12) ✓" (15 char name + prefix + badge)
- Minimum practical width per SessionSidebar tests: 20 chars
- Maximum reasonable width: 25-30 chars
- Should be configurable for future user preferences

**Edge Cases**:
- Very narrow terminals (<90 chars total) - sidebar auto-hides (Task 4.5.4)
- User could theoretically set width >50 - validate or cap in layout code
- Width must be >=20 for proper badge rendering

**Testing Strategy**:
- Unit test: Model has `sidebar_width` field
- Unit test: Default value is `20`
- Unit test: Can be set to custom values (25, 30)
- Integration test: Sidebar renders at configured width

---

### 4.5.3.3: Add sidebar_expanded field to Model struct

**File**: Same as above

**Location**: Same defstruct, added in same section

**Implementation**: See 4.5.3.1 above

**Rationale**:
- Uses `MapSet` for O(1) membership checks (same as Accordion widget)
- Stores session IDs of expanded sessions
- Empty by default (all sessions collapsed initially)
- Persists across renders until user toggles

**Usage Pattern**:
```elixir
# Check if session is expanded
MapSet.member?(model.sidebar_expanded, session_id)

# Toggle expansion
expanded = if MapSet.member?(model.sidebar_expanded, session_id) do
  MapSet.delete(model.sidebar_expanded, session_id)
else
  MapSet.put(model.sidebar_expanded, session_id)
end
%{model | sidebar_expanded: expanded}
```

**Edge Cases**:
- Session removed while expanded - stale ID left in set (harmless, cleaned on next toggle)
- All sessions expanded - could be large set, but <10 sessions max (Ctrl+1-0 limit)
- Session ID collision - unlikely with UUID-based IDs

**Testing Strategy**:
- Unit test: Model has `sidebar_expanded` field
- Unit test: Default value is empty MapSet
- Unit test: Can add/remove session IDs
- Unit test: MapSet operations work correctly

---

### 4.5.3.4: Add sidebar_focused field to Model struct

**File**: Same as above

**Location**: Same defstruct, added in same section

**Implementation**: See 4.5.3.1 above

**Rationale**:
- Boolean flag for keyboard navigation focus
- Initially `false` (input has focus by default)
- Will be used in Phase 4.5.5 for Tab/arrow key navigation
- Integrates with existing `focus` field (:input | :conversation | :tabs)

**Future Enhancement** (Phase 4.5.5):
- Extend `@type focus` to include `:sidebar`
- Use `sidebar_focused` as internal navigation state
- Or merge into `focus` field as `:sidebar` variant

**Design Decision**:
Keep as separate boolean for now rather than extending `focus` type:
- Simpler initial implementation
- Can be refactored to `focus: :sidebar` in Phase 4.5.5 if needed
- Maintains backward compatibility with existing focus handling

**Testing Strategy**:
- Unit test: Model has `sidebar_focused` field
- Unit test: Default value is `false`
- Unit test: Can be toggled true/false

---

### 4.5.3.5: Update Model typespec with new fields

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: Model `@type t` definition (currently line 157)

**Updated Typespec**:
```elixir
# Sidebar state (Phase 4.5)
sidebar_visible: boolean(),
sidebar_width: pos_integer(),
sidebar_expanded: MapSet.t(String.t()),
sidebar_focused: boolean(),
```

**Changes**:
1. Add comment line: `# Sidebar state (Phase 4.5)`
2. Add `sidebar_visible: boolean()`
3. Add `sidebar_width: pos_integer()` (must be >= 1)
4. Add `sidebar_expanded: MapSet.t(String.t())` (set of session IDs)
5. Add `sidebar_focused: boolean()`

**Type Safety**:
- All types are standard Elixir types (no custom types needed)
- `pos_integer()` ensures width is always >= 1
- `MapSet.t(String.t())` clearly documents set contents
- Maintains consistency with existing typespec style

**Testing Strategy**:
- Dialyzer will check typespec correctness
- Unit tests verify fields exist and have correct types
- No runtime typespec tests needed (compile-time checking)

---

### 4.5.3.6: Update init/1 to initialize sidebar state

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Location**: `init/1` function (currently lines 587-661)

**Updated init/1**:
```elixir
# Sidebar state (Phase 4.5)
sidebar_visible: true,
sidebar_width: 20,
sidebar_expanded: MapSet.new(),
sidebar_focused: false
```

**Rationale**:
- Initialize with default values matching defstruct
- All sessions collapsed initially (clean, minimal view)
- Sidebar visible by default (will auto-hide on narrow terminals in 4.5.4)
- Input has focus initially (sidebar_focused: false)

**Future Enhancement**:
- Load sidebar preferences from settings (Phase 7+)
- Remember last expanded sessions across restarts
- Save sidebar width preference

**Testing Strategy**:
- Unit test: init/1 sets sidebar_visible to true
- Unit test: init/1 sets sidebar_width to 20
- Unit test: init/1 sets sidebar_expanded to empty MapSet
- Unit test: init/1 sets sidebar_focused to false
- Integration test: Full TUI initialization includes sidebar state

---

### 4.5.3.7: Write unit tests for model updates

**File**: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`

**Location**: Add new describe block after existing "Model struct" tests (after line ~123)

**Test Suite Structure**:

```elixir
describe "Model sidebar state (Phase 4.5.3)" do
  # Field existence tests (4 tests)
  test "Model struct has sidebar_visible field"
  test "Model struct has sidebar_width field"
  test "Model struct has sidebar_expanded field"
  test "Model struct has sidebar_focused field"

  # Default value tests (4 tests)
  test "sidebar_visible defaults to true"
  test "sidebar_width defaults to 20"
  test "sidebar_expanded defaults to empty MapSet"
  test "sidebar_focused defaults to false"

  # Custom value tests (4 tests)
  test "can create Model with sidebar_visible false"
  test "can create Model with custom sidebar_width"
  test "can create Model with expanded sessions"
  test "can create Model with sidebar_focused true"

  # MapSet operations tests (3 tests)
  test "can add session to sidebar_expanded"
  test "can remove session from sidebar_expanded"
  test "can toggle session expansion"
end

describe "init/1 sidebar initialization (Phase 4.5.3)" do
  # Init tests (5 tests)
  test "init/1 sets sidebar_visible to true"
  test "init/1 sets sidebar_width to 20"
  test "init/1 sets sidebar_expanded to empty MapSet"
  test "init/1 sets sidebar_focused to false"
  test "init/1 initializes all sidebar fields together"
end
```

**Test Coverage**:
- 4 tests for field existence
- 4 tests for default values
- 4 tests for custom values
- 3 tests for MapSet operations
- 5 tests for init/1 behavior
- **Total: 20 tests**

**Test Strategy**:
1. **Field Existence**: Verify all fields added to struct
2. **Default Values**: Verify defaults match design spec
3. **Custom Values**: Verify fields can be set to custom values
4. **MapSet Operations**: Verify add/remove/toggle work correctly
5. **Init Integration**: Verify init/1 properly initializes sidebar state

---

## Integration Considerations

### 1. Backward Compatibility

**Risk**: Existing code expects Model without sidebar fields

**Mitigation**:
- All new fields have default values in defstruct
- Pattern matches on Model don't need to be updated (use `%Model{}` not `%Model{field1, field2, ...}`)
- No breaking changes to existing API

**Testing**: Run full test suite to ensure no regressions

### 2. SessionSidebar Widget Integration

**Current**: SessionSidebar is complete and tested independently

**Integration** (Phase 4.5.4):
```elixir
# In view/1 or render_with_sidebar/1
sidebar_widget = SessionSidebar.new(
  sessions: Map.values(state.sessions),
  order: state.session_order,
  active_id: state.active_session_id,
  expanded: state.sidebar_expanded,  # NEW - from Model
  width: state.sidebar_width          # NEW - from Model
)

sidebar_view = SessionSidebar.render(sidebar_widget, state.sidebar_width)
```

**Testing**: Integration test in Phase 4.5.4

### 3. Focus Management

**Current Focus Field**: `:input | :conversation | :tabs`

**Sidebar Focus** (Phase 4.5.5):
- Option A: Extend to `:input | :conversation | :tabs | :sidebar`
- Option B: Keep separate `sidebar_focused` boolean

**Recommendation**: Keep separate for Phase 4.5, consider merging in Phase 4.6+

**Rationale**:
- Simpler initial implementation
- Sidebar navigation is optional enhancement
- Can refactor later without breaking changes

### 4. Responsive Behavior

**Terminal Width Handling** (Phase 4.5.4):
```elixir
{width, _height} = state.window
show_sidebar = state.sidebar_visible and width >= 90

if show_sidebar do
  # Render with sidebar
else
  # Hide sidebar on narrow terminals
end
```

**State Management**:
- `sidebar_visible` = user preference (Ctrl+S toggle)
- Actual visibility = `sidebar_visible AND width >= 90`
- Don't modify `sidebar_visible` based on width (preserve user preference)

---

## Success Criteria

### Functional Requirements

- [ ] Model struct includes `sidebar_visible` field (boolean, default: true)
- [ ] Model struct includes `sidebar_width` field (pos_integer, default: 20)
- [ ] Model struct includes `sidebar_expanded` field (MapSet, default: empty)
- [ ] Model struct includes `sidebar_focused` field (boolean, default: false)
- [ ] Model `@type t` typespec includes all four new fields with correct types
- [ ] `init/1` initializes all sidebar fields with default values
- [ ] All unit tests pass (20 new tests, 0 failures)

### Quality Requirements

- [ ] Code passes Dialyzer type checking
- [ ] Code passes Credo --strict
- [ ] Test coverage remains >= 80%
- [ ] Documentation updated (moduledoc for Model includes sidebar fields)
- [ ] No breaking changes to existing TUI functionality
- [ ] All existing tests continue to pass

### Integration Requirements

- [ ] SessionSidebar widget can be instantiated with Model fields
- [ ] Sidebar state persists across re-renders
- [ ] MapSet operations work correctly for expansion state
- [ ] No memory leaks from stale session IDs in expanded set

---

## Testing Plan

### Unit Tests (20 tests)

**Test File**: `test/jido_code/tui_test.exs`

**Coverage**:
1. Model struct field existence (4 tests)
2. Default values (4 tests)
3. Custom values (4 tests)
4. MapSet operations (3 tests)
5. init/1 initialization (5 tests)

**Execution**:
```bash
mix test test/jido_code/tui_test.exs
```

### Type Checking

```bash
mix dialyzer
```

Expected: No new warnings

### Code Quality

```bash
mix credo --strict
```

Expected: No new issues

---

## Risk Assessment

### Low Risk

- **Field Addition**: Simple struct fields with defaults (no breaking changes)
- **Type Safety**: Using standard Elixir types (boolean, pos_integer, MapSet)
- **Testing**: Straightforward unit tests with no external dependencies

### Medium Risk

- **MapSet Performance**: Should be fine with <10 sessions, but worth monitoring
  - Mitigation: Profile if session count increases in future
- **Stale Session IDs**: Expanded set may contain IDs of deleted sessions
  - Mitigation: Harmless (will be skipped during rendering), cleaned on next toggle

### No Risk

- **Memory**: Negligible overhead (4 fields, 1 small MapSet)
- **Backward Compatibility**: All new fields have defaults
- **Integration**: SessionSidebar already expects these exact fields

---

## Implementation Sequence

### Step 1: Update Model Struct (5 minutes)
- Edit defstruct in tui.ex
- Add 4 new fields with defaults
- Group under "# Sidebar state (Phase 4.5)" comment

### Step 2: Update Typespec (5 minutes)
- Edit @type t in tui.ex
- Add 4 new field types
- Verify Dialyzer compliance

### Step 3: Update init/1 (5 minutes)
- Add 4 field initializations to Model creation
- Use default values

### Step 4: Write Unit Tests (30 minutes)
- Add "Model sidebar state" describe block (16 tests)
- Add "init/1 sidebar initialization" describe block (5 tests)
- Run tests: `mix test test/jido_code/tui_test.exs`

### Step 5: Verify Quality (10 minutes)
- Run Dialyzer: `mix dialyzer`
- Run Credo: `mix credo --strict`
- Check test coverage: `mix test --cover`

### Step 6: Documentation (10 minutes)
- Update Model moduledoc to mention sidebar state
- Add comments to new fields in defstruct
- Update phase-04.md to mark subtasks complete

**Total Estimated Time**: 65 minutes

---

## Next Steps (Phase 4.5.4)

After completing Task 4.5.3, proceed to Task 4.5.4 (Layout Integration):

1. Create `render_with_sidebar/1` function
2. Update `render_main_view/1` to conditionally use sidebar
3. Implement horizontal split (sidebar | separator | main)
4. Add responsive behavior (hide sidebar when width < 90)
5. Ensure sidebar works with reasoning panel layouts
6. Write integration tests

**Dependencies**: Requires sidebar_visible, sidebar_width, sidebar_expanded from this task.

---

## References

- Phase 4.5 Plan: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`
- SessionSidebar Docs: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/session_sidebar.ex`
- Accordion Docs: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`
- Existing Model Tests: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`
- SessionSidebar Planning: `/home/ducky/code/jido_code/notes/features/session-sidebar.md`
