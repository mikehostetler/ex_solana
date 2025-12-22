# Planning Document: Task 4.5.6 - Sidebar Visual Polish

## Overview

**Task**: Add visual styling, separators, and responsive adjustments (Phase 4.5.6)

**Status**: ✅ Complete

**Context**: Tasks 4.5.1-4.5.5 are complete. The sidebar is integrated into the TUI layout with full keyboard navigation. This task adds visual polish to enhance the user experience with better styling, focus indicators, and visual feedback.

**Dependencies**:
- Phase 4.5.1: Accordion Component ✅ COMPLETE
- Phase 4.5.2: Session Sidebar Component ✅ COMPLETE
- Phase 4.5.3: Model Updates ✅ COMPLETE
- Phase 4.5.4: Layout Integration ✅ COMPLETE
- Phase 4.5.5: Keyboard Shortcuts ✅ COMPLETE

**Blocks**:
- Phase 4.6: Keyboard Navigation (partially implemented)
- Phase 4.7: Event Routing

---

## Current State Analysis

### Existing Styling

**SessionSidebar** (`lib/jido_code/tui/widgets/session_sidebar.ex`):
- ✅ Header styled with cyan/bold (line 148)
- ✅ Active session indicator "→ " prefix (line 229)
- ✅ Session name truncation to 15 chars (line 232)
- ✅ Status icons in badges (✓ ⟳ ✗ ○)
- ✅ Label styles (cyan) for Info/Files/Tools sections
- ✅ Info/muted styles for content

**Accordion** (`lib/jido_code/tui/widgets/accordion.ex`):
- ✅ Expand/collapse icons (▼ ▶)
- ✅ Title style (white)
- ✅ Badge style (yellow)
- ✅ Content indentation (2 spaces default)
- ✅ Icon style infrastructure (line 208)

**Layout Integration** (`lib/jido_code/tui.ex`):
- ✅ Vertical separator already present in `render_vertical_separator/1` (line 1698)
- ✅ Horizontal split layout (sidebar | separator | main)

### What's Missing for Visual Polish

