# Feature: Tab Navigation Shortcuts (Ctrl+Tab and Ctrl+Shift+Tab Cycling)

**Task ID**: 4.6.2
**Phase**: 4 (TUI Tab Integration)
**Status**: ✅ Complete
**Created**: 2025-12-16
**Completed**: 2025-12-16

## 1. Problem Statement

### Current State

JidoCode TUI supports multiple concurrent work sessions with direct tab switching via Ctrl+1-9 and Ctrl+0 (Task 4.6.1, completed). However, users cannot cycle through tabs sequentially using Ctrl+Tab (forward) and Ctrl+Shift+Tab (backward), which is a standard navigation pattern in modern applications.

**Currently implemented**:
- Tab/Shift+Tab: Cycle focus between UI areas (input/conversation/sidebar)
- Ctrl+1-9, Ctrl+0: Direct tab switching by index
- Ctrl+W: Close active session
- Ctrl+S: Toggle sidebar

**Missing functionality**:
- Ctrl+Tab: Cycle to next session
- Ctrl+Shift+Tab: Cycle to previous session

### User Impact

Without tab cycling shortcuts:
- Users must remember session indices to switch tabs
- Browsing through sessions requires multiple Ctrl+1-9 keypresses
- No efficient way to "browse" through all open sessions
- Inconsistent with browser tab navigation patterns

### Technical Gap

The event handling infrastructure distinguishes between:
- `Tab` key → cycles UI focus (event_to_msg line 819)
- `Ctrl+Tab` → **not handled** (falls through to default input_event)

The codebase has:
- `Model.switch_session/2` for changing active session
- `session_order` list for maintaining tab order
- `active_session_id` for tracking current session

Missing:
- Event handlers for Ctrl+Tab and Ctrl+Shift+Tab
- Update handlers `:next_tab` and `:prev_tab`
- Cycling logic (wrap-around at list boundaries)
- Edge case handling (single session, empty list)

## 2. Solution Overview

### High-Level Design

Implement Ctrl+Tab and Ctrl+Shift+Tab shortcuts to cycle through sessions in `session_order` with wrap-around behavior:

```
Ctrl+Tab (forward):
[Session 1] → [Session 2] → [Session 3] → [Session 1] (wraps)
     ↑                                           |
     └───────────────────────────────────────────┘

Ctrl+Shift+Tab (backward):
[Session 1] ← [Session 2] ← [Session 3] ← [Session 1] (wraps)
     |                                           ↑
     └───────────────────────────────────────────┘
```

### Architecture

The implementation follows the existing TUI Elm Architecture pattern:

```
Terminal Event
      ↓
event_to_msg/2: Convert Ctrl+Tab → :next_tab or :prev_tab
      ↓
update/2: Calculate next/prev session ID
      ↓
Model.switch_session/2: Update active_session_id
      ↓
refresh_conversation_view_for_session/2: Load messages
      ↓
Re-render TUI with new active session
```

### Key Components

1. **Event Handlers** (lib/jido_code/tui.ex, event_to_msg/2)
   - Detect Ctrl+Tab → `:next_tab`
   - Detect Ctrl+Shift+Tab → `:prev_tab`

2. **Update Handlers** (lib/jido_code/tui.ex, update/2)
   - `:next_tab` → cycle forward with wrap-around
   - `:prev_tab` → cycle backward with wrap-around

3. **Edge Case Handling**
   - Single session: no-op (stay on current)
   - Empty session list: no-op (should never happen)
   - Already at first/last: wrap around

## 3. Technical Details

### Event Detection Pattern

TermUI represents keyboard events as:
```elixir
%TermUI.Event.Key{
  key: :tab,
  modifiers: [:ctrl] | [:ctrl, :shift]
}
```

The existing Tab handler (line 819) shows the pattern:
```elixir
def event_to_msg(%Event.Key{key: :tab, modifiers: modifiers}, _state) do
  if :shift in modifiers do
    {:msg, {:cycle_focus, :backward}}  # Shift+Tab → focus cycling
  else
    {:msg, {:cycle_focus, :forward}}   # Tab → focus cycling
  end
end
```

