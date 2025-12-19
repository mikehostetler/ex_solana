# Feature: Phase 5 Review Fixes

## Problem Statement

The Phase 5 review identified several blockers, concerns, and improvements needed before Phase 6. These issues affect performance, reliability, security, and code maintainability.

## Solution Overview

Fix all identified issues in priority order:
1. **Blockers:** PubSub topic mismatch, list concatenation performance, atom poisoning
2. **Concerns:** Streaming timeout, code duplication, API key exposure, message type inconsistency
3. **Suggestions:** Centralize PubSub topics, message builders, logging, role formatting

## Implementation Plan

### Step 1: Fix List Concatenation Performance (Critical)
- [x] 1.1 Change `messages ++ [msg]` to `[msg | messages]` in TUI
- [x] 1.2 Change `reasoning_steps ++ [step]` to prepend
- [x] 1.3 Change `tool_calls ++ [entry]` to prepend
- [x] 1.4 Update view functions to reverse lists when displaying
- [x] 1.5 Update tests if needed

### Step 2: Fix Atom Poisoning Vulnerability (Critical)
- [x] 2.1 Create provider whitelist map in Commands module
- [x] 2.2 Replace String.to_atom with whitelist lookup
- [x] 2.3 Update Settings provider handling with to_existing_atom
- [x] 2.4 Update Config provider handling with to_existing_atom

### Step 3: Fix PubSub Topic Architecture (Critical)
- [x] 3.1 Create JidoCode.PubSubTopics module
- [x] 3.2 Update TUI to use centralized topics
- [x] 3.3 Update LLMAgent to use centralized topics
- [x] 3.4 Update Commands to use centralized topics
- [x] 3.5 Ensure TUI subscribes to correct session topic

### Step 4: Add Streaming Timeout (High)
- [x] 4.1 Implement timeout wrapper do_chat_stream_with_timeout
- [x] 4.2 Add Task.async with Task.yield/shutdown for timeout handling
- [x] 4.3 Broadcast stream_error on timeout

### Step 5: Extract System Message Helper (Medium)
- [x] 5.1 Create system_message/1 helper in TUI (part of message builders)
- [x] 5.2 Refactor all system message creation to use helper

### Step 6: Extract Message Formatting Helper (Medium)
- Note: Deferred - existing code is maintainable as-is

### Step 7: Create Message Builder Helpers (Medium)
- [x] 7.1 Add user_message/1, assistant_message/1, system_message/1
- [x] 7.2 Refactor message creation to use builders

### Step 8: Fix API Key Error Messages (Medium)
- [x] 8.1 Make error messages generic (no env var names)

### Step 9: Normalize Message Types (Low)
- [x] 9.1 LLMAgent now broadcasts :agent_response (not :llm_response)
- [x] 9.2 TUI already handles both :config_change and :config_changed
- [x] 9.3 All broadcasters use normalized types

### Step 10: Fix Entity.to_iri (Low)
- [x] 10.1 Use KnowledgeGraph.entity_base_iri() instead of hardcoded URL

### Step 11: Add Logging to Catch-all (Low)
- [x] 11.1 Add Logger.debug to unhandled message catch-all

### Step 12: Run Tests and Verify
- [x] 12.1 Run full test suite
- [x] 12.2 Fix any broken tests
- [x] 12.3 Verify all functionality works

## Success Criteria

1. ✅ All tests pass (954 tests, 0 failures)
2. ✅ No list concatenation with `++` for growing lists
3. ✅ Provider validation uses whitelist (no String.to_atom on user input)
4. ✅ PubSub topics centralized
5. ✅ Streaming has timeout handling
6. ✅ Code duplication reduced (message builders)
7. ✅ Message types normalized

## Current Status

**Status**: Complete
**What Works**: All review fixes implemented and tested

## Files Changed

- `lib/jido_code/pubsub_topics.ex` (new) - Centralized PubSub topic definitions
- `lib/jido_code/tui.ex` - List prepend, message builders, session subscription, catch-all logging
- `lib/jido_code/agents/llm_agent.ex` - Streaming timeout, normalized message types, centralized topics
- `lib/jido_code/commands.ex` - Provider whitelist, generic API key errors, centralized topics
- `lib/jido_code/settings.ex` - Safe atom conversion
- `lib/jido_code/config.ex` - Safe atom conversion
- `lib/jido_code/knowledge_graph.ex` - Added entity_base_iri/0
- `lib/jido_code/knowledge_graph/entity.ex` - Use centralized entity base IRI
- `test/jido_code/tui_test.exs` - Updated for reverse-order storage
- `test/jido_code/commands_test.exs` - Updated for generic error messages
