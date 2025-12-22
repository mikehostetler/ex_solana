# Feature Planning: Accordion Component (Task 4.5.1)

**Status**: ✅ Complete
**Phase**: 4 (TUI Implementation)
**Section**: 4.5 (Sidebar Components)
**Task**: 4.5.1 - Accordion Component
**Created**: 2025-12-15
**Related Documents**:
- Phase 4 Plan: `/home/ducky/code/jido_code/notes/planning/proof-of-concept/phase-04.md`
- ConversationView Widget: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/conversation_view.ex`
- TermUI TreeView: `../term_ui/lib/term_ui/widgets/tree_view.ex`

---

## Problem Statement

The JidoCode TUI needs a reusable accordion widget to display collapsible sections of information. This component will eventually be used to organize:

1. **File Lists** - Files in the current project session
2. **Tool History** - Recent tool executions and results
3. **Context** - Active conversation context and metadata

For the initial implementation (per user scope decision), the accordion widget should provide the **infrastructure** with minimal content. The focus is on the expand/collapse mechanics, badge display, and visual hierarchy.

### Current State

- No accordion widget exists in the codebase
- JidoCode uses TermUI library for TUI rendering (Elm Architecture)
- Existing widget: `ConversationView` demonstrates TermUI `StatefulComponent` patterns
- TermUI provides `TreeView` widget with expand/collapse functionality (reference implementation)

### Desired State

A reusable accordion component in `JidoCode.TUI.Widgets.Accordion` that:
- Renders collapsible sections with expand/collapse icons
- Supports section badges (e.g., file counts, status indicators)
- Provides clean API for adding/updating sections
- Integrates seamlessly with TermUI's rendering system
- Follows established widget patterns in the codebase

---

## Solution Overview

### Architecture

The accordion widget will be implemented as a **TermUI StatefulComponent** following the same pattern as `ConversationView`:

```
JidoCode.TUI.Widgets.Accordion
  ├─ Accordion struct (sections, active_ids, style)
  ├─ Section struct (id, title, content, badge, icons)
  ├─ StatefulComponent callbacks (init, handle_event, render)
  ├─ Public API (expand, collapse, toggle, add_section, etc.)
  └─ Private helpers (rendering, state management)
```

### Design Decisions

1. **TermUI StatefulComponent**: Use `use TermUI.StatefulComponent` for state management
2. **Minimal Initial Content**: Start with empty sections infrastructure, defer actual content to future enhancements
3. **Badge Support**: Include badge infrastructure from the start (for file counts, status indicators)
4. **Icon Customization**: Default icons (▶ collapsed, ▼ expanded), but allow customization
5. **MapSet for Active IDs**: Use `MapSet` for efficient O(1) lookup of expanded sections

### Visual Design

```
╔════════════════════════════════════════╗
║ ▼ Files (12)                           ║  ← Expanded section with badge
║   [file1.ex, file2.ex, ...]            ║  ← Content indented 2 spaces
║                                        ║
║ ▶ Tools (5)                            ║  ← Collapsed section with badge
║                                        ║
║ ▶ Context                              ║  ← Collapsed section, no badge
╚════════════════════════════════════════╝
```

---

## Research Findings

### TermUI Widget Patterns

From examining `ConversationView` and `TreeView`:

#### 1. StatefulComponent Structure

```elixir
defmodule JidoCode.TUI.Widgets.Accordion do
  use TermUI.StatefulComponent

  # Type definitions
  @type section_id :: term()
  @type section :: %{...}
  @type state :: %{...}

  # Props constructor
  def new(opts \\ []) do
    %{sections: ..., ...}
  end

  # Callbacks
  @impl true
  def init(props) do
    {:ok, state}
  end

  @impl true
  def handle_event(event, state) do
    {:ok, new_state}
  end

  @impl true
  def render(state, area) do
    # Return TermUI view tree
  end