1. **Focus Indicator**: No visual feedback when sidebar has focus
2. **Selection Highlight**: No visual indicator for sidebar_selected_index
3. **Separator Below Header**: No line between "SESSIONS" header and accordion
4. **Hover Styling**: Not applicable (terminal UIs don't support hover)
5. **Enhanced Color Scheme**: Could improve contrast and hierarchy

---

## Solution Overview

### Design Approach

**Minimal Changes Required**: Most visual elements already exist. Focus on:

1. **Add focus indicator**: Render border or style change when `focus: :sidebar`
2. **Add selection highlight**: Style the session at `sidebar_selected_index` differently
3. **Add header separator**: Render horizontal line below "SESSIONS"
4. **Enhance existing styles**: Improve color contrast and visual hierarchy

**Implementation Strategy**:
- Pass focus state and selected_index to SessionSidebar.render/3
- Modify Accordion to accept and render selected_id
- Add separator rendering in SessionSidebar
- Update tests to verify visual elements

---

## Implementation Plan

### 4.5.6.1: Style sidebar header with cyan/bold

**Status**: ✅ Already Complete

**Current Implementation** (session_sidebar.ex:148):
```elixir
defp render_header(width) do
  header_style = Style.new(fg: :cyan, attrs: [:bold])
  header_text = "SESSIONS"
  padded = String.pad_trailing(header_text, width)
  text(padded, header_style)
end
```

**No Action Needed**: Header already styled correctly.

### 4.5.6.2: Style active session with → and appropriate color

**Status**: ✅ Already Complete

**Current Implementation** (session_sidebar.ex:229):
```elixir
def build_title(sidebar, session) do
  prefix = if session.id == sidebar.active_id, do: "→ ", else: ""
  truncated_name = truncate(session.name, 15)
  "#{prefix}#{truncated_name}"
end
```

**Enhancement Needed**: Add color distinction for active session.

**File**: `lib/jido_code/tui/widgets/session_sidebar.ex`

**Changes**:
- Return styled text from `build_title/2` instead of plain string
- Pass title_view to accordion section
- Update Accordion to accept view trees in titles

**New Implementation**:
```elixir
defp build_section(sidebar, session) do
  # Build title with active indicator and style
  title_view = build_title_view(sidebar, session)

  # ... rest unchanged

  %{
    id: session.id,
    title: title_view,  # Now a view tree instead of string
    badge: badge,
    content: content,
    icon_open: "▼",
    icon_closed: "▶"
  }
end

defp build_title_view(sidebar, session) do
  is_active = session.id == sidebar.active_id

  # Active session: green, otherwise white
  title_style = if is_active do
    Style.new(fg: :green, attrs: [:bold])
  else
    Style.new(fg: :white)
  end

  prefix = if is_active, do: "→ ", else: ""
  truncated_name = truncate(session.name, 15)

  text("#{prefix}#{truncated_name}", title_style)
end
```

### 4.5.6.3: Style expanded accordion content with indentation

**Status**: ✅ Already Complete

**Current Implementation** (accordion.ex:250-263):
```elixir
defp render_content(accordion, content_views) do
  # Content is already indented
  indent_spaces = String.duplicate(" ", accordion.indent)

  Enum.map(content_views, fn view ->
    stack(:horizontal, [
      text(indent_spaces),
      view
    ])
  end)
end
```

**No Action Needed**: Content already indented correctly.

### 4.5.6.4: Add vertical separator (│) between sidebar and main

**Status**: ✅ Already Complete

**Current Implementation** (tui.ex:1698-1701):
```elixir
defp render_vertical_separator(_state) do
  separator_style = Style.new(fg: :bright_black)
  text("│", separator_style)
end
```

**No Action Needed**: Vertical separator already implemented.

### 4.5.6.5: Add separator below sidebar header

**File**: `lib/jido_code/tui/widgets/session_sidebar.ex`

**Changes**:
- Add `render_header_separator/1` function
- Update `render/2` to include separator in stack

**Implementation**:
```elixir
@spec render(t(), pos_integer() | nil) :: TermUI.View.t()
def render(%__MODULE__{} = sidebar, width \\ nil) do
  render_width = width || sidebar.width

  # Build header
  header = render_header(render_width)

  # Build separator
  separator = render_header_separator(render_width)

  # Build accordion from sessions
  accordion = build_accordion(sidebar)
  accordion_view = Accordion.render(accordion, render_width)

  # Stack header, separator, and accordion
  stack(:vertical, [header, separator, accordion_view])
end

@doc false
@spec render_header_separator(pos_integer()) :: TermUI.View.t()
defp render_header_separator(width) do
  separator_style = Style.new(fg: :bright_black)
  separator_line = String.duplicate("─", width)
  text(separator_line, separator_style)
end
```

### 4.5.6.6: Adjust colors for collapsed/expanded state

**File**: `lib/jido_code/tui/widgets/accordion.ex`

**Current State**: Icons are same color regardless of state.

**Enhancement**: Use different colors for icon based on expanded/collapsed.

**Implementation**:
```elixir
defp build_title_line(accordion, section, icon, width, is_expanded) do
  # Icon color: cyan when expanded, bright_black when collapsed
  icon_style = if is_expanded do
    Style.new(fg: :cyan)
  else
    Style.new(fg: :bright_black)
  end

  title_style = accordion.style.title_style || Style.new(fg: :white)
  badge_style = accordion.style.badge_style || Style.new(fg: :yellow)

  # Build with styled icon
  stack(:horizontal, [
    text(icon, icon_style),
    text(" "),
    # ... rest of title and badge
  ])
end
```

### 4.5.6.7: Add hover/focus styling (if supported)

**Assessment**: Terminal UIs don't support hover events.

**Alternative**: Add focus indicator when sidebar has focus.

**File**: `lib/jido_code/tui/widgets/session_sidebar.ex`

**Changes**:
- Accept `focused` parameter in render/3
- Render focus border when focused=true

**Implementation**:
```elixir
@spec render(t(), pos_integer() | nil, boolean()) :: TermUI.View.t()
def render(%__MODULE__{} = sidebar, width \\ nil, focused \\ false) do
  render_width = width || sidebar.width

  # Build header
  header = if focused do
    render_focused_header(render_width)
  else
    render_header(render_width)
  end

  # ... rest unchanged
end

@doc false
defp render_focused_header(width) do
  # Brighter cyan + bold for focused state
  header_style = Style.new(fg: :cyan, attrs: [:bold, :underline])
  header_text = "SESSIONS"
  padded = String.pad_trailing(header_text, width)
  text(padded, header_style)
end
```

**Selection Highlighting**: Highlight the session at `sidebar_selected_index`.

**Changes**:
- Accept `selected_index` parameter in render/3
- Pass to accordion to highlight selected section

**Implementation**:
```elixir
@spec render(t(), pos_integer() | nil, boolean(), non_neg_integer()) :: TermUI.View.t()
def render(%__MODULE__{} = sidebar, width \\ nil, focused \\ false, selected_index \\ 0) do
  # ... header as before

  # Build accordion with selection
  selected_session_id = if selected_index < length(sidebar.order) do
    Enum.at(sidebar.order, selected_index)
  else
    nil
  end

  accordion = build_accordion(sidebar, selected_session_id)
  # ...
end

defp build_accordion(sidebar, selected_id) do
  sections =
    sidebar.order
    |> Enum.with_index()
    |> Enum.map(fn {session_id, index} ->
      session = Enum.find(sidebar.sessions, &(&1.id == session_id))

      if session do
        is_selected = session_id == selected_id
        build_section(sidebar, session, is_selected)
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)

  Accordion.new(
    sections: sections,
    active_ids: MapSet.to_list(sidebar.expanded),
    indent: 2
  )
end

defp build_section(sidebar, session, is_selected) do
  # Add selection indicator
  title_view = build_title_view(sidebar, session, is_selected)
  # ...
end

defp build_title_view(sidebar, session, is_selected) do
  is_active = session.id == sidebar.active_id

  # Selection background
  style = cond do
    is_selected and is_active ->
      # Selected + active: green bg + black text
      Style.new(fg: :black, bg: :green, attrs: [:bold])
    is_selected ->
      # Selected only: white bg + black text
      Style.new(fg: :black, bg: :white)
    is_active ->
      # Active only: green text
      Style.new(fg: :green, attrs: [:bold])
    true ->
      # Normal: white text
      Style.new(fg: :white)
  end

  prefix = if is_active, do: "→ ", else: "  "
  truncated_name = truncate(session.name, 15)

  text("#{prefix}#{truncated_name}", style)
end
```

### 4.5.6.8: Write unit tests for visual styling

**File**: `test/jido_code/tui/widgets/session_sidebar_test.exs`

**Test Categories**:

1. **Header Styling Tests** (2 tests)
   - Header renders with cyan/bold style
   - Header separator renders below header

2. **Active Session Styling Tests** (2 tests)
   - Active session has → prefix
   - Active session has green/bold style

3. **Selection Highlighting Tests** (3 tests)
   - Selected session has background highlight
   - Selected + active session has green background
   - Non-selected sessions have normal style

4. **Focus Indicator Tests** (2 tests)
   - Focused sidebar shows underline on header
   - Unfocused sidebar shows normal header

5. **Icon Color Tests** (2 tests)
   - Expanded icon is cyan
   - Collapsed icon is bright_black

**Total**: ~11 tests

---

## Test Plan

### Unit Tests (11 tests)

**Header Styling**:
```elixir
test "header renders with cyan bold style"
test "header separator renders as horizontal line"
```

**Active Session Styling**:
```elixir
test "active session has → prefix"
test "active session has green bold style"
```

**Selection Highlighting**:
```elixir
test "selected session has white background"
test "selected + active session has green background"
test "non-selected sessions have no background"
```

**Focus Indicator**:
```elixir
test "focused sidebar header has underline"
test "unfocused sidebar header has no underline"
```

**Icon Colors**:
```elixir
test "expanded section icon is cyan"
test "collapsed section icon is bright_black"
```

---

## Success Criteria

### Functional Requirements
- ✅ Sidebar header styled with cyan/bold (already complete)
- ✅ Active session has → prefix (already complete)
- ⏸️ Active session has distinct color (green)
- ✅ Expanded content indented (already complete)
- ✅ Vertical separator between sidebar and main (already complete)
- ⏸️ Horizontal separator below header
- ⏸️ Icons colored by expanded/collapsed state
- ⏸️ Focus indicator on sidebar when focused
- ⏸️ Selection highlight for sidebar_selected_index

### Technical Requirements
- ⏸️ 11 unit tests covering all visual elements
- ⏸️ All tests passing
- ⏸️ No breaking changes to existing rendering
- ⏸️ Type specs updated if signatures change

---

## Implementation Summary

### Required Changes

1. **SessionSidebar** (`lib/jido_code/tui/widgets/session_sidebar.ex`):
   - Update `render/2` to `render/4` (add focused, selected_index params)
   - Add `render_header_separator/1`
   - Add `render_focused_header/1`
   - Update `build_title_view/3` with selection styling
   - Update `build_accordion/2` with selected_id
   - Update `build_section/3` with is_selected param

2. **Accordion** (`lib/jido_code/tui/widgets/accordion.ex`):
   - Update `build_title_line/5` with is_expanded for icon coloring
   - Support view trees in section titles (not just strings)

3. **TUI** (`lib/jido_code/tui.ex`):
   - Update `build_session_sidebar/1` to pass focus and selected_index
   - Modify calls to SessionSidebar.render/4

4. **Tests** (`test/jido_code/tui/widgets/session_sidebar_test.exs`):
   - Add 11 visual styling tests

### Files to Modify
- `lib/jido_code/tui/widgets/session_sidebar.ex` (~50 lines changed)
- `lib/jido_code/tui/widgets/accordion.ex` (~20 lines changed)
- `lib/jido_code/tui.ex` (~10 lines changed)
- `test/jido_code/tui/widgets/session_sidebar_test.exs` (~150 lines added)

### Estimated Complexity
- **Low-Medium**: Most infrastructure exists, mainly adding parameters and styling variations
- **Risk**: Type signature changes may require updates in multiple places
- **Time Estimate**: 2-3 hours

---

## Design Decisions

### 1. Selection vs Active vs Both

**States**:
- **Active**: The current session being displayed (→ prefix, green text)
- **Selected**: The session at sidebar_selected_index (background highlight)
- **Both**: Active + selected (green background, black text)

**Rationale**: Clear visual hierarchy distinguishes "what's shown" (active) from "what's navigated to" (selected).

### 2. Focus Indicator on Header vs Border

**Decision**: Use underline on header instead of full border.

**Rationale**:
- Simpler implementation
- Less visual clutter
- Clear indication of focus state
- Compatible with existing layout

### 3. Icon Color by State

**Decision**: Cyan when expanded, bright_black when collapsed.

**Rationale**:
- Provides visual feedback on state
- Cyan draws attention to expanded sections
- Muted color for collapsed sections reduces noise
- Consistent with existing cyan theme

### 4. Backward Compatibility

**Decision**: Add optional parameters with defaults, maintain old signature.

**Implementation**:
```elixir
# Old signature still works
def render(sidebar, width \\ nil) do
  render(sidebar, width, false, 0)
end

# New signature with focus and selection
def render(sidebar, width, focused, selected_index) do
  # ...
end
```

**Rationale**: Avoids breaking existing calls to SessionSidebar.render/2.

---

## Next Steps After 4.5.6

After completing Task 4.5.6, proceed with:

**Phase 4.6: Keyboard Navigation** (partially complete)
- Ctrl+1-9/0 for direct tab switching ✅
- Ctrl+Tab/Shift+Tab for cycling (Task 4.5.5 implemented Tab cycling)
- Ctrl+W for closing sessions ✅
- Ctrl+N for new session ✅

**Phase 4.7: Event Routing**
- Route input to active session
- Route scroll to active session or sidebar
- Handle sidebar-specific events

**Phase 4.8: Integration Tests**
- End-to-end multi-session workflows
- Sidebar interaction tests
- Keyboard navigation tests
- Event routing tests

---

## References

- **Phase Plan**: `/home/ducky/code/jido_code/notes/planning/work-session/phase-04.md` (lines 525-537)
- **SessionSidebar**: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/session_sidebar.ex`
- **Accordion**: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`
- **TUI Layout**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (render_with_session_sidebar/1)