We need to add **before** the existing Tab handler to intercept Ctrl+Tab:
```elixir
# Ctrl+Tab - cycle to next session (forward)
def event_to_msg(%Event.Key{key: :tab, modifiers: modifiers}, _state) do
  cond do
    :ctrl in modifiers and :shift in modifiers ->
      {:msg, :prev_tab}  # Ctrl+Shift+Tab → previous session

    :ctrl in modifiers ->
      {:msg, :next_tab}  # Ctrl+Tab → next session

    :shift in modifiers ->
      {:msg, {:cycle_focus, :backward}}  # Shift+Tab → focus cycling

    true ->
      {:msg, {:cycle_focus, :forward}}  # Tab → focus cycling
  end
end
```

**Why this works**:
- Pattern matching order matters: specific patterns (Ctrl+Tab) must come before generic (Tab)
- `cond` allows multiple modifier checks in priority order
- Falls through to existing focus cycling behavior

### Cycling Logic

The cycling algorithm uses modular arithmetic for wrap-around:

```elixir
# Forward cycling (Ctrl+Tab)
def update(:next_tab, state) do
  case state.session_order do
    [] ->
      # No sessions (edge case)
      {state, []}

    [_single] ->
      # Only one session, stay where we are
      {state, []}

    order ->
      # Find current index in session_order
      current_idx = Enum.find_index(order, &(&1 == state.active_session_id))

      # Calculate next index with wrap-around
      next_idx = rem(current_idx + 1, length(order))
      next_id = Enum.at(order, next_idx)

      # Switch to next session
      new_state =
        state
        |> Model.switch_session(next_id)
        |> refresh_conversation_view_for_session(next_id)
        |> clear_session_activity(next_id)
        |> add_session_message("Switched to: #{get_session_name(state, next_id)}")

      {new_state, []}
  end
end

# Backward cycling (Ctrl+Shift+Tab)
def update(:prev_tab, state) do
  case state.session_order do
    [] -> {state, []}
    [_single] -> {state, []}

    order ->
      current_idx = Enum.find_index(order, &(&1 == state.active_session_id))

      # Calculate previous index with wrap-around
      # Add length before modulo to handle negative wrap
      prev_idx = rem(current_idx - 1 + length(order), length(order))
      prev_id = Enum.at(order, prev_idx)

      new_state =
        state
        |> Model.switch_session(prev_id)
        |> refresh_conversation_view_for_session(prev_id)
        |> clear_session_activity(prev_id)
        |> add_session_message("Switched to: #{get_session_name(state, prev_id)}")

      {new_state, []}
  end
end
```

**Wrap-around examples**:
```
Forward (3 sessions):
index 0 → 1 → 2 → 0 (wraps)
rem(0+1, 3) = 1
rem(1+1, 3) = 2
rem(2+1, 3) = 0  ✓

Backward (3 sessions):
index 0 → 2 → 1 → 0 (wraps)
rem(0-1+3, 3) = rem(2, 3) = 2  ✓
rem(2-1+3, 3) = rem(4, 3) = 1
rem(1-1+3, 3) = rem(3, 3) = 0
```

### Integration Points

The implementation reuses existing infrastructure:

1. **Model.switch_session/2** (line 480)
   - Updates `active_session_id`
   - Validates session exists in sessions map

2. **refresh_conversation_view_for_session/2** (existing helper)
   - Loads messages for the newly active session
   - Updates ConversationView widget

3. **clear_session_activity/2** (existing helper)
   - Clears notification badge for visited session

4. **add_session_message/2** (existing helper)
   - Shows feedback message to user

## 4. Implementation Plan

### Phase 1: Event Handlers (Subtask 4.6.2.1)

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Action**: Replace the existing Tab handler (line 819) with enhanced version:

```elixir
# Ctrl+Tab / Ctrl+Shift+Tab for session cycling, Tab / Shift+Tab for focus cycling
def event_to_msg(%Event.Key{key: :tab, modifiers: modifiers}, _state) do
  cond do
    # Ctrl+Shift+Tab → previous session
    :ctrl in modifiers and :shift in modifiers ->
      {:msg, :prev_tab}

    # Ctrl+Tab → next session
    :ctrl in modifiers ->
      {:msg, :next_tab}

    # Shift+Tab → focus backward
    :shift in modifiers ->
      {:msg, {:cycle_focus, :backward}}

    # Tab → focus forward
    true ->
      {:msg, {:cycle_focus, :forward}}
  end
end
```

**Location**: Insert at line 819 (replace existing Tab handler)

### Phase 2: Forward Cycling Handler (Subtask 4.6.2.2)

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Action**: Add `:next_tab` update handler after `:close_active_session` (after line 1160):

