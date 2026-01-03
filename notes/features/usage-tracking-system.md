# Feature Planning: Usage Tracking System

**Status**: Planning
**Created**: 2025-12-25
**Branch**: TBD

---

## Problem Statement

JidoCode TUI receives token usage metadata from the LLM agent after each streaming response, but currently discards this valuable information. The metadata includes `input_tokens`, `output_tokens`, and `total_cost` from ReqLLM. Users have no visibility into:

1. How many tokens each response consumes
2. Cumulative token usage across a session
3. Estimated cost per message and per session
4. Historical usage data across sessions

### Current State

**Metadata Flow (already working)**:
1. `LLMAgent.process_stream/3` awaits `metadata_task` from `ReqLLM.StreamResponse`
2. Metadata is extracted via `await_stream_metadata/1` containing usage info
3. `broadcast_stream_end/4` sends `{:stream_end, session_id, full_content, metadata}` via PubSub
4. `MessageHandlers.handle_stream_end/4` receives the metadata but ignores it

**Evidence** (from `lib/jido_code/tui/message_handlers.ex:194`):
```elixir
# TODO: Use metadata for token usage display in status bar
defp handle_active_stream_end(session_id, _full_content, _metadata, state) do
```

**Metadata Structure** (from LLMAgent at line 976-977):
```elixir
if metadata[:usage] do
  Logger.info("LLMAgent: Token usage - #{inspect(metadata[:usage])}")
end
```

The metadata map contains:
- `:usage` - Token usage info map with `input_tokens`, `output_tokens`, `total_cost`
- `:status` - HTTP status
- `:headers` - Response headers
- `:finish_reason` - How the response ended

---

## Solution Overview

### Components

1. **Per-session cumulative tracking** - Store `input_tokens`, `output_tokens`, `total_cost` in session UI state
2. **Status bar display** - Show current session's cumulative tokens/cost
3. **Per-message storage** - Attach usage to each assistant message, display ABOVE message during streaming
4. **Persistent tracking** - Save usage data with sessions for historical analysis

### Display Format

```
📊 Tokens: 150 in / 342 out | Cost: $0.0023
```

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     LLM Agent                                   │
│  broadcast_stream_end(topic, full_content, session_id, metadata)│
│     metadata = %{usage: %{input_tokens: 150, output_tokens: 342,│
│                           total_cost: 0.0023}}                  │
└─────────────────────────────┬───────────────────────────────────┘
                              │ PubSub
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   MessageHandlers                               │
│  handle_stream_end/4                                            │
│    ├─ Extract usage from metadata                               │
│    ├─ Accumulate in session ui_state.usage                      │
│    ├─ Attach to message (ui_state.messages)                     │
│    └─ Update ConversationView with usage line                   │
└─────────────────────────────┬───────────────────────────────────┘
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ ConversationView│  │ ViewHelpers     │  │ Session.State   │
│ render_message  │  │ render_status   │  │ usage tracking  │
│ with usage line │  │ with usage      │  │ (cumulative)    │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## Technical Details

### New Data Structures

#### Usage Map (per-session cumulative)

```elixir
@type usage :: %{
  input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer(),
  total_cost: float()
}

# Initial value
@default_usage %{input_tokens: 0, output_tokens: 0, total_cost: 0.0}
```

#### Extended Message Type

```elixir
@type message :: %{
  id: String.t(),
  role: :user | :assistant | :system | :tool,
  content: String.t(),
  timestamp: DateTime.t(),
  usage: usage() | nil  # Only present for assistant messages
}
```

### Key Files

- `lib/jido_code/tui/message_handlers.ex` - Entry point for usage extraction
- `lib/jido_code/tui/view_helpers.ex` - Status bar and message rendering
- `lib/jido_code/session/persistence/serialization.ex` - Persistence
- `lib/jido_code/tui/widgets/conversation_view.ex` - Streaming display

---

## Implementation Plan

### Step 1: Add Usage Extraction Helpers ✅

**File**: `lib/jido_code/tui/message_handlers.ex`

