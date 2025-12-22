# Feature: WS-3.1.3 PubSub Integration

## Problem Statement

The Tools.Executor broadcasts tool execution events via PubSub, but the current message format doesn't include session_id in the payload. When events are received on the global topic (for backwards compatibility), consumers can't determine which session the event originated from.

Task 3.1.3 requires:
1. Update `broadcast_result/3` to use session-specific topic (already done)
2. Build topic from session_id: `"tui.events.#{session_id}"` (already done)
3. Include session_id in broadcast payload
4. Update `broadcast_tool_call/4` similarly (already done)
5. Write unit tests for broadcast routing

## Current State Analysis

The following is **already implemented**:
- `pubsub_topic/1` - Returns session-specific or global topic
- `broadcast_tool_call/4` - Broadcasts to both session and global topics
- `broadcast_tool_result/2` - Broadcasts to both session and global topics
- ARCH-2 fix - Dual-topic broadcasting for PubSubBridge compatibility
- Existing tests cover topic routing

**Missing**:
- session_id not included in message payloads
- Tests for session_id in payloads

## Solution Overview

Enhance the message payloads to include session_id:

1. **Tool Call Messages**: Change from:
   ```elixir
   {:tool_call, tool_name, params, call_id}
   ```
   To:
   ```elixir
   {:tool_call, tool_name, params, call_id, session_id}
   ```

2. **Tool Result Messages**: Add session_id to Result struct or wrap message:
   ```elixir
   {:tool_result, result, session_id}
   ```

3. **Backwards Compatibility**: Consumers need to handle both old and new formats during transition.

## Technical Details

### Files to Modify

- `lib/jido_code/tools/executor.ex` - Update broadcast functions
- `lib/jido_code/tui.ex` - Update message handlers (if breaking change)
- `lib/jido_code/tui/message_handlers.ex` - Update message handlers
- `test/jido_code/tools/executor_test.exs` - Add tests for session_id in payload

### Message Format Changes

Current:
```elixir
{:tool_call, tool_name, params, call_id}
{:tool_result, result}
```

New:
```elixir
{:tool_call, tool_name, params, call_id, session_id}  # session_id can be nil
{:tool_result, result, session_id}                      # session_id can be nil
```

## Implementation Plan

### Step 1: Update broadcast functions
- [x] Update `broadcast_tool_call/4` to include session_id in message tuple
- [x] Update `broadcast_tool_result/2` to include session_id in message tuple
- [x] Update documentation to reflect new message format

### Step 2: Update TUI message handlers
- [x] Update TUI.ex type spec for tool_call message
- [x] Update TUI.ex update/2 clauses to handle new format
- [x] Update message_handlers.ex to handle new format

### Step 3: Write tests
- [x] Test broadcast_tool_call includes session_id in payload
- [x] Test broadcast_tool_result includes session_id in payload
- [x] Test nil session_id is handled correctly

## Success Criteria

- [x] Tool call messages include session_id (or nil)
- [x] Tool result messages include session_id (or nil)
- [x] TUI handles new message format
- [x] All existing tests pass
- [x] New tests cover session_id in payload

## Current Status

**Status**: Complete

## Summary

All tasks completed:
- Message payloads now include session_id in the final position
- TUI handlers updated to accept new format
- All related tests updated and passing
- Documentation updated to reflect new message format
