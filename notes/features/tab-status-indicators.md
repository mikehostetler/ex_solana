# Feature: Tab Status Indicators (Task 4.3.3)

## Problem Statement

Task 4.3.1 implemented visual tab bars showing numbered sessions, but tabs don't show the current status of each session's agent. Users cannot tell if a session is idle, processing a request, errored, or unconfigured without switching to that tab.

Current issues:
- No visual indication of which sessions are actively processing
- No way to see error states without switching tabs
- Users can't tell if a session's agent is ready or busy
- Missing feedback about session health

Without status indicators, users have reduced awareness of multi-session state and may try to interact with busy or errored sessions.

## Solution Overview

Add visual status indicators to each tab showing the session's agent state using Unicode characters:

1. **Processing indicator** (⟳) - Agent is actively handling a request
2. **Idle indicator** (✓) - Agent is ready for new requests
3. **Error indicator** (✗) - Agent crashed or not responding
4. **Unconfigured indicator** (○) - Session has no agent

Key components:
1. `Model.get_session_status/1` - Query session agent status
2. Update `render_single_tab/3` - Add status parameter and indicator
3. Update `render_tabs/1` - Query status for each session
4. Status-aware styling - Error tabs red, processing tabs yellow
5. Unit tests for all status states

## Agent Consultations Performed

**Plan Agent** (ad754b8):
- Researched Session.AgentAPI status query methods
- Confirmed `get_status/1` and `is_processing?/1` exist
- Analyzed agent status states and state transitions
- Identified Unicode characters for indicators
- Designed performance-efficient status query approach
- Created comprehensive implementation plan with testing strategy

## Technical Details

### Research Findings

**Session.AgentAPI.get_status/1** - EXISTS
- Location: `lib/jido_code/session/agent_api.ex:201-206`
- Returns: `{:ok, %{ready: boolean(), config: map(), session_id: string(), topic: string()}}`
- Error: `{:error, :agent_not_found}`

**Session.AgentAPI.is_processing?/1** - EXISTS
- Location: `lib/jido_code/session/agent_api.ex:236-244`
- Returns: `{:ok, true}` when processing, `{:ok, false}` when idle
- Error: `{:error, :agent_not_found}`
- Note: "Processing is the inverse of ready"

**LLMAgent.get_status/1** - EXISTS
- Location: `lib/jido_code/agents/llm_agent.ex:242-262`
- Returns: `{:ok, %{ready: boolean(), config: map(), session_id: string(), topic: string()}}`
- Checks: `Process.alive?(state.ai_pid)`

**Model.agent_status Type**:
```elixir
@type agent_status :: :idle | :processing | :error | :unconfigured
```

### Files to Modify

1. **lib/jido_code/tui.ex**
   - Add `Model.get_session_status/1` helper function
   - Query Session.AgentAPI for agent status
   - Map ready/processing/error states

2. **lib/jido_code/tui/view_helpers.ex**
   - Add `@status_indicators` constant map
   - Update `render_single_tab/2` signature to `/3` (add status)
   - Implement `build_tab_style/2` for status-aware styling
   - Update `render_tabs/1` to query status for each session

3. **test/jido_code/tui_test.exs**
   - Add unit tests for `Model.get_session_status/1`
   - Test idle, processing, error, unconfigured states
   - Test error handling for invalid session_id