```elixir
# Cycle to next session (Ctrl+Tab)
def update(:next_tab, state) do
  case state.session_order do
    # No sessions (should not happen in practice)
    [] ->
      {state, []}

    # Single session - stay on current
    [_single] ->
      {state, []}

    # Multiple sessions - cycle forward
    order ->
      current_idx = Enum.find_index(order, &(&1 == state.active_session_id))
      next_idx = rem(current_idx + 1, length(order))
      next_id = Enum.at(order, next_idx)
      next_session = Map.get(state.sessions, next_id)

      new_state =
        state
        |> Model.switch_session(next_id)
        |> refresh_conversation_view_for_session(next_id)
        |> clear_session_activity(next_id)
        |> add_session_message("Switched to: #{next_session.name}")

      {new_state, []}
  end
end
```

**Location**: Insert after line 1185 (after `:switch_to_session_index` handler)

### Phase 3: Backward Cycling Handler (Subtask 4.6.2.3)

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

**Action**: Add `:prev_tab` update handler after `:next_tab`:

```elixir
# Cycle to previous session (Ctrl+Shift+Tab)
def update(:prev_tab, state) do
  case state.session_order do
    [] -> {state, []}
    [_single] -> {state, []}

    order ->
      current_idx = Enum.find_index(order, &(&1 == state.active_session_id))
      # Add length before modulo to handle negative wrap-around
      prev_idx = rem(current_idx - 1 + length(order), length(order))
      prev_id = Enum.at(order, prev_idx)
      prev_session = Map.get(state.sessions, prev_id)

      new_state =
        state
        |> Model.switch_session(prev_id)
        |> refresh_conversation_view_for_session(prev_id)
        |> clear_session_activity(prev_id)
        |> add_session_message("Switched to: #{prev_session.name}")

      {new_state, []}
  end
end
```

### Phase 4: Edge Cases (Subtask 4.6.2.4)

**Handled in Phase 2-3**: The `case` statements already handle:

1. **Empty session list** (`[]`): No-op, return state unchanged
2. **Single session** (`[_single]`): No-op, stay on current session
3. **Wrap-around**: Modular arithmetic ensures cycling wraps correctly

**Additional consideration**: What if `active_session_id` is not in `session_order`?
- This indicates a bug in session management
- `Enum.find_index/2` returns `nil`
- Need to add guard:

```elixir
order ->
  case Enum.find_index(order, &(&1 == state.active_session_id)) do
    nil ->
      # Active session not in order list (should not happen)
      {state, []}

    current_idx ->
      # Normal cycling logic...
  end
```

### Phase 5: Unit Tests (Subtask 4.6.2.5)

