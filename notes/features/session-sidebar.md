# Feature Planning: Session Sidebar Component (Task 4.5.2)

**Status**: ✅ Complete
**Phase**: 4 (TUI Implementation)
**Section**: 4.5 (Sidebar Components)
**Task**: 4.5.2 - Session Sidebar Component
**Created**: 2025-12-15
**Dependencies**:
- Task 4.5.1 - Accordion Component (✅ Complete)
- SessionRegistry API for session listing
- Session.State API for message counts
- Session.AgentAPI for status indicators

**Related Documents**:
- Phase 4 Plan: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`
- Accordion Component: `/home/ducky/code/jido_code/notes/features/accordion-component.md`
- Tab Status Indicators: `/home/ducky/code/jido_code/notes/features/tab-status-indicators.md`

---

## Problem Statement

The JidoCode TUI needs a session-specific sidebar component that displays all active work sessions in an accordion format. This provides users with:

1. **Quick Visual Access** - See all sessions at a glance without switching tabs
2. **Session Context** - View session details (info, files, tools) per session
3. **Status Indicators** - See which sessions are processing, idle, or have errors
4. **Message Counts** - Track conversation activity in each session

### Current State

- Session tabs exist at the top of the TUI (Task 4.3 completed)
- Accordion widget infrastructure completed (Task 4.5.1)
- No sidebar component for viewing session details
- Session data scattered across SessionRegistry, Session.State, Session.AgentAPI

### Desired State

A reusable SessionSidebar widget in `JidoCode.TUI.Widgets.SessionSidebar` that:
- Uses Accordion widget to display sessions in collapsible sections
- Shows active session indicator (→ prefix)
- Displays session badges (message count, status)
- Provides minimal/empty session detail sections (Info, Files, Tools) for infrastructure
- Integrates seamlessly with the TUI layout
- Follows established widget patterns in the codebase

### Scope Decision (from User)

**Minimal Implementation** - Focus on infrastructure with placeholder content:
- Session list rendering with accordion
- Active session indicator
- Session badges (message count, status)
- Minimal/empty sections for session details (Info, Files, Tools)
- Defer actual content (file lists, tool history) to future enhancements

---

## Solution Overview

### Architecture

The SessionSidebar widget will be implemented as a **pure rendering component** (not StatefulComponent) that uses the Accordion widget:

```
JidoCode.TUI.Widgets.SessionSidebar
  ├─ SessionSidebar struct (sessions, order, active, expanded, width)
  ├─ render/2 function (model, area)
  ├─ Session badge calculation (message_count, status)
  ├─ Active session indicator (→ prefix)
  ├─ Accordion integration (one section per session)
  └─ Session details rendering (Info, Files, Tools - minimal)
```

### Design Decisions

1. **Pure Rendering Component**: Not a StatefulComponent - receives data from TUI Model
2. **Accordion Integration**: Use completed Accordion widget for expand/collapse
3. **Minimal Sections**: Implement Info, Files, Tools sections with empty/placeholder content
4. **Session Data**: Fetch from SessionRegistry and Session.State on each render
5. **Status Integration**: Reuse `Model.get_session_status/1` from tab indicators
6. **Badge Format**: `"(msgs: 5) ⟳"` - message count + status icon

### Visual Design

```
╔════════════════════════════════╗
║ SESSIONS                       ║  ← Header
║                                ║
║ ▼ → My Project (msgs: 12) ✓   ║  ← Active, expanded, 12 msgs, idle
║     Info                       ║  ← Session details section
║       Created: 2h ago          ║
║     Files                      ║
║       (empty)                  ║
║     Tools                      ║
║       (empty)                  ║
║                                ║
║ ▶ Backend API (msgs: 5) ⟳     ║  ← Collapsed, 5 msgs, processing
║                                ║
║ ▶ Frontend (msgs: 0) ○         ║  ← Collapsed, no msgs, unconfigured
╚════════════════════════════════╝
```

---

## Research Findings

### Session System Data Sources

From examining the Session system code:

#### 1. SessionRegistry - Session List and Lookup

**File**: `/home/ducky/code/jido_code/lib/jido_code/session_registry.ex`

**Key APIs**:
```elixir
# Get all sessions sorted by created_at
@spec list_all() :: [Session.t()]
SessionRegistry.list_all()