end
```

#### 2. State Management Patterns

**From ConversationView**:
- Use MapSet for expanded state: `expanded: MapSet.new()`
- Cursor/focus tracking: `cursor_message_idx: 0`
- Configuration in state: `max_collapsed_lines`, `show_timestamps`, etc.

**From TreeView**:
- Active sections tracking: `expanded: MapSet.new(props.initially_expanded)`
- Flat representation for rendering: `flat_nodes = flatten_nodes(...)`
- Toggle functions: `expand_node/2`, `collapse_node/2`

#### 3. Event Handling Patterns

**Keyboard Events** (from TreeView):
```elixir
def handle_event(%Event.Key{key: :up}, state)
def handle_event(%Event.Key{key: :down}, state)
def handle_event(%Event.Key{key: :enter}, state)
def handle_event(%Event.Key{key: :space}, state)
```

**Mouse Events** (from ConversationView):
```elixir
def handle_event(%Event.Mouse{action: :scroll_up}, state)
def handle_event(%Event.Mouse{action: :click, x: x, y: y}, state)
```

#### 4. Rendering Patterns

**TermUI Primitives Used**:
```elixir
import TermUI.Component.Helpers

# Text rendering
text("Hello", Style.new(fg: :cyan))

# Layout
stack(:vertical, [element1, element2, ...])
stack(:horizontal, [left, right])

# Styling
Style.new(fg: :color, bg: :color, attrs: [:bold, :dim])
```

**From ConversationView**:
- Build list of render nodes, then `stack(:vertical, nodes)`
- Use `text/2` for each line with optional `Style`
- Pad/fill to viewport height if needed

#### 5. Public API Patterns

**State Accessors**:
```elixir
def expanded?(state, section_id)
def get_section(state, section_id)
def section_count(state)
```

**State Modifiers**:
```elixir
def expand(state, section_id)
def collapse(state, section_id)
def toggle(state, section_id)
def add_section(state, section)
def remove_section(state, section_id)
```

---

## Technical Details

### Module Structure

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`

**Dependencies**:
```elixir
use TermUI.StatefulComponent
import TermUI.Component.Helpers
alias TermUI.Renderer.Style
alias TermUI.Event
```

### Data Structures

#### Accordion State

```elixir
@type state :: %{
  # Data
  sections: [section()],

  # Expansion state
  active_ids: MapSet.t(section_id()),

  # Configuration
  style: accordion_style(),
  indent: pos_integer(),
  icons: icon_config()
}
```

#### Section Struct

```elixir
@type section :: %{
  id: section_id(),
  title: String.t(),
  content: [TermUI.View.t()],  # List of TermUI elements
  badge: String.t() | nil,     # Optional badge text
  icon_open: String.t(),       # Default: "▼"
  icon_closed: String.t()      # Default: "▶"
}
```

#### Style Configuration

```elixir
@type accordion_style :: %{
  title_style: Style.t(),      # Section title styling
  badge_style: Style.t(),      # Badge styling
  content_style: Style.t(),    # Content styling
  icon_style: Style.t()        # Icon styling
}
```

### Core Functions

#### Initialization

```elixir
@spec new(keyword()) :: map()
def new(opts \\ []) do
  %{
    sections: Keyword.get(opts, :sections, []),
    initially_expanded: Keyword.get(opts, :initially_expanded, []),
    indent: Keyword.get(opts, :indent, 2),
    icons: Keyword.get(opts, :icons, %{
      open: "▼",
      closed: "▶"
    }),
    style: Keyword.get(opts, :style, default_style())
  }
end

@impl true
def init(props) do
  state = %{
    sections: props.sections,
    active_ids: MapSet.new(props.initially_expanded),
    indent: props.indent,
    icons: props.icons,
    style: props.style
  }

  {:ok, state}
end
```

#### Rendering