**File**: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`

**Location**: Add after existing tab switching tests (after line 3000)

#### Test Suite Structure

```elixir
describe "tab cycling shortcuts (Ctrl+Tab and Ctrl+Shift+Tab)" do
  setup do
    # Create 3-session test model
    session1 = %{id: "s1", name: "Project 1", project_path: "/path1"}
    session2 = %{id: "s2", name: "Project 2", project_path: "/path2"}
    session3 = %{id: "s3", name: "Project 3", project_path: "/path3"}

    model = %Model{
      text_input: create_text_input(),
      sessions: %{"s1" => session1, "s2" => session2, "s3" => session3},
      session_order: ["s1", "s2", "s3"],
      active_session_id: "s1",
      messages: [],
      config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"},
      conversation_view: create_conversation_view()
    }

    {:ok, model: model}
  end

  # Test 1: Event mapping
  test "Ctrl+Tab event maps to :next_tab message" do
    event = Event.key(:tab, modifiers: [:ctrl])
    {:msg, msg} = TUI.event_to_msg(event, %Model{})
    assert msg == :next_tab
  end

  test "Ctrl+Shift+Tab event maps to :prev_tab message" do
    event = Event.key(:tab, modifiers: [:ctrl, :shift])
    {:msg, msg} = TUI.event_to_msg(event, %Model{})
    assert msg == :prev_tab
  end

  # Test 2: Forward cycling
  test "Ctrl+Tab cycles forward from first to second session", %{model: model} do
    {new_model, _cmds} = TUI.update(:next_tab, model)
    assert new_model.active_session_id == "s2"
  end

  test "Ctrl+Tab cycles forward from second to third session", %{model: model} do
    model = %{model | active_session_id: "s2"}
    {new_model, _cmds} = TUI.update(:next_tab, model)
    assert new_model.active_session_id == "s3"
  end

  test "Ctrl+Tab wraps from last to first session", %{model: model} do
    model = %{model | active_session_id: "s3"}
    {new_model, _cmds} = TUI.update(:next_tab, model)
    assert new_model.active_session_id == "s1"
  end

  # Test 3: Backward cycling
  test "Ctrl+Shift+Tab cycles backward from first to last session", %{model: model} do
    {new_model, _cmds} = TUI.update(:prev_tab, model)
    assert new_model.active_session_id == "s3"
  end

  test "Ctrl+Shift+Tab cycles backward from third to second session", %{model: model} do
    model = %{model | active_session_id: "s3"}
    {new_model, _cmds} = TUI.update(:prev_tab, model)
    assert new_model.active_session_id == "s2"
  end

  test "Ctrl+Shift+Tab cycles backward from second to first session", %{model: model} do
    model = %{model | active_session_id: "s2"}
    {new_model, _cmds} = TUI.update(:prev_tab, model)
    assert new_model.active_session_id == "s1"
  end

  # Test 4: Edge cases
  test "Ctrl+Tab with single session stays on current session" do
    session = %{id: "s1", name: "Only Session", project_path: "/path"}
    model = %Model{
      text_input: create_text_input(),
      sessions: %{"s1" => session},
      session_order: ["s1"],
      active_session_id: "s1",
      messages: [],
      conversation_view: create_conversation_view()
    }

    {new_model, _cmds} = TUI.update(:next_tab, model)
    assert new_model.active_session_id == "s1"
  end

  test "Ctrl+Shift+Tab with single session stays on current session" do
    session = %{id: "s1", name: "Only Session", project_path: "/path"}
    model = %Model{
      text_input: create_text_input(),
      sessions: %{"s1" => session},
      session_order: ["s1"],
      active_session_id: "s1",
      messages: [],
      conversation_view: create_conversation_view()
    }

    {new_model, _cmds} = TUI.update(:prev_tab, model)
    assert new_model.active_session_id == "s1"
  end

  test "Ctrl+Tab with empty session list returns unchanged state" do
    model = %Model{
      text_input: create_text_input(),
      sessions: %{},
      session_order: [],
      active_session_id: nil,
      messages: [],
      conversation_view: create_conversation_view()
    }

    {new_model, _cmds} = TUI.update(:next_tab, model)
    assert new_model.active_session_id == nil
  end

  # Test 5: Integration test
  test "complete flow: Ctrl+Tab event -> state update -> session switch", %{model: model} do
    # Simulate Ctrl+Tab key press
    event = Event.key(:tab, modifiers: [:ctrl])
    {:msg, msg} = TUI.event_to_msg(event, model)

    # Verify event mapped correctly
    assert msg == :next_tab

    # Process the message
    {new_model, _cmds} = TUI.update(msg, model)

    # Verify session switched
    assert new_model.active_session_id == "s2"

    # Verify message added
    assert length(new_model.messages) > 0
    assert List.first(new_model.messages).content =~ "Switched to: Project 2"
  end

  # Test 6: Focus cycling still works
  test "Tab (without Ctrl) still cycles focus forward" do
    model = %Model{focus: :input}
    event = Event.key(:tab, modifiers: [])
    {:msg, msg} = TUI.event_to_msg(event, model)
    assert msg == {:cycle_focus, :forward}
  end

  test "Shift+Tab (without Ctrl) still cycles focus backward" do
    model = %Model{focus: :input}
    event = Event.key(:tab, modifiers: [:shift])
    {:msg, msg} = TUI.event_to_msg(event, model)
    assert msg == {:cycle_focus, :backward}
  end