# Get active session ID
@spec get_default_session_id() :: {:ok, String.t()} | {:error, :no_sessions}
SessionRegistry.get_default_session_id()
```

**Session Struct** (from `/home/ducky/code/jido_code/lib/jido_code/session.ex`):
```elixir
%Session{
  id: String.t(),              # UUID
  name: String.t(),            # Display name
  project_path: String.t(),    # Absolute path
  config: config(),            # LLM config
  created_at: DateTime.t(),    # Creation timestamp
  updated_at: DateTime.t()     # Last update
}
```

#### 2. Session.State - Message Count

**File**: `/home/ducky/code/jido_code/lib/jido_code/session/state.ex`

**Key APIs**:
```elixir
# Get all messages
@spec get_messages(String.t()) :: {:ok, [message()]} | {:error, :not_found}
Session.State.get_messages(session_id)

# Get message count via pagination metadata
@spec get_messages(String.t(), non_neg_integer(), pos_integer() | :all) ::
  {:ok, [message()], map()} | {:error, :not_found}
Session.State.get_messages(session_id, 0, 0)  # Returns metadata with :total
```

**Message Count Strategy**:
Use pagination API with `limit: 0` to get metadata without fetching messages:
```elixir
case Session.State.get_messages(session_id, 0, 1) do
  {:ok, _, %{total: count}} -> count
  {:error, :not_found} -> 0
end
```

#### 3. Session.AgentAPI - Status

**File**: `/home/ducky/code/jido_code/lib/jido_code/session/agent_api.ex`

**Key APIs**:
```elixir
@spec get_status(String.t()) :: {:ok, status()} | {:error, :agent_not_found}
Session.AgentAPI.get_status(session_id)

# Returns:
%{
  ready: boolean(),         # true = idle, false = processing
  config: config(),
  session_id: String.t(),
  topic: String.t()
}
```

**Status Mapping** (from `/home/ducky/code/jido_code/lib/jido_code/tui.ex`):
```elixir
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

**Status Indicators** (from Task 4.3.3):
- `⟳` - :processing (agent busy)
- `✓` - :idle (agent ready)
- `✗` - :error (agent error)
- `○` - :unconfigured (no agent)

#### 4. TUI Model - Session Access

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 228-249)

**Session Data in Model**:
```elixir
%Model{
  sessions: %{session_id => Session.t()},  # Map of sessions
  session_order: [session_id],             # Display order
  active_session_id: session_id | nil      # Current session
}

# Helper function
@spec get_active_session(Model.t()) :: Session.t() | nil
Model.get_active_session(model)
```

### Accordion Widget Integration

From Task 4.5.1 (`/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`):

**Accordion API**:
```elixir
# Create accordion with sections
Accordion.new(
  sections: [
    %{
      id: section_id,           # Unique identifier
      title: String.t(),        # Section title
      content: [TermUI.View.t()], # Content elements
      badge: String.t() | nil,  # Optional badge
      icon_open: "▼",          # Expanded icon
      icon_closed: "▶"         # Collapsed icon
    }
  ],
  active_ids: [section_id],    # Initially expanded
  style: %{...},               # Styling
  indent: 2                    # Content indentation
)

# Manipulation functions
Accordion.expand(accordion, section_id)
Accordion.collapse(accordion, section_id)
Accordion.toggle(accordion, section_id)
Accordion.expand_all(accordion)
Accordion.collapse_all(accordion)

# Rendering
Accordion.render(accordion, area)
```

**Section Structure for Sessions**:
Each session becomes one accordion section:
```elixir
%{
  id: session.id,
  title: "→ My Project",       # With active indicator
  badge: "(msgs: 12) ✓",       # Message count + status
  content: [
    text("Info"),
    text("  Created: 2h ago"),
    text("Files"),
    text("  (empty)"),
    text("Tools"),
    text("  (empty)")
  ]
}
```

### Name Truncation

From Task 4.3.1 (tab rendering):

```elixir
# Truncate long session names to 15 characters
defp truncate(text, max_length) do
  if String.length(text) > max_length do
    String.slice(text, 0, max_length - 1) <> "…"
  else
    text
  end
end
```

**For Sidebar**: Use same 15-char limit for consistency

---

## Technical Details