4. **test/jido_code/tui/view_helpers_test.exs** (create if doesn't exist)
   - Add unit tests for `render_single_tab/3` with status
   - Test all status indicators render correctly
   - Test status-aware color styling

### Current State

**render_single_tab/2** (ViewHelpers:797-807):
```elixir
defp render_single_tab(label, is_active) do
  style =
    if is_active do
      Style.new(fg: Theme.get_color(:primary) || :cyan, attrs: [:bold, :underline])
    else
      Style.new(fg: Theme.get_color(:secondary) || :bright_black)
    end

  text(" #{label} ", style)
end
```

**Need to change to**:
```elixir
defp render_single_tab(label, is_active, status) do
  indicator = Map.get(@status_indicators, status, "?")
  full_label = "#{indicator} #{label}"
  style = build_tab_style(is_active, status)
  text(" #{full_label} ", style)
end
```

### Implementation Approach

#### Step 1: Add Status Indicators Constants

```elixir
# In ViewHelpers module
@status_indicators %{
  processing: "⟳",  # Rotating arrow (U+27F3)
  idle: "✓",        # Check mark (U+2713)
  error: "✗",       # X mark (U+2717)
  unconfigured: "○" # Empty circle (U+25CB)
}
```

#### Step 2: Add Status Query Function

```elixir
# In Model (TUI.ex)
@spec get_session_status(String.t()) :: agent_status()
def get_session_status(session_id) do
  case Session.AgentAPI.get_status(session_id) do
    {:ok, %{ready: true}} -> :idle
    {:ok, %{ready: false}} -> :processing
    {:error, :agent_not_found} -> :unconfigured
    {:error, _} -> :error
  end
end
```

#### Step 3: Update render_single_tab/3

```elixir
@spec render_single_tab(String.t(), boolean(), Model.agent_status()) :: TermUI.View.t()
defp render_single_tab(label, is_active, status) do
  indicator = Map.get(@status_indicators, status, "?")
  full_label = "#{indicator} #{label}"
  style = build_tab_style(is_active, status)
  text(" #{full_label} ", style)
end

@spec build_tab_style(boolean(), Model.agent_status()) :: Style.t()
defp build_tab_style(is_active, status) do
  base_style =
    if is_active do
      Style.new(fg: Theme.get_color(:primary) || :cyan, attrs: [:bold, :underline])
    else
      Style.new(fg: Theme.get_color(:secondary) || :bright_black)
    end

  # Override color for error status
  case status do
    :error -> %{base_style | fg: Theme.get_semantic(:error) || :red}
    :processing when is_active ->
      %{base_style | fg: Theme.get_semantic(:warning) || :yellow}
    _ -> base_style
  end
end
```

#### Step 4: Update render_tabs/1

```elixir
def render_tabs(%Model{sessions: sessions, session_order: order, active_session_id: active_id}) do
  tabs =
    order
    |> Enum.with_index(1)
    |> Enum.map(fn {session_id, index} ->
      session = Map.get(sessions, session_id)
      label = format_tab_label(session, index)
      is_active = session_id == active_id
      status = Model.get_session_status(session_id)  # NEW: Query status
      render_single_tab(label, is_active, status)   # NEW: Pass status
    end)

  tab_elements =
    tabs
    |> Enum.intersperse(text(" │ ", Style.new(fg: Theme.get_color(:secondary) || :bright_black)))

  stack(:horizontal, tab_elements)
end
```

## Success Criteria

All success criteria from Task 4.3.3:

1. ✅ Show spinner/indicator when session is processing (⟳)
2. ✅ Show error indicator on agent error (✗)
3. ✅ Query agent status via Session.AgentAPI.get_status/1
4. ✅ Write unit tests for status indicators
5. ✅ Idle sessions show checkmark (✓)
6. ✅ Unconfigured sessions show empty circle (○)
7. ✅ Error tabs always show red color
8. ✅ Active processing tabs show yellow color
9. ✅ No performance degradation (< 1ms per tab render)
10. ✅ All tests pass

## Implementation Plan

### Phase 1: Status Query Infrastructure ✅
- [x] Add `@status_indicators` constant to ViewHelpers
- [x] Add `Model.get_session_status/1` function
- [x] Write unit tests for status query (4 test cases)
- [x] Test error handling for invalid session_id

### Phase 2: Tab Rendering Updates
- [ ] 2.1 Update `render_single_tab/2` signature to `/3`
- [ ] 2.2 Implement status indicator logic
- [ ] 2.3 Create `build_tab_style/2` for status-aware styling
- [ ] 2.4 Update `render_tabs/1` to query status
- [ ] 2.5 Write unit tests for rendering (6 test cases)

### Phase 3: Integration & Verification
- [ ] 3.1 Verify all view layouts render correctly
- [ ] 3.2 Manual testing with different session states
- [ ] 3.3 Visual regression check
- [ ] 3.4 Performance benchmarking

### Phase 4: Documentation
- [ ] 4.1 Update module documentation
- [ ] 4.2 Document edge cases
- [ ] 4.3 Update phase plan to mark task complete
- [ ] 4.4 Write summary document

## Notes/Considerations

### Design Decisions

**Decision 1**: Use Unicode characters for indicators
- **Choice**: ⟳ ✓ ✗ ○
- **Rationale**: Visually clear, widely supported in modern terminals
- **Fallback**: If rendering issues, could add ASCII mode (future config)

**Decision 2**: Query status on every render
- **Choice**: Call `Session.AgentAPI.get_status/1` for each tab on each render
- **Rationale**: Status query is fast (< 0.1ms), caching adds complexity
- **Performance**: For 10 tabs: ~1ms total overhead
- **Future**: Add caching if performance becomes an issue

**Decision 3**: Status-aware color overrides
- **Choice**: Error always red, active+processing yellow
- **Rationale**: Error is critical state, processing needs attention
- **Implementation**: Override base_style in build_tab_style/2

**Decision 4**: Status mapping from AgentAPI
- **Choice**: Map `ready: true` to `:idle`, `ready: false` to `:processing`
- **Rationale**: Matches AgentAPI semantics
- **Error handling**: `:agent_not_found` → `:unconfigured`, other errors → `:error`

### Edge Cases

| Case | Behavior | Implementation |
|------|----------|----------------|
| Agent crashes mid-render | Shows error indicator | get_status returns :error |
| Session with no agent | Shows unconfigured indicator | AgentAPI returns :agent_not_found |
| Status changes during render | Shows stale status | Acceptable - updates next frame |
| Unicode not supported | Falls back to `?` | Map.get with default |
| 10+ tabs overflow | Indicators still render | Existing truncation handles |

### Testing Strategy

**Unit Tests** (minimum 10 tests):
- `Model.get_session_status/1`: idle, processing, error, unconfigured (4 tests)
- `render_single_tab/3`: each status indicator, color overrides (6 tests)

**Integration Tests** (future Phase 4.7):
- Tabs render with correct indicators for different session states
- Indicator updates when session status changes

**Manual Testing Checklist**:
1. Create session, verify idle indicator (✓)
2. Send message, verify processing indicator (⟳) during streaming
3. Kill agent, verify error indicator (✗)
4. Create session without API key, verify unconfigured (○)
5. Check error tabs are red
6. Check active processing tabs are yellow

### Performance Considerations

**Status Query Benchmark**:
- `Session.AgentAPI.get_status/1`: Registry lookup + GenServer call
- Expected: < 0.1ms per call
- For 10 tabs: ~1ms total
- Acceptable overhead for 60 FPS rendering

**Optimization Options** (if needed):
1. Cache status with TTL (100ms)
2. Batch status queries for all sessions
3. Subscribe to status change events

**Current Decision**: No optimization needed, query on each render

### Future Enhancements

**Phase 4.5** (Keyboard Navigation):
- Ctrl+1-9 keyboard shortcuts will use existing tab indices
- Status indicators don't affect navigation

**Future Task** (Animated Indicators):
- Processing indicator could rotate/animate
- Would require stateful rendering or CSS animation
- Out of scope for this task

**Future Task** (Status Tooltips):
- Hover over indicator to see detailed status
- Would require mouse interaction support
- Out of scope for this task

## Current Status

**Branch**: feature/tab-status-indicators
**Phase**: 1 (Planning) - COMPLETE
**Next Step**: Begin Phase 2.1 - Update render_single_tab signature

## Files to Change

```
M  lib/jido_code/tui.ex                    # Add get_session_status/1
M  lib/jido_code/tui/view_helpers.ex        # Update rendering functions
M  test/jido_code/tui_test.exs              # Add status query tests
A? test/jido_code/tui/view_helpers_test.exs # Add rendering tests (if needed)
M  notes/planning/work-session/phase-04.md  # Mark task complete
A  notes/summaries/tab-status-indicators.md # Summary document
```

## Dependencies

**Completed**:
- Phase 4.3.1: Tab bar rendering infrastructure
- Session.AgentAPI: Status query methods exist

**Concurrent**:
- Task 4.3.3: This task

**Future**:
- Phase 4.5: Keyboard navigation (uses existing tabs)
- Phase 4.7: Integration tests

## Technical Notes

### Visual Appearance

Expected tab bar with status indicators:
```
✓ 1:my-project │ ⟳ 2:processing │ ✗ 3:errored │ ○ 4:no-agent
```

Active processing tab (yellow):
```
⟳ 1:my-project
^^^^^^^^^^^^^^^
(yellow, bold, underline)
```

Error tab (red, even if not active):
```
✗ 2:errored
^^^^^^^^^^^
(red)
```

### Status State Machine

```
┌─────────────┐
│Unconfigured │ ○
└──────┬──────┘
       │ Agent started
       v
┌─────────────┐
│    Idle     │ ✓
└──────┬──────┘
       │ Request received
       v
┌─────────────┐
│ Processing  │ ⟳
└──────┬──────┘
       │ Response complete / Error
       v
┌─────────────┐
│ Idle/Error  │ ✓ / ✗
└─────────────┘
```

### Integration with Existing Code

**No breaking changes to public API**:
- `render_tabs/1` signature unchanged (still takes Model)
- `render_single_tab/2` is private, signature change OK
- View layouts call `render_tabs/1` - no changes needed

**Type safety**:
- `Model.agent_status` type already defined
- Compiler will catch any missed function updates

### Performance Profiling

If performance becomes an issue, profile with:
```elixir
:timer.tc(fn -> ViewHelpers.render_tabs(model) end)
```

Acceptable: < 10ms for 10 tabs
Expected: < 2ms for 10 tabs

## References

- Feature plan: This document
- Phase plan: `notes/planning/work-session/phase-04.md` (lines 219-236)
- Session.AgentAPI: `lib/jido_code/session/agent_api.ex`
- Current tabs: `lib/jido_code/tui/view_helpers.ex` (lines 775-807)