end
```

**Test Coverage**:
- Event mapping: 2 tests (Ctrl+Tab, Ctrl+Shift+Tab)
- Forward cycling: 3 tests (first→second, second→third, wrap third→first)
- Backward cycling: 3 tests (first→last wrap, third→second, second→first)
- Edge cases: 3 tests (single session, empty list, no-op)
- Integration: 1 test (complete flow)
- Focus cycling regression: 2 tests (Tab, Shift+Tab still work)

**Total**: 14 tests

## 5. Success Criteria

### Functional Requirements

- [ ] Ctrl+Tab cycles to the next session in `session_order`
- [ ] Ctrl+Shift+Tab cycles to the previous session in `session_order`
- [ ] Cycling wraps around (last → first, first → last)
- [ ] Single session: Ctrl+Tab and Ctrl+Shift+Tab are no-ops
- [ ] Empty session list: gracefully handled (no crash)
- [ ] Switched session loads correctly (messages, status, name)
- [ ] User sees feedback message "Switched to: [session name]"
- [ ] Session activity indicator clears on visit

### Non-Functional Requirements

- [ ] No performance degradation (< 50ms cycle time)
- [ ] No memory leaks from cycling
- [ ] Tab/Shift+Tab focus cycling still works (no regression)
- [ ] Existing Ctrl+1-9 shortcuts still work (no regression)

### Test Coverage

- [ ] All 14 unit tests pass
- [ ] Test coverage ≥ 90% for new code
- [ ] No new compiler warnings
- [ ] No Dialyzer type errors

### User Experience

- [ ] Consistent with browser tab navigation (Ctrl+Tab forward, Ctrl+Shift+Tab back)
- [ ] Immediate visual feedback (active tab updates)
- [ ] Smooth cycling through 10 sessions without lag
- [ ] Documentation updated in keyboard shortcuts guide

## 6. Testing Strategy

### Unit Tests (14 tests)

**Test file**: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`

**Categories**:
1. Event mapping (2 tests)
2. Forward cycling logic (3 tests)
3. Backward cycling logic (3 tests)
4. Edge cases (3 tests)
5. Integration flow (1 test)
6. Regression checks (2 tests)

**Run command**:
```bash
mix test test/jido_code/tui_test.exs --only tab_cycling
```

### Manual Testing Checklist

**Setup**: Create 5 test sessions
```bash
/session new ~/test1 --name="Test 1"
/session new ~/test2 --name="Test 2"
/session new ~/test3 --name="Test 3"
/session new ~/test4 --name="Test 4"
/session new ~/test5 --name="Test 5"
```

**Test Cases**:

1. **Basic forward cycling**
   - Start on Test 1
   - Press Ctrl+Tab → should switch to Test 2
   - Press Ctrl+Tab → should switch to Test 3
   - Press Ctrl+Tab 3 more times → should wrap to Test 1

2. **Basic backward cycling**
   - Start on Test 1
   - Press Ctrl+Shift+Tab → should wrap to Test 5
   - Press Ctrl+Shift+Tab → should switch to Test 4
   - Press Ctrl+Shift+Tab 4 more times → should return to Test 5

3. **Mixed navigation**
   - Start on Test 1
   - Press Ctrl+Tab twice → Test 3
   - Press Ctrl+Shift+Tab once → Test 2
   - Press Ctrl+3 → Test 3 (verify direct switching still works)
   - Press Ctrl+Tab → Test 4

4. **Single session**
   - Close all but one session
   - Press Ctrl+Tab → should stay on same session
   - Press Ctrl+Shift+Tab → should stay on same session

5. **Focus cycling regression**
   - Press Tab (no Ctrl) → focus should cycle (input → conversation → sidebar → input)
   - Press Shift+Tab → focus should cycle backward

6. **Performance test**
   - Create 10 sessions (max)
   - Rapidly press Ctrl+Tab 50 times → should remain responsive
   - Verify no memory leak or UI lag

### Integration Test

**File**: `/home/ducky/code/jido_code/test/jido_code/integration_test.exs`

**Add to Phase 4 integration suite**:

```elixir
test "tab cycling workflow with multiple sessions" do
  # Setup: create 3 sessions
  {:ok, _model} = TUI.init([])

  # Create sessions
  TUI.update({:input_submitted, "/session new /tmp/test1 --name='Test 1'"}, model)
  TUI.update({:input_submitted, "/session new /tmp/test2 --name='Test 2'"}, model)
  TUI.update({:input_submitted, "/session new /tmp/test3 --name='Test 3'"}, model)

  # Verify we're on Test 3 (last created)
  assert model.active_session_id == "test3"

  # Cycle forward
  event = Event.key(:tab, modifiers: [:ctrl])
  {:msg, msg} = TUI.event_to_msg(event, model)
  {model, _} = TUI.update(msg, model)
  assert model.active_session_id == "test1"  # Wrapped to first

  # Cycle backward
  event = Event.key(:tab, modifiers: [:ctrl, :shift])
  {:msg, msg} = TUI.event_to_msg(event, model)
  {model, _} = TUI.update(msg, model)
  assert model.active_session_id == "test3"  # Wrapped to last
end
```