### File Structure

```
lib/jido_code/tui/widgets/
  ├── accordion.ex           (✅ Complete)
  └── session_sidebar.ex     (NEW)

test/jido_code/tui/widgets/
  ├── accordion_test.exs     (✅ Complete, 82 tests)
  └── session_sidebar_test.exs  (NEW)
```

### Module Structure

**File**: `lib/jido_code/tui/widgets/session_sidebar.ex`

```elixir
defmodule JidoCode.TUI.Widgets.SessionSidebar do
  @moduledoc """
  Session sidebar widget displaying all sessions in accordion format.

  Shows session list with:
  - Active session indicator (→ prefix)
  - Session badges (message count, status)
  - Collapsible session details (Info, Files, Tools)
  """

  import TermUI.Component.Helpers
  alias JidoCode.TUI.Widgets.Accordion
  alias JidoCode.Session
  alias JidoCode.Session.State
  alias JidoCode.TUI.Model
  alias TermUI.Renderer.Style

  # Type Definitions
  @type t :: %__MODULE__{
    sessions: [Session.t()],
    order: [String.t()],
    active_id: String.t() | nil,
    expanded: MapSet.t(String.t()),
    width: pos_integer()
  }

  defstruct [
    sessions: [],
    order: [],
    active_id: nil,
    expanded: MapSet.new(),
    width: 25
  ]

  # Public API
  @spec new(keyword()) :: t()
  def new(opts \\ [])

  @spec render(t(), TermUI.Area.t()) :: TermUI.View.t()
  def render(sidebar, area)

  # Private Helpers
  defp build_accordion_sections(sidebar)
  defp build_section_for_session(session, sidebar)
  defp format_session_title(session, is_active)
  defp build_session_badge(session_id)
  defp get_message_count(session_id)
  defp get_session_status(session_id)
  defp build_session_details(session)
  defp truncate(text, max_length)
end
```

### Dependencies

**Required Modules**:
- `JidoCode.TUI.Widgets.Accordion` - For accordion rendering
- `JidoCode.SessionRegistry` - For session list
- `JidoCode.Session.State` - For message counts
- `JidoCode.TUI.Model` - For get_session_status/1
- `TermUI.Component.Helpers` - For text/1, vbox/1, etc.

**No External Dependencies** - All required modules are internal to JidoCode.

### Data Flow

```
TUI Model (render cycle)
  ↓
SessionSidebar.new(
  sessions: model.sessions,
  order: model.session_order,
  active_id: model.active_session_id
)
  ↓
SessionSidebar.render(sidebar, area)
  ↓
For each session:
  1. Get message count from Session.State
  2. Get status from Model.get_session_status/1
  3. Build badge: "(msgs: N) [status]"
  4. Build title with → if active
  5. Build minimal details (Info, Files, Tools)
  6. Create accordion section
  ↓
Accordion.render(accordion, area)
  ↓
TermUI view tree
```

### Session Badge Calculation

**Message Count**:
```elixir
defp get_message_count(session_id) do
  case Session.State.get_messages(session_id, 0, 1) do
    {:ok, _, %{total: count}} -> count
    {:error, :not_found} -> 0
  end
end
```

**Status Icon**:
```elixir
defp get_status_icon(session_id) do
  case Model.get_session_status(session_id) do
    :processing -> "⟳"
    :idle -> "✓"
    :error -> "✗"
    :unconfigured -> "○"
  end
end
```

**Badge Format**:
```elixir
defp build_session_badge(session_id) do
  count = get_message_count(session_id)
  icon = get_status_icon(session_id)
  "(msgs: #{count}) #{icon}"
end
```

### Session Details Rendering (Minimal)

**Info Section**:
```elixir
defp build_info_section(session) do
  age = format_time_ago(session.created_at)
  [
    text("Info", style: Style.new(fg: :cyan)),
    text("  Created: #{age}"),
    text("  Path: #{truncate(session.project_path, 20)}")
  ]
end
```

**Files Section** (placeholder):
```elixir
defp build_files_section(_session) do
  [
    text("Files", style: Style.new(fg: :cyan)),
    text("  (empty)", style: Style.new(fg: :gray))
  ]
end
```

