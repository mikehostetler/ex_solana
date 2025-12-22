# WS-4.1.1 TUI Model Struct Changes for Multi-Session Support

**Branch:** `feature/ws-4.1.1-model-struct-changes`
**Date:** 2025-12-06
**Status:** Complete

## Overview

Restructure the TUI Model struct to support multiple sessions with tab-based navigation. This is the foundational change for Phase 4 (TUI Tab Integration).

## Problem Statement

The current TUI Model stores per-session data (messages, reasoning_steps, tool_calls, streaming_message) directly in the struct. For multi-session support, these need to be fetched from Session.State while the Model tracks which sessions exist and which is active.

### Current Model Structure

```elixir
defstruct [
  # Per-session data (needs to move to Session.State)
  messages: [],
  reasoning_steps: [],
  tool_calls: [],
  streaming_message: nil,
  is_streaming: false,

  # Shared UI state (stays in Model)
  text_input: nil,
  window: {80, 24},
  show_reasoning: false,
  show_tool_details: false,
  agent_status: :unconfigured,
  config: %{provider: nil, model: nil},
  ...
]
```

### Target Model Structure

```elixir
defstruct [
  # Session management (NEW)
  sessions: %{},           # session_id => Session.t()
  session_order: [],       # List of session_ids in tab order
  active_session_id: nil,  # Currently focused session

  # Shared UI state (existing)
  window: {80, 24},
  text_input: nil,
  show_reasoning: false,
  focus: :input,           # NEW: :tabs | :conversation | :input

  # Modals (shared across sessions)
  shell_dialog: nil,
  pick_list: nil,

  # Per-session fields REMOVED - now in Session.State:
  # messages, reasoning_steps, tool_calls, streaming_message, is_streaming

  # Keep for backwards compatibility during transition:
  messages: [],            # DEPRECATED: Will be removed in 4.2
  ...
]
```

## Implementation Plan

### Step 1: Add Session Tracking Fields ✅
- [x] Add `sessions: %{}` field to Model struct
- [x] Add `session_order: []` field to Model struct
- [x] Add `active_session_id: nil` field to Model struct
- [x] Keep existing fields for backwards compatibility

### Step 2: Update Type Definitions ✅
- [x] Update `@type t()` to include new session fields
- [x] Add `@type focus()` for focus states (:tabs | :conversation | :input)
- [x] Add `@type session_map()` for sessions field

### Step 3: Write Unit Tests ✅
- [x] Test Model struct has session tracking fields
- [x] Test default values are correct
- [x] Test typespec compiles correctly
- [x] 13 tests, 0 failures

## Files to Modify

- `lib/jido_code/tui.ex` - Model struct and types

## Files to Create

- `test/jido_code/tui/model_test.exs` - Unit tests for Model struct

## Success Criteria

1. Model struct includes `sessions`, `session_order`, `active_session_id` fields
2. Type definitions include `@type focus()`
3. Existing TUI functionality unchanged (backwards compatible)
4. Unit tests pass
5. Application compiles without warnings

## Notes

- This is a non-breaking change - existing per-session fields remain for backwards compatibility
- Actual migration to Session.State for per-session data happens in Task 4.1.2 and 4.2.x
- The `focus` field enables keyboard navigation between tabs, conversation, and input areas