### Regression Testing

**Verify no breakage**:
- Run full test suite: `mix test`
- Run integration tests: `mix test test/jido_code/integration_test.exs`
- Verify existing keyboard shortcuts:
  - Ctrl+1-9, Ctrl+0 (direct switching)
  - Ctrl+W (close session)
  - Ctrl+S (toggle sidebar)
  - Ctrl+R (toggle reasoning)
  - Tab/Shift+Tab (focus cycling)

## 7. Documentation Updates

### User Documentation

**File**: `/home/ducky/code/jido_code/guides/user/keyboard-shortcuts.md`

**Update**: Already documents Ctrl+Tab, verify accuracy:
```markdown
| **Ctrl+Tab** | Next Session | Cycle to next session |
| **Ctrl+Shift+Tab** | Previous Session | Cycle to previous session |
```

**File**: `/home/ducky/code/jido_code/guides/user/sessions.md`

**Update**: Already mentions Ctrl+Tab in Quick Start, no changes needed.

### Developer Documentation

**File**: This document (`ws-4.6.2-tab-cycling-shortcuts.md`)

**File**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`

**Update**: Mark Task 4.6.2 subtasks as complete after implementation.

### Help Text

**File**: `/home/ducky/code/jido_code/lib/jido_code/commands.ex`

**Update**: Already includes Ctrl+Tab in help text (line 93), verify accuracy.

## 8. Implementation Risks

### Risk 1: Modifier Key Detection

**Issue**: TermUI might not reliably detect Ctrl+Tab on all terminals

**Mitigation**:
- Test on multiple terminal emulators (Alacritty, iTerm2, Gnome Terminal)
- If detection fails, document limitations in keyboard shortcuts guide
- Provide alternative: Ctrl+] and Ctrl+[ for cycling (if needed)

**Likelihood**: Low (TermUI already handles Ctrl modifiers for Ctrl+1-9)

### Risk 2: Focus Cycling Conflict

**Issue**: Replacing Tab handler might break focus cycling

**Mitigation**:
- Use `cond` with priority order: Ctrl+Tab before Tab
- Add regression tests for Tab/Shift+Tab
- Verify ConversationView scrolling still works (uses Up/Down, not Tab)

**Likelihood**: Very Low (conditional logic isolates behaviors)

### Risk 3: Wrap-Around Edge Case

**Issue**: Modular arithmetic might fail for `current_idx = nil`

**Mitigation**:
- Add guard clause: `case Enum.find_index(...) do nil -> ...; idx -> ... end`
- Unit test specifically for this case
- Log warning if active_session_id not in session_order (indicates bug)

**Likelihood**: Medium (defensive coding required)

### Risk 4: Performance with 10 Sessions

**Issue**: Rapid cycling through 10 sessions might cause UI lag

**Mitigation**:
- Profile cycling performance: `Enum.find_index/2` is O(n), acceptable for n=10
- Avoid reloading messages unnecessarily (already handled by `refresh_conversation_view_for_session/2`)
- Manual test: press Ctrl+Tab 50 times rapidly, verify < 50ms response

**Likelihood**: Very Low (10 sessions is small dataset)

## 9. Rollout Plan

### Development Sequence

1. **Subtask 4.6.2.1**: Implement event handlers (30 min)
   - Modify `event_to_msg/2` at line 819
   - Test: Ctrl+Tab generates `:next_tab`, Ctrl+Shift+Tab generates `:prev_tab`

2. **Subtask 4.6.2.2**: Implement `:next_tab` handler (45 min)
   - Add `update(:next_tab, state)` after line 1185
   - Test: Forward cycling works, wrap-around works

3. **Subtask 4.6.2.3**: Implement `:prev_tab` handler (30 min)
   - Add `update(:prev_tab, state)` after `:next_tab`
   - Test: Backward cycling works, wrap-around works

4. **Subtask 4.6.2.4**: Edge case handling (15 min)
   - Add guards for empty list, single session, nil index
   - Test: Edge cases return gracefully

5. **Subtask 4.6.2.5**: Write unit tests (60 min)
   - Add 14 tests to `tui_test.exs`
   - Run full test suite, fix any failures
   - Verify coverage ≥ 90%

### Testing Sequence

1. **Unit tests**: `mix test test/jido_code/tui_test.exs --only tab_cycling`
2. **Full test suite**: `mix test`
3. **Manual testing**: Follow checklist in Section 6
4. **Integration tests**: Run Phase 4 integration suite
5. **Regression tests**: Verify all existing shortcuts still work

### Commit Strategy

**Single feature commit** (preferred):
```bash
git add lib/jido_code/tui.ex test/jido_code/tui_test.exs
git commit -m "feat(tui): Add Ctrl+Tab and Ctrl+Shift+Tab for session cycling