**Tasks**:
- [x] Create `extract_usage/1` helper function
- [x] Create `accumulate_usage/2` helper function
- [x] Add `@default_usage` module attribute

### Step 2: Update MessageHandlers for Usage ✅

**File**: `lib/jido_code/tui/message_handlers.ex`

**Tasks**:
- [x] Modify `handle_active_stream_end/4` to extract usage from metadata
- [x] Attach usage to assistant message struct
- [x] Accumulate usage in UI state
- [x] Modify `handle_inactive_stream_end/3` similarly

### Step 3: Display Usage in Status Bar ✅

**File**: `lib/jido_code/tui/view_helpers.ex`

**Tasks**:
- [x] Create `format_usage_compact/1` helper (in message_handlers.ex)
- [x] Modify status bar rendering to include cumulative usage
- [x] Handle nil usage gracefully

### Step 4: Display Per-Message Usage Line ✅

**File**: `lib/jido_code/tui/view_helpers.ex`

**Tasks**:
- [x] Create `render_usage_line/1` helper
- [x] Modify `format_message/2` to render usage line ABOVE assistant messages
- [x] Use muted styling (bright_black)

### Step 5: Update ConversationView for Streaming ✅

**Note**: Token usage data only arrives at stream_end (not during streaming chunks). Real-time
updating during streaming would require changes to ReqLLM's streaming architecture. The usage
line appears when the message is finalized.

**Tasks**:
- [x] Added `usage` field to session UI state type
- [x] Added `usage: nil` to default UI state
- [x] Usage is set when stream ends

### Step 6: Persist Usage with Messages ✅

**File**: `lib/jido_code/session/persistence/serialization.ex`

**Tasks**:
- [x] Modify `serialize_message/1` to include usage
- [x] Modify `deserialize_message/1` to parse usage
- [x] Handle legacy messages without usage

### Step 7: Persist Session Cumulative Usage ✅

**Files**:
- `lib/jido_code/session/persistence/serialization.ex`
- `lib/jido_code/session/persistence/schema.ex`

**Tasks**:
- [x] Add `cumulative_usage` to session schema (as optional field)
- [x] Calculate cumulative usage from messages during serialization
- [x] Deserialize session usage
- [x] Handle legacy sessions without usage

### Step 8: Write Tests ✅

**Files**:
- `test/jido_code/tui/message_handlers_test.exs` (NEW - 19 tests)
- `test/jido_code/session/persistence_test.exs` (8 new tests)

**Tests**:
- [x] `extract_usage/1` - various metadata formats
- [x] `accumulate_usage/2` - correct summation
- [x] `format_usage_compact/1` - formatting
- [x] `format_usage_detailed/1` - detailed formatting
- [x] `default_usage/0` - initial values
- [x] Message serialization with usage
- [x] Session cumulative usage calculation

### Step 9: Documentation and Cleanup ⬜

**Tasks**:
- [ ] Update `@moduledoc` for changed modules
- [ ] Add `@doc` and `@spec` for new functions
- [ ] Run `mix format` and `mix credo --strict`

---

## Success Criteria

### Functional Requirements

- [ ] Usage extracted from stream metadata
- [ ] Per-message usage attached to assistant messages
- [ ] Cumulative usage tracked per session
- [ ] Status bar displays session usage
- [ ] Usage line appears above assistant messages
- [ ] Format: `📊 Tokens: X in / Y out | Cost: $Z.ZZZZ`
- [ ] Usage persists with session save/load
- [ ] Legacy messages without usage handled gracefully

### Non-Functional Requirements

- [ ] No visible performance impact during streaming
- [ ] Usage updates in place (not appending lines)
- [ ] Muted styling for usage line (not distracting)
- [ ] Graceful handling of missing metadata

---

## Notes

- The user specified that the per-message usage should be displayed on a single line ABOVE the response
- The line should update in place during streaming as tokens accumulate
- Cost may not always be available depending on the provider/model

---

## Current Status

**What Works**: Metadata flows through to TUI but is ignored
**What's Next**: Step 1 - Add usage extraction helpers
**How to Run**: `mix jido_code`