**Tools Section** (placeholder):
```elixir
defp build_tools_section(_session) do
  [
    text("Tools", style: Style.new(fg: :cyan)),
    text("  (empty)", style: Style.new(fg: :gray))
  ]
end
```

**Combined Details**:
```elixir
defp build_session_details(session) do
  [
    build_info_section(session),
    build_files_section(session),
    build_tools_section(session)
  ]
  |> List.flatten()
end
```

### Active Session Indicator

**Title Format**:
```elixir
defp format_session_title(session, is_active) do
  truncated = truncate(session.name, 15)

  if is_active do
    "→ #{truncated}"
  else
    "  #{truncated}"
  end
end
```

**Visual**:
```
→ My Project      ← Active session
  Backend API     ← Inactive session
  Frontend        ← Inactive session
```

---

## Success Criteria

### Functional Requirements

- [ ] SessionSidebar.new/1 creates sidebar struct with sessions
- [ ] render/2 displays "SESSIONS" header
- [ ] render/2 builds one accordion section per session
- [ ] Active session shows → prefix in title
- [ ] Session titles truncated to 15 characters max
- [ ] Session badges show message count and status
- [ ] Expanded sessions show Info, Files, Tools sections
- [ ] Info section shows creation time and path
- [ ] Files and Tools sections show "(empty)" placeholder
- [ ] Empty session list handled gracefully

### Performance Requirements

- [ ] Message count fetched efficiently (pagination metadata only)
- [ ] Status query uses existing Model.get_session_status/1
- [ ] No N+1 queries when rendering multiple sessions
- [ ] Rendering completes in <50ms for 10 sessions

### Testing Requirements

- [ ] Unit tests for sidebar structure (7 tests)
- [ ] Unit tests for session badge calculation (4 tests)
- [ ] Unit tests for active indicator (2 tests)
- [ ] Unit tests for name truncation (2 tests)
- [ ] Unit tests for session details rendering (3 tests)
- [ ] Unit tests for empty state (1 test)
- [ ] Total: 19+ unit tests

---

## Implementation Plan

### Phase 1: Module Structure & Constructor (30 min)

**Tasks**:
1. Create `lib/jido_code/tui/widgets/session_sidebar.ex`
2. Define SessionSidebar struct with typespecs
3. Implement `new/1` constructor with options
4. Add module documentation

**Tests** (4 tests):
- Test new/1 creates empty sidebar
- Test new/1 with sessions list
- Test new/1 with active_id
- Test new/1 with expanded sessions

**Files Modified**:
- NEW: `lib/jido_code/tui/widgets/session_sidebar.ex`

### Phase 2: Badge Calculation (45 min)

**Tasks**:
1. Implement `get_message_count/1` using Session.State pagination
2. Implement `get_status_icon/1` using Model.get_session_status/1
3. Implement `build_session_badge/1` combining count + icon
4. Add error handling for missing sessions

**Tests** (4 tests):
- Test message count from Session.State
- Test status icon mapping (idle, processing, error, unconfigured)
- Test badge format "(msgs: N) [icon]"
- Test badge with missing session (returns 0 messages)

**Files Modified**:
- `lib/jido_code/tui/widgets/session_sidebar.ex`

### Phase 3: Title Formatting & Active Indicator (30 min)

**Tasks**:
1. Implement `truncate/2` helper (15 char limit)
2. Implement `format_session_title/2` with → prefix
3. Add tests for active/inactive sessions

**Tests** (3 tests):
- Test active session has → prefix
- Test inactive session has spaces instead
- Test truncation at 15 characters with ellipsis

**Files Modified**:
- `lib/jido_code/tui/widgets/session_sidebar.ex`

### Phase 4: Session Details (Minimal) (45 min)

**Tasks**:
1. Implement `build_info_section/1` with created_at and path
2. Implement `build_files_section/1` with "(empty)" placeholder
3. Implement `build_tools_section/1` with "(empty)" placeholder
4. Implement `build_session_details/1` combining all sections
5. Add time formatting helper `format_time_ago/1`

**Tests** (3 tests):
- Test Info section shows created time and path
- Test Files section shows "(empty)"
- Test Tools section shows "(empty)"

**Files Modified**:
- `lib/jido_code/tui/widgets/session_sidebar.ex`

### Phase 5: Accordion Integration & Rendering (60 min)