Implement tab cycling shortcuts to navigate between sessions:
- Ctrl+Tab cycles forward through session_order with wrap-around
- Ctrl+Shift+Tab cycles backward through session_order with wrap-around
- Single session and empty list edge cases handled gracefully
- 14 unit tests with 90%+ coverage

Completes Task 4.6.2 from Phase 4 (TUI Tab Integration).
Follows existing keyboard shortcut patterns (Ctrl+1-9, Ctrl+W).
Focus cycling (Tab/Shift+Tab) remains unchanged."
```

**Alternative: incremental commits**:
1. Event handlers: `feat(tui): Add Ctrl+Tab event detection`
2. Forward cycling: `feat(tui): Implement :next_tab handler`
3. Backward cycling: `feat(tui): Implement :prev_tab handler`
4. Tests: `test(tui): Add 14 tests for tab cycling shortcuts`

## 10. Future Enhancements

This task completes basic tab cycling. Future improvements:

### Enhancement 1: Tab Reordering

**Feature**: Drag-and-drop or Ctrl+Shift+Left/Right to reorder tabs

**Benefit**: Users can organize sessions by priority or project

**Complexity**: Medium (requires tracking drag state, updating session_order)

### Enhancement 2: Tab Preview

**Feature**: Hold Ctrl+Tab to show tab switcher popup (like Alt+Tab in OS)

**Benefit**: Visual preview of all sessions before switching

**Complexity**: High (requires new modal widget, timeout handling)

### Enhancement 3: Tab Groups

**Feature**: Group related sessions (e.g., "Frontend", "Backend", "Docs")

**Benefit**: Cycle within groups, reduce visual clutter

**Complexity**: High (requires group metadata, UI changes)

### Enhancement 4: MRU (Most Recently Used) Cycling

**Feature**: Ctrl+Tab cycles through sessions in MRU order (like VS Code)

**Benefit**: Faster switching between two frequently used sessions

**Complexity**: Medium (requires tracking access timestamps)

**Trade-off**: Breaks spatial consistency (tab order changes)

## 11. References

### Codebase Files

- **Implementation**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`
  - Event handlers: lines 710-825 (event_to_msg/2)
  - Update handlers: lines 1100-1185 (update/2)
  - Model helpers: lines 325-490 (get_session_by_index, switch_session)

- **Tests**: `/home/ducky/code/jido_code/test/jido_code/tui_test.exs`
  - Tab switching tests: lines 2944-3000
  - Focus cycling tests: lines 3636-3680

- **Documentation**:
  - `/home/ducky/code/jido_code/guides/user/keyboard-shortcuts.md`
  - `/home/ducky/code/jido_code/guides/user/sessions.md`

### Related Tasks

- **Task 4.6.1**: Tab Switching Shortcuts (Ctrl+1-9, Ctrl+0) - Completed
- **Task 4.6.3**: Session Close Shortcut (Ctrl+W) - Already implemented
- **Task 4.6.4**: New Session Shortcut (Ctrl+N) - Next in sequence

### Design Documents

- **Phase 4 Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`
- **Session Architecture**: `/home/ducky/code/jido_code/guides/developer/session-architecture.md`
- **Tab Bar Component**: `/home/ducky/code/jido_code/notes/features/tab-bar-component.md`

### External References

- **TermUI Documentation**: `../term_ui/README.md` (event handling)
- **Elm Architecture**: Event-Message-Update pattern
- **Browser Tab Navigation**: Chrome, Firefox, Safari tab cycling behavior

---

**Status**: Ready for implementation
**Estimated Time**: 3 hours (implementation + testing)
**Dependencies**: None (Task 4.6.1 completed)
**Next Task**: Task 4.6.3 (Ctrl+W session close - already implemented, needs tests)