```elixir
@impl true
def render(state, _area) do
  if Enum.empty?(state.sections) do
    text("(no sections)", Style.new(fg: :white, attrs: [:dim]))
  else
    nodes = Enum.flat_map(state.sections, fn section ->
      render_section(state, section)
    end)

    stack(:vertical, nodes)
  end
end

defp render_section(state, section) do
  is_expanded = MapSet.member?(state.active_ids, section.id)

  # Render header
  header = render_section_header(state, section, is_expanded)

  # Render content if expanded
  content_nodes =
    if is_expanded and not Enum.empty?(section.content) do
      render_section_content(state, section)
    else
      []
    end

  [header] ++ content_nodes
end

defp render_section_header(state, section, is_expanded) do
  icon = if is_expanded, do: section.icon_open, else: section.icon_closed
  title = section.title
  badge = if section.badge, do: " (#{section.badge})", else: ""

  line = "#{icon} #{title}#{badge}"
  text(line, state.style.title_style)
end

defp render_section_content(state, section) do
  indent_str = String.duplicate(" ", state.indent)

  Enum.map(section.content, fn content_node ->
    # Wrap each content line with indent
    # Note: Simplified - may need more sophisticated indenting
    stack(:horizontal, [
      text(indent_str, nil),
      content_node
    ])
  end)
end
```

#### Event Handling

For the initial implementation, support basic keyboard navigation:

```elixir
@impl true
def handle_event(%Event.Key{key: :enter}, state) do
  # Toggle expand/collapse for focused section (future: cursor tracking)
  {:ok, state}
end

def handle_event(%Event.Key{key: :space}, state) do
  # Toggle expand/collapse for focused section (future: cursor tracking)
  {:ok, state}
end

def handle_event(_event, state) do
  {:ok, state}
end
```

**Note**: For Phase 4.5.1, keyboard navigation can be minimal. Full navigation (cursor, focus) can be added in future enhancements.

#### Public API

```elixir
# Expansion control
@spec expand(state(), section_id()) :: state()
def expand(state, section_id)

@spec collapse(state(), section_id()) :: state()
def collapse(state, section_id)

@spec toggle(state(), section_id()) :: state()
def toggle(state, section_id)

@spec expand_all(state()) :: state()
def expand_all(state)

@spec collapse_all(state()) :: state()
def collapse_all(state)

# Section management
@spec add_section(state(), section()) :: state()
def add_section(state, section)

@spec remove_section(state(), section_id()) :: state()
def remove_section(state, section_id)

@spec update_section(state(), section_id(), (section() -> section())) :: state()
def update_section(state, section_id, update_fn)

# Accessors
@spec expanded?(state(), section_id()) :: boolean()
def expanded?(state, section_id)

@spec get_section(state(), section_id()) :: section() | nil
def get_section(state, section_id)

@spec section_count(state()) :: non_neg_integer()
def section_count(state)
```

### Default Styling

```elixir
defp default_style do
  %{
    title_style: Style.new(fg: :cyan, attrs: [:bold]),
    badge_style: Style.new(fg: :yellow),
    content_style: Style.new(fg: :white),
    icon_style: Style.new(fg: :bright_black)
  }
end
```

---

## Success Criteria

### Functional Requirements

✅ **Core Infrastructure**:
- [ ] Accordion module exists at `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`
- [ ] Implements `TermUI.StatefulComponent` behavior
- [ ] `new/1` creates accordion props with options
- [ ] `init/1` initializes state from props
- [ ] `render/2` produces valid TermUI view tree

✅ **Section Management**:
- [ ] Sections can be defined with `id`, `title`, `content`, `badge`
- [ ] Sections can be added dynamically
- [ ] Sections can be removed by ID
- [ ] Section content is a list of TermUI elements

✅ **Expand/Collapse**:
- [ ] Sections start collapsed by default
- [ ] `initially_expanded` option expands sections on init
- [ ] `expand/2` expands a section by ID
- [ ] `collapse/2` collapses a section by ID
- [ ] `toggle/2` toggles section state
- [ ] `expand_all/1` expands all sections
- [ ] `collapse_all/1` collapses all sections
- [ ] Icons change based on state (▶ collapsed, ▼ expanded)