**Tasks**:
1. Implement `build_section_for_session/2` creating accordion section
2. Implement `build_accordion_sections/1` mapping all sessions
3. Implement `render/2` with header and accordion
4. Add empty state handling (no sessions)

**Tests** (5 tests):
- Test render/2 displays "SESSIONS" header
- Test render/2 builds one section per session
- Test section structure (id, title, badge, content)
- Test expanded sessions show details
- Test empty session list renders gracefully

**Files Modified**:
- `lib/jido_code/tui/widgets/session_sidebar.ex`

### Phase 6: Test Suite (60 min)

**Tasks**:
1. Create `test/jido_code/tui/widgets/session_sidebar_test.exs`
2. Add test helpers for session fixtures
3. Add test helpers for Session.State mocking
4. Implement all 19+ unit tests
5. Verify test coverage >90%

**Tests**: 19+ unit tests covering all functionality

**Files Modified**:
- NEW: `test/jido_code/tui/widgets/session_sidebar_test.exs`

### Phase 7: Documentation & Review (30 min)

**Tasks**:
1. Add comprehensive module documentation
2. Add function documentation with examples
3. Add inline comments for complex logic
4. Run `mix credo --strict`
5. Run `mix dialyzer`
6. Update this planning document with results

**Files Modified**:
- `lib/jido_code/tui/widgets/session_sidebar.ex`
- `notes/features/session-sidebar.md`

---

## Testing Strategy

### Unit Tests (19+ tests)

**Constructor Tests** (4 tests):
```elixir
describe "new/1" do
  test "creates empty sidebar with defaults"
  test "creates sidebar with sessions list"
  test "creates sidebar with active_id"
  test "creates sidebar with expanded sessions"
end
```

**Badge Tests** (4 tests):
```elixir
describe "build_session_badge/1" do
  test "shows message count from Session.State"
  test "shows idle status icon (✓)"
  test "shows processing status icon (⟳)"
  test "shows error status icon (✗)"
  test "shows unconfigured status icon (○)"
  test "handles missing session gracefully"
end
```

**Title Tests** (3 tests):
```elixir
describe "format_session_title/2" do
  test "active session has → prefix"
  test "inactive session has no prefix"
  test "truncates long names to 15 chars"
end
```

**Details Tests** (3 tests):
```elixir
describe "build_session_details/1" do
  test "Info section shows created time and path"
  test "Files section shows (empty)"
  test "Tools section shows (empty)"
end
```

**Rendering Tests** (5 tests):
```elixir
describe "render/2" do
  test "displays SESSIONS header"
  test "builds one accordion section per session"
  test "section has correct id, title, badge"
  test "expanded section shows session details"
  test "empty session list renders gracefully"
end
```

### Test Fixtures

```elixir
defmodule SessionSidebarTest do
  use ExUnit.Case, async: true

  setup do
    # Create test sessions
    {:ok, session1} = Session.new(project_path: "/tmp/project1")
    {:ok, session2} = Session.new(project_path: "/tmp/project2")

    %{
      sessions: [session1, session2],
      session1: session1,
      session2: session2
    }
  end
end
```

### Integration Testing

**Deferred to Phase 4.6** - Sidebar integration with TUI layout will be tested in view integration tests.

---

## Notes & Considerations

### Performance Optimization

**Message Count Caching**:
- Currently fetches on every render
- Future: Cache in TUI Model, invalidate on message append
- For now: Acceptable for 10 sessions max

**Status Query Optimization**:
- Reuses existing Model.get_session_status/1
- Already optimized in Task 4.3.3
- No additional optimization needed

### Error Handling

**Missing Sessions**:
```elixir
defp get_message_count(session_id) do
  case Session.State.get_messages(session_id, 0, 1) do
    {:ok, _, %{total: count}} -> count
    {:error, :not_found} -> 0  # Handle gracefully
  end
end
```

**Invalid Session IDs**:
- Filter out invalid sessions in build_accordion_sections/1
- Log warnings for debugging

### Future Enhancements (Out of Scope)

**Phase 4.6 - Actual Session Content**:
- Files section: List recently modified files in session
- Tools section: Show recent tool executions with status
- Context section: Show active context items (files, functions)

