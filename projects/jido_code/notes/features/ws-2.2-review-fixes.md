# Feature: WS-2.2 Review Fixes

## Problem Statement

The Section 2.2 review identified 2 blockers, 5 concerns, and 3 suggestions that need to be addressed before production use. These issues affect performance, security, API consistency, and code quality.

## Solution Overview

Address all review findings in a single focused PR:
- Fix O(n) list appends with prepend + reverse-on-read pattern
- Add configurable list size limits with oldest-item eviction
- Add input validation guards on client functions
- Document streaming race condition
- Add missing `get_tool_calls/1` for API consistency
- Fix compiler warning by regrouping clauses
- Extract call/cast helpers to ProcessRegistry
- Add terminate/2 and handle_info/2 callbacks

### Key Decisions

1. **Prepend + reverse-on-read** - Store lists in reverse order (newest first), reverse when retrieving. O(1) append, O(n) read (acceptable tradeoff since reads are less frequent).

2. **Configurable limits** - Use module attributes for max sizes, evict oldest items when limit reached.

3. **Input validation** - Add guards on public functions, validate at boundary not in GenServer.

4. **Registry helpers** - Extract `call/3` and `cast/3` to ProcessRegistry for reuse.

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/session/state.ex` | All implementation changes |
| `lib/jido_code/session/process_registry.ex` | Add call/cast helpers |
| `test/jido_code/session/state_test.exs` | Add tests for limits, validation, get_tool_calls |
| `notes/planning/work-session/phase-02.md` | Mark Task 2.2.2 complete |

### Implementation Plan

#### Step 1: Fix O(n) list append (Blocker 1)
- [ ] Change `append_message/2` handle_call to prepend: `[message | state.messages]`
- [ ] Change `add_reasoning_step/2` handle_call to prepend
- [ ] Change `add_tool_call/2` handle_call to prepend
- [ ] Change `end_streaming/1` handle_call to prepend message
- [ ] Update `get_messages/1` to reverse list before returning
- [ ] Update `get_reasoning_steps/1` to reverse list before returning
- [ ] Add `get_tool_calls/1` client function with reverse

#### Step 2: Add list size limits (Blocker 2)
- [ ] Add module attributes: `@max_messages`, `@max_reasoning_steps`, `@max_tool_calls`
- [ ] Update `append_message/2` to enforce limit with `Enum.take/2`
- [ ] Update `add_reasoning_step/2` to enforce limit
- [ ] Update `add_tool_call/2` to enforce limit
- [ ] Add tests for limit enforcement

#### Step 3: Add input validation (Concern 1)
- [ ] Add guard to `set_scroll_offset/2`: `when is_integer(offset) and offset >= 0`
- [ ] Add guard to `append_message/2`: validate map with required keys
- [ ] Add guard to `update_todos/2`: validate list
- [ ] Add guard to `add_reasoning_step/2`: validate map
- [ ] Add guard to `add_tool_call/2`: validate map
- [ ] Add guard to `start_streaming/2`: validate message_id is string
- [ ] Add guard to `update_streaming/2`: validate chunk is string

#### Step 4: Document streaming race condition (Concern 2)
- [ ] Add warning note to `update_streaming/2` @doc about cast vs call timing
- [ ] Document that chunks may arrive before start_streaming completes
- [ ] Note that this is safe (chunks ignored when not streaming)

#### Step 5: Add get_tool_calls/1 (Concern 3)
- [ ] Add `get_tool_calls/1` client function
- [ ] Add `handle_call(:get_tool_calls, _, state)` callback
- [ ] Return reversed list for chronological order
- [ ] Add tests for get_tool_calls

#### Step 6: Mark Task 2.2.2 complete (Concern 4)
- [ ] Update phase-02.md to mark Task 2.2.2 as complete

#### Step 7: Fix compiler warning - clause grouping (Concern 5)
- [ ] Move all `handle_call/3` clauses together
- [ ] Move all `handle_cast/2` clauses after handle_call group
- [ ] Verify no compiler warning

#### Step 8: Extract Registry helpers (Suggestion 1)
- [ ] Add `ProcessRegistry.call/3` function
- [ ] Add `ProcessRegistry.cast/3` function
- [ ] Update `call_state/2` to use `ProcessRegistry.call/3`
- [ ] Update `cast_state/2` to use `ProcessRegistry.cast/3`
- [ ] Remove private helpers from state.ex

#### Step 9: Add terminate/2 callback (Suggestion 2)
- [ ] Add `terminate/2` callback with debug logging
- [ ] Add test for terminate behavior

#### Step 10: Add handle_info/2 catch-all (Suggestion 3)
- [ ] Add `handle_info/2` catch-all with warning logging
- [ ] Add test for unexpected message handling

## Success Criteria

- [ ] All 47+ tests pass
- [ ] No compiler warnings
- [ ] List operations are O(1) for append
- [ ] Lists have configurable size limits
- [ ] Input validation rejects invalid data
- [ ] API is consistent (all get_* functions exist)
- [ ] ProcessRegistry has reusable call/cast helpers

## Current Status

**Status**: Complete

All review findings have been addressed:
- [x] O(n) list append fixed with prepend + reverse-on-read
- [x] List size limits added (1000 messages, 100 reasoning steps, 500 tool calls)
- [x] Input validation guards added to all client functions
- [x] Streaming race condition documented
- [x] get_tool_calls/1 added for API consistency
- [x] Task 2.2.2 marked complete
- [x] Compiler warning fixed (clause grouping)
- [x] Registry helpers extracted to ProcessRegistry.call/3 and cast/3
- [x] terminate/2 callback added
- [x] handle_info/2 catch-all added
- [x] All 49 tests pass