✅ **Rendering**:
- [ ] Collapsed sections show header only
- [ ] Expanded sections show header + content
- [ ] Content is indented (default: 2 spaces)
- [ ] Badge displays in header when present
- [ ] Empty accordion shows placeholder message

✅ **Styling**:
- [ ] Default styling looks consistent with JidoCode TUI
- [ ] Style can be customized via props
- [ ] Icons can be customized per-section or globally

### Testing Requirements

✅ **Unit Tests** (file: `test/jido_code/tui/widgets/accordion_test.exs`):

```elixir
describe "Accordion.new/1" do
  test "creates accordion with default options"
  test "accepts sections list"
  test "accepts initially_expanded list"
  test "accepts custom indent"
  test "accepts custom icons"
  test "accepts custom style"
end

describe "init/1" do
  test "initializes state from props"
  test "sets active_ids from initially_expanded"
  test "empty sections list works"
end

describe "render/2" do
  test "renders empty accordion with placeholder"
  test "renders accordion with all sections collapsed"
  test "renders accordion with specific sections expanded"
  test "shows correct icon for collapsed sections (▶)"
  test "shows correct icon for expanded sections (▼)"
  test "displays badge when present"
  test "indents content when expanded (2 spaces default)"
  test "handles empty sections list"
  test "applies custom styling correctly"
end

describe "expand/2" do
  test "expands a collapsed section"
  test "no-op if section already expanded"
  test "no-op if section ID not found"
end

describe "collapse/2" do
  test "collapses an expanded section"
  test "no-op if section already collapsed"
  test "no-op if section ID not found"
end

describe "toggle/2" do
  test "expands a collapsed section"
  test "collapses an expanded section"
  test "no-op if section ID not found"
end

describe "expand_all/1" do
  test "expands all sections"
  test "works on empty accordion"
end

describe "collapse_all/1" do
  test "collapses all sections"
  test "works on empty accordion"
end

describe "add_section/2" do
  test "adds section to list"
  test "preserves existing sections"
end

describe "remove_section/2" do
  test "removes section by ID"
  test "preserves other sections"
  test "no-op if section not found"
end

describe "expanded?/2" do
  test "returns true for expanded section"
  test "returns false for collapsed section"
  test "returns false for unknown section ID"
end

describe "get_section/2" do
  test "returns section by ID"
  test "returns nil if not found"
end

describe "section_count/1" do
  test "returns number of sections"
  test "returns 0 for empty accordion"
end
```

### Code Quality

- [ ] Module documented with `@moduledoc`
- [ ] Public functions have `@doc` and `@spec`
- [ ] Follows existing code style (Credo passes)
- [ ] No compiler warnings
- [ ] Passes Dialyzer type checks

---

## Implementation Plan