**Phase 5 - Advanced Features**:
- Click to expand/collapse sections
- Right-click context menu (rename, close, etc.)
- Drag-to-reorder sessions
- Session search/filter

### Alternative Approaches Considered

**1. StatefulComponent vs Pure Rendering**:
- Chose pure rendering for simplicity
- Sidebar state managed by parent TUI component
- No local event handling needed for minimal implementation

**2. Badge Format Options**:
- Option A: `"(12) ✓"` - Minimal, compact
- Option B: `"[12 msgs] ✓"` - More descriptive
- **Chosen**: `"(msgs: 12) ✓"` - Clear but not too verbose

**3. Active Indicator Position**:
- Option A: `"→ My Project"` - Prefix (chosen)
- Option B: `"My Project ←"` - Suffix
- Option C: `"* My Project"` - Star prefix
- **Reasoning**: Prefix → is most visible and consistent with file trees

---

## Acceptance Criteria

### Definition of Done

- [ ] SessionSidebar module created with full documentation
- [ ] Constructor creates sidebar struct with all fields
- [ ] render/2 displays header "SESSIONS"
- [ ] render/2 builds one accordion section per session
- [ ] Active session shows → indicator
- [ ] Session names truncated to 15 chars
- [ ] Session badges show message count and status icon
- [ ] Expanded sessions show Info, Files, Tools sections
- [ ] Info section shows creation time and path
- [ ] Files and Tools sections show "(empty)"
- [ ] Empty session list handled gracefully
- [ ] 19+ unit tests passing with >90% coverage
- [ ] mix credo --strict passes
- [ ] mix dialyzer passes
- [ ] Documentation complete with examples
- [ ] Integration ready for Phase 4.6

### Success Metrics

- **Test Coverage**: >90% line coverage
- **Test Count**: 19+ tests passing
- **Performance**: Renders in <50ms for 10 sessions
- **Code Quality**: Credo grade A, zero Dialyzer warnings
- **Documentation**: All public functions documented

---

## Risk Assessment

### Low Risk
- Accordion widget already complete and tested (82 tests)
- Session data APIs stable and well-tested
- Similar patterns exist in tab rendering (Task 4.3)

### Medium Risk
- Message count fetching may be slow for large conversations
  - Mitigation: Use pagination metadata (total only)
  - Mitigation: Future caching in TUI Model

### Minimal Risk
- Empty state handling edge cases
  - Mitigation: Comprehensive unit tests
  - Mitigation: Defensive programming (default values)

---

## Timeline Estimate

| Phase | Task | Time | Tests |
|-------|------|------|-------|
| 1 | Module Structure | 30 min | 4 |
| 2 | Badge Calculation | 45 min | 4 |
| 3 | Title & Active Indicator | 30 min | 3 |
| 4 | Session Details (Minimal) | 45 min | 3 |
| 5 | Accordion & Rendering | 60 min | 5 |
| 6 | Test Suite | 60 min | 19+ |
| 7 | Documentation & Review | 30 min | - |
| **Total** | | **5 hours** | **19+ tests** |

---

## Next Steps

After completion of this task (4.5.2):

1. **Task 4.5.3** - Sidebar Toggle (Ctrl+S)
2. **Task 4.5.4** - Layout Integration (add sidebar to view/1)
3. **Task 4.6** - Session Content (populate Files, Tools sections)
4. **Task 4.7** - Keyboard Shortcuts (session navigation)

---

## References

### Session System
- SessionRegistry: `/home/ducky/code/jido_code/lib/jido_code/session_registry.ex`
- Session: `/home/ducky/code/jido_code/lib/jido_code/session.ex`
- Session.State: `/home/ducky/code/jido_code/lib/jido_code/session/state.ex`
- Session.AgentAPI: `/home/ducky/code/jido_code/lib/jido_code/session/agent_api.ex`

### Widgets
- Accordion: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`
- ConversationView: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/conversation_view.ex`

### TUI
- TUI Model: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`
- ViewHelpers: `/home/ducky/code/jido_code/lib/jido_code/tui/view_helpers.ex`

### Planning
- Phase 4 Plan: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md`
- Accordion Feature: `/home/ducky/code/jido_code/notes/features/accordion-component.md`
- Tab Status: `/home/ducky/code/jido_code/notes/features/tab-status-indicators.md`

---

**End of Planning Document**
