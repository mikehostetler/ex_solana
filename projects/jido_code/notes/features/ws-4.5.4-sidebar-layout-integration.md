# Planning Document: Task 4.5.4 - Sidebar Layout Integration

## Overview

**Task**: Integrate sidebar into existing view layouts with responsive behavior (Phase 4.5.4)

**Status**: ✅ Complete

**Context**: This task is part of Phase 4.5 (Left Sidebar Integration). Tasks 4.5.1 (Accordion Component), 4.5.2 (Session Sidebar Component), and 4.5.3 (Model Updates) are complete. The SessionSidebar widget is ready to be rendered, and the Model has the required state fields. This task integrates the sidebar into the three existing TUI layouts without breaking reasoning panel functionality.

**Dependencies**:
- Phase 4.5.1: Accordion Component ✅ COMPLETE
- Phase 4.5.2: Session Sidebar Component ✅ COMPLETE
- Phase 4.5.3: Model Updates ✅ COMPLETE

**Blocks**:
- Phase 4.5.5: Keyboard Shortcuts
- Phase 4.5.6: Visual Polish

---

## Current State Analysis

### Existing Layout Architecture

**Location**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex` (lines 1558-1659)

The TUI currently has **three layout modes**:

1. **Standard Layout**: No reasoning panel (`show_reasoning == false`)
2. **Reasoning Sidebar Layout**: Wide terminal (`width >= 100`)
3. **Reasoning Drawer Layout**: Narrow terminal (`width < 100`)

### SessionSidebar Widget

- **Default Width**: 20 characters (configurable via `Model.sidebar_width`)
- **Minimum Width**: 20 characters
- **Rendering**: `SessionSidebar.render(sidebar, width)` returns a `TermUI.View.t()` tree

### Model State Fields

Available sidebar state:
```elixir
sidebar_visible: boolean()      # default: true
sidebar_width: pos_integer()    # default: 20
sidebar_expanded: MapSet.t()    # default: MapSet.new()
sidebar_focused: boolean()      # default: false
```

---

## Solution Overview

### Design Approach

**Horizontal Split Layout**:
```
Border ──────────────────────────────────────┐
  Tabs (main area only) ─────────────────┐   │
  Separator (main area only)             │   │
  Status Bar                             │   │
  Separator                              │   │ Vertical Stack
  ┌──────────┬─┬──────────────────────┐  │   │
  │ Sidebar  │││   Main Content       │  │   │ Horizontal Split
  │ 20 chars │││   (dynamic width)    │  │   │
  └──────────┴─┴──────────────────────┘  │   │
  Separator                              │   │
  Input Bar                              │   │
  Separator                              │   │
  Help Bar                           ────┘   │
Border ──────────────────────────────────────┘
```

**Key Decisions**:
1. **Sidebar Position**: Left side, full height between status bar and input bar
2. **Vertical Separator**: Single `│` character between sidebar and main content
3. **Tab Placement**: Tabs render ONLY in main content area (not spanning sidebar)
4. **Responsive Threshold**: Hide sidebar when `width < 90`
5. **Width Formula**: `main_width = content_width - sidebar_width - 1` (1 for separator)

### Responsive Behavior

**Width Thresholds**:
- **< 90 chars**: Hide sidebar
- **90-99 chars**: Show sidebar OR reasoning panel
- **100+ chars**: Show sidebar + reasoning panel

---

## Implementation Plan

### 4.5.4.1: Create render_with_sidebar/1 function

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

Create main layout function that renders sidebar + main content in horizontal split.

**Helper Functions Needed**:
- `build_session_sidebar/1` - Constructs SessionSidebar from model state
- `render_vertical_separator/1` - Renders `│` separator
- `calculate_main_width/1` - Calculates available width for main content

### 4.5.4.2: Update render_main_view/1 to conditionally use sidebar

**File**: `/home/ducky/code/jido_code/lib/jido_code/tui.ex`

Add condition to check `sidebar_visible` and `width >= 90`, then call `render_with_sidebar/1`.

### 4.5.4.3: Implement horizontal split

Build `stack(:horizontal, [sidebar, separator, main])` structure.

### 4.5.4.4: Adjust main content width when sidebar visible

**Width Calculation Formula**:
```
content_width = window_width - 2  # borders
main_width = content_width - sidebar_width - 1  # if sidebar visible
```

### 4.5.4.5: Move tabs to main area

Tabs should render only in main content area when sidebar visible.

### 4.5.4.6: Add responsive behavior

```elixir
show_sidebar = state.sidebar_visible and width >= 90
```

### 4.5.4.7: Ensure sidebar works with reasoning panel

Handle combinations:
- Sidebar + No Reasoning
- Sidebar + Reasoning Sidebar (wide terminal)
- Sidebar + Reasoning Drawer (medium terminal)

### 4.5.4.8: Write unit tests

**Test Categories**:
- Layout selection (5 tests)
- Width calculations (4 tests)
- Sidebar + reasoning panel (4 tests)
- Tab rendering (3 tests)
- Visual verification (4 tests)

**Total**: ~20 tests

---

## Width Calculation Formulas

### Standard Layout (No Sidebar)
```
total_width = window_width
content_width = total_width - 2  # borders
main_width = content_width
```

### Sidebar Layout
```
total_width = window_width
content_width = total_width - 2  # borders
sidebar_width = model.sidebar_width  # default: 20
separator_width = 1
main_width = content_width - sidebar_width - separator_width

constraint: main_width >= 20
constraint: total_width >= 90 (else hide sidebar)
```

### Example Calculations

| Window Width | Content Width | Sidebar | Sep | Main Width |
|--------------|---------------|---------|-----|------------|
| 80           | 78            | -       | -   | 78         |
| 90           | 88            | 20      | 1   | 67         |
| 100          | 98            | 20      | 1   | 77         |
| 120          | 118           | 20      | 1   | 97         |

---

## Success Criteria

### Functional Requirements
- ✅ Sidebar renders when `sidebar_visible == true` and `width >= 90`
- ✅ Sidebar hidden when `width < 90` or `sidebar_visible == false`
- ✅ Horizontal split: Sidebar | Separator | Main content
- ✅ Tabs render only in main area
- ✅ Reasoning panel works with sidebar

### Technical Requirements
- ✅ 20+ unit tests covering all scenarios
- ✅ 100% coverage for new layout functions
- ✅ No breaking changes to existing layouts
- ✅ No performance degradation

---

## Critical Files

1. **lib/jido_code/tui.ex** - Core layout logic (150 new lines)
2. **test/jido_code/tui_test.exs** - Unit tests (200-300 new lines)
3. **lib/jido_code/tui/widgets/session_sidebar.ex** - Reference only

---

## Known Limitations

1. **Minimum Sidebar Width**: 20 characters
2. **Minimum Terminal Width**: 43 characters (20 sidebar + 1 sep + 20 main + 2 borders)

---

## Estimated Implementation Time

- Core layout function: 2 hours
- Helper functions: 1 hour
- Testing: 2-3 hours
- Integration verification: 1 hour

**Total**: 4-6 hours

**Risk Level**: Medium (touches core view rendering logic)
**Success Confidence**: High (clear design, existing patterns to follow)