### Step 1: Create Module Structure (30 min)

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/accordion.ex`

**Tasks**:
1. Create module skeleton with `use TermUI.StatefulComponent`
2. Define type specifications:
   - `@type section_id`
   - `@type section`
   - `@type state`
   - `@type accordion_style`
3. Add module documentation
4. Import required dependencies

**Deliverable**: Module compiles, no errors

---

### Step 2: Implement Props and Initialization (45 min)

**Tasks**:
1. Implement `new/1` function:
   - Accept options: `sections`, `initially_expanded`, `indent`, `icons`, `style`
   - Set defaults
   - Return props map
2. Implement `init/1` callback:
   - Convert props to state
   - Initialize `active_ids` MapSet
   - Return `{:ok, state}`
3. Write initial tests for `new/1` and `init/1`

**Deliverable**: Accordion can be created and initialized

---

### Step 3: Implement Basic Rendering (60 min)

**Tasks**:
1. Implement `render/2` callback:
   - Handle empty sections case
   - Render each section (collapsed state only initially)
2. Implement `render_section/2` helper:
   - Check expansion state
   - Delegate to header/content renderers
3. Implement `render_section_header/3`:
   - Build header with icon, title, badge
   - Apply styling
4. Implement `render_section_content/2`:
   - Add indentation
   - Render content nodes
5. Write rendering tests:
   - Empty accordion
   - Collapsed sections
   - Expanded sections
   - Icon display
   - Badge display
   - Indentation

**Deliverable**: Accordion renders correctly in both collapsed and expanded states

---

### Step 4: Implement Expansion API (45 min)

**Tasks**:
1. Implement `expand/2`:
   - Add section ID to `active_ids`
   - Return updated state
2. Implement `collapse/2`:
   - Remove section ID from `active_ids`
   - Return updated state
3. Implement `toggle/2`:
   - Check current state
   - Call expand or collapse
4. Implement `expand_all/1`:
   - Add all section IDs to `active_ids`
5. Implement `collapse_all/1`:
   - Clear `active_ids`
6. Write expansion API tests

**Deliverable**: Expansion/collapse works correctly via API

---

### Step 5: Implement Section Management API (30 min)

**Tasks**:
1. Implement `add_section/2`:
   - Append to sections list
   - Return updated state
2. Implement `remove_section/2`:
   - Filter sections by ID
   - Also remove from `active_ids`
   - Return updated state
3. Implement `update_section/3`:
   - Find section by ID
   - Apply update function
   - Return updated state
4. Write section management tests

**Deliverable**: Sections can be added, removed, and updated dynamically

---

### Step 6: Implement Accessor Functions (20 min)

**Tasks**:
1. Implement `expanded?/2`
2. Implement `get_section/2`
3. Implement `section_count/1`
4. Write accessor tests

**Deliverable**: State can be queried via clean API

---

### Step 7: Add Event Handling Skeleton (20 min)

**Tasks**:
1. Implement `handle_event/2` callback:
   - Add catch-all clause returning `{:ok, state}`
   - Add placeholder for Enter/Space (future: cursor navigation)
2. Add note in documentation about future keyboard navigation

**Deliverable**: Event handling compiles, but minimal functionality (ok for Phase 4.5.1)

---

### Step 8: Documentation and Cleanup (30 min)

**Tasks**:
1. Add comprehensive `@moduledoc`:
   - Purpose and usage
   - Example
   - Features list
2. Add `@doc` to all public functions
3. Add `@spec` to all public functions
4. Run `mix format`
5. Run `mix credo --strict`
6. Run `mix dialyzer`
7. Fix any issues

**Deliverable**: Code is fully documented and passes quality checks

---

### Step 9: Integration Verification (20 min)

**Tasks**:
1. Create minimal integration test:
   - Start accordion in `iex`
   - Create props with sample sections
   - Initialize state
   - Call `render/2`
   - Verify output looks correct
2. Verify accordion can be used in TUI module (manual inspection, no integration yet)

**Deliverable**: Accordion works end-to-end

---

### Total Estimated Time: **5 hours**

---

## Notes and Considerations

### Scope Boundaries

**In Scope for 4.5.1**:
- Accordion widget infrastructure
- Expand/collapse mechanics
- Badge support
- Basic rendering
- Section management API
- Minimal event handling

**Out of Scope for 4.5.1** (Future Enhancements):
- Keyboard navigation with cursor/focus
- Mouse click to expand/collapse
- Actual content for Files/Tools/Context sections
- Integration into TUI sidebar
- Nested accordions
- Animation/transitions
- Search/filter within accordion

### Integration Points

**Future Integration** (deferred to later tasks):
- **4.5.2**: Integrate accordion into TUI layout
- **4.5.3**: Populate Files section from session
- **4.5.4**: Populate Tools section from tool_calls
- **4.5.5**: Populate Context section from agent state

### Design Rationale

**Why StatefulComponent?**
- Consistent with existing JidoCode widgets (`ConversationView`)
- TermUI's recommended pattern for interactive widgets
- Clean separation of state, props, and rendering

**Why MapSet for active_ids?**
- O(1) membership check for rendering
- Follows pattern from TermUI TreeView
- Efficient for typical use case (<100 sections)

**Why List for Sections?**
- Preserves order for display
- Simple to iterate for rendering
- Easy to add/remove sections

**Why TermUI Elements for Content?**
- Maximum flexibility (can render text, styled text, nested elements)
- Consistent with TermUI rendering model
- Future-proof for complex content

### Testing Strategy

**Unit Tests**: Focus on pure functions and state transformations
- Props creation
- State initialization
- Expansion/collapse logic
- Section management
- Rendering output structure

**Integration Tests** (Future): Test within TUI context
- Rendering in sidebar
- Keyboard navigation
- Content updates

### Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| TermUI API changes | High | Pin to specific TermUI version, monitor releases |
| Performance with many sections | Medium | Start with small lists, profile if needed |
| Rendering complexity | Medium | Keep rendering logic simple, extract helpers |
| Indentation edge cases | Low | Test with various content types |

### Future Enhancements

**Phase 4.5.2+**:
1. **Keyboard Navigation**:
   - Cursor tracking to focus sections
   - Up/Down to navigate
   - Enter/Space to toggle
   - Home/End to jump

2. **Mouse Support**:
   - Click header to toggle
   - Scroll support

3. **Content Population**:
   - Files section: List files from session
   - Tools section: Show recent tool executions
   - Context section: Display active context info

4. **Advanced Features**:
   - Nested accordions
   - Lazy loading for large content
   - Search/filter
   - Custom icons per-section
   - Badges with styling (color-coded status)

5. **Performance**:
   - Virtual rendering for large content
   - Memoization for expensive renders

---

## Dependencies

### Internal Dependencies
- TermUI library (v0.1.x)
- Existing TUI module structure
- Style/Theme system

### External Dependencies
- None (pure Elixir)

### Test Dependencies
- ExUnit
- Standard test infrastructure

---

## Acceptance Checklist

- [ ] Module created at correct path
- [ ] Uses `TermUI.StatefulComponent`
- [ ] All unit tests pass
- [ ] Test coverage > 90%
- [ ] All public functions documented
- [ ] All public functions have `@spec`
- [ ] `mix format` passes
- [ ] `mix credo --strict` passes (no issues)
- [ ] `mix dialyzer` passes (no errors)
- [ ] Module documentation includes usage example
- [ ] Accordion renders with all sections collapsed
- [ ] Accordion renders with specific sections expanded
- [ ] Icons display correctly (▶ collapsed, ▼ expanded)
- [ ] Badges display correctly when present
- [ ] Content is indented when expanded
- [ ] Empty accordion shows placeholder
- [ ] Section management API works (add, remove, update)
- [ ] Expansion API works (expand, collapse, toggle, expand_all, collapse_all)
- [ ] Accessor API works (expanded?, get_section, section_count)
- [ ] Event handling compiles (even if minimal)

---

## References

### Code References

**Similar Widgets**:
- `/home/ducky/code/jido_code/lib/jido_code/tui/widgets/conversation_view.ex` - StatefulComponent example
- `../term_ui/lib/term_ui/widgets/tree_view.ex` - Expand/collapse pattern

**TermUI Documentation**:
- Check `../term_ui` for latest API docs
- `TermUI.StatefulComponent` behavior
- `TermUI.Component.Helpers` (text, stack, box, etc.)

**Styling**:
- `/home/ducky/code/jido_code/lib/jido_code/tui/view_helpers.ex` - Theme usage

### Related Tasks

- **4.5.2**: Accordion integration into sidebar layout
- **4.5.3**: Files section content
- **4.5.4**: Tools section content
- **4.5.5**: Context section content

---

## Implementation Log

_To be filled during implementation_

### 2025-12-15: Planning Complete
- Created comprehensive feature plan
- Researched TermUI widget patterns
- Defined data structures and API
- Created detailed implementation steps
- Estimated 5 hours total effort

---

**End of Planning Document**
