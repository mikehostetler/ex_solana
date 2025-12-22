# Phase 5: Session Commands

This phase implements the `/session` command family for managing sessions via the command interface. Commands allow creating, listing, switching, closing, and renaming sessions.

---

## 5.1 Command Parser Updates

Update the command parser to recognize session commands.

### 5.1.1 Session Command Registration
- [x] **Task 5.1.1** (completed 2025-12-06)

Add session commands to the command registry.

- [x] 5.1.1.1 Update command pattern matching in `Commands.parse/1`:
  ```elixir
  def parse("/session " <> args), do: {:session, parse_session_args(args)}
  def parse("/session"), do: {:session, :help}
  ```
- [x] 5.1.1.2 Define session subcommands:
  - `new [path] [--name=name]` - Create new session
  - `list` - List all sessions
  - `switch <id|index>` - Switch to session
  - `close [id|index]` - Close session
  - `rename <name>` - Rename current session
- [x] 5.1.1.3 Implement `parse_session_args/1` for subcommand parsing
- [x] 5.1.1.4 Write unit tests for command parsing (17 tests)

### 5.1.2 Session Argument Parser
- [x] **Task 5.1.2** (completed 2025-12-06)

Implement argument parsing for session subcommands.

- [x] 5.1.2.1 Implement `parse_session_args/1` (done in 5.1.1)
- [x] 5.1.2.2 Implement `parse_new_args/1` handling path and --name flag (done in 5.1.1)
- [x] 5.1.2.3 Implement `parse_close_args/1` handling optional target (done in 5.1.1)
- [x] 5.1.2.4 Implement `resolve_session_path/1` for path resolution:
  - Handle `~` expansion to home directory
  - Handle `.` and `..` for relative paths
  - Handle relative paths resolved against CWD
- [x] 5.1.2.5 Implement `validate_session_path/1` for path validation
- [x] 5.1.2.6 Write unit tests for path resolution (14 tests)

**Unit Tests for Section 5.1:**
- Test `/session new /path/to/project` parses correctly
- Test `/session new /path --name=MyProject` parses name flag
- Test `/session list` parses to :list
- Test `/session switch 1` parses index
- Test `/session switch abc123` parses ID
- Test `/session close` parses with no target
- Test `/session close 2` parses with index
- Test `/session rename NewName` parses name
- Test `/session` shows help

---

## 5.2 Session New Command

Implement the `/session new` command for creating sessions.

### 5.2.1 New Session Handler
- [x] **Task 5.2.1** (completed 2025-12-06)

Implement the handler for creating new sessions.

- [x] 5.2.1.1 Implement `execute_session({:new, opts}, model)` with path resolution
- [x] 5.2.1.2 Validate path exists before creating session (uses validate_session_path)
- [x] 5.2.1.3 Handle session limit (10 max) - returns `:session_limit_reached` error
- [x] 5.2.1.4 Handle duplicate project path - returns `:project_already_open` error
- [x] 5.2.1.5 Return `{:session_action, {:add_session, session}}` for TUI
- [x] 5.2.1.6 Write unit tests for new command (11 tests)
- [x] 5.2.1.7 Implement `execute_session(:help, model)` for session help
- [x] 5.2.1.8 Add stub handlers for :list, :switch, :close, :rename

### 5.2.2 Path Resolution
- [x] **Task 5.2.2** (completed in Task 5.1.2)

Implement path resolution for session creation.

- [x] 5.2.2.1 Handle relative paths (resolve against CWD)
- [x] 5.2.2.2 Handle `~` expansion for home directory
- [x] 5.2.2.3 Handle `.` for current directory
- [x] 5.2.2.4 Handle `..` for parent directory
- [x] 5.2.2.5 Validate resolved path exists and is directory
- [x] 5.2.2.6 Write unit tests for path resolution (14 tests)

### 5.2.3 TUI Integration for New Session
- [x] **Task 5.2.3** (completed 2025-12-06)

Handle `{:session, subcommand}` and `{:session_action, {:add_session, session}}` in TUI.

- [x] 5.2.3.1 Add `{:session, subcommand}` handling in `do_handle_command/2`
- [x] 5.2.3.2 Add `handle_session_command/2` to execute session subcommands
- [x] 5.2.3.3 Add `Model.add_session/2` to add session to model
- [x] 5.2.3.4 Add `Model.switch_to_session/2` to switch active session
- [x] 5.2.3.5 Add `Model.session_count/1` helper function
- [x] 5.2.3.6 Subscribe to session's PubSub topic on creation
- [x] 5.2.3.7 Write unit tests for Model helpers (8 tests)

**Unit Tests for Section 5.2:**
- Test `/session new` creates session for CWD
- Test `/session new /path` creates session for path
- Test `/session new /path --name=Foo` uses custom name
- Test `/session new` fails at 10 sessions
- Test `/session new` fails for duplicate path
- Test `/session new` fails for non-existent path
- Test relative path resolution
- Test TUI adds session to tabs

---

## 5.3 Session List Command

Implement the `/session list` command.

### 5.3.1 List Handler
- [x] **Task 5.3.1** (completed 2025-12-06)

Implement the handler for listing sessions.

- [x] 5.3.1.1 Implement `execute_session(:list, model)`
- [x] 5.3.1.2 Implement `format_session_list/2` helper
- [x] 5.3.1.3 Implement `truncate_path/1` helper
- [x] 5.3.1.4 Show index number (1-10)
- [x] 5.3.1.5 Show asterisk for active session
- [x] 5.3.1.6 Show truncated project path with ~ for home
- [x] 5.3.1.7 Write unit tests for list command (8 tests)

### 5.3.2 Empty List Handling
- [x] **Task 5.3.2** (completed 2025-12-06)

Handle empty session list.

- [x] 5.3.2.1 Return helpful message when no sessions
- [x] 5.3.2.2 Update unit test for empty list

**Unit Tests for Section 5.3:**
- Test `/session list` shows all sessions
- Test list includes index numbers
- Test active session marked with asterisk
- Test paths truncated appropriately
- Test empty list shows help message

---

## 5.4 Session Switch Command

Implement the `/session switch` command.

### 5.4.1 Switch by Index
- [x] **Task 5.4.1** (completed 2025-12-06)

Implement switching by tab index.

- [x] 5.4.1.1 Implement `execute_session({:switch, target}, model)`
- [x] 5.4.1.2 Implement `resolve_session_target/2` with helpers
- [x] 5.4.1.3 Support index 1-10 (0 means 10)
- [x] 5.4.1.4 Support switch by session ID
- [x] 5.4.1.5 Support switch by session name
- [x] 5.4.1.6 Write unit tests for switch command (8 tests)

### 5.4.2 Switch by ID or Name
- [x] **Task 5.4.2** (completed 2025-12-06)

Implement switching by session ID or name.

- [x] 5.4.2.1 Implement `find_session_by_name/2` with case-insensitive matching
- [x] 5.4.2.2 Support partial name matching (prefix)
- [x] 5.4.2.3 Handle ambiguous names (multiple matches) with helpful error
- [x] 5.4.2.4 Add `find_session_by_prefix/2` helper
- [x] 5.4.2.5 Write unit tests for name/prefix matching (5 tests)

### 5.4.3 TUI Integration for Switch
- [x] **Task 5.4.3** (completed 2025-12-06)

Handle `{:switch_session, id}` action in TUI.

- [x] 5.4.3.1 Add `{:session_action, {:switch_session, session_id}}` handler
- [x] 5.4.3.2 Call `Model.switch_to_session/2` to update active session
- [x] 5.4.3.3 Show success message with session name
- [x] 5.4.3.4 Model.switch_to_session/2 already tested in model_test.exs

**Unit Tests for Section 5.4:**
- Test `/session switch 1` switches to first session
- Test `/session switch 0` switches to 10th session
- Test `/session switch abc123` switches by ID
- Test `/session switch MyProject` switches by name
- Test `/session switch` with invalid target shows error
- Test partial name matching works
- Test ambiguous name shows error

### 5.4.4 Review Fixes and Improvements
- [x] **Task 5.4.4** (completed 2025-12-06)

Address code review findings for Section 5.4.

- [x] 5.4.4.1 Extract `add_session_message/2` helper to reduce TUI duplication (~70 lines → ~20 lines)
- [x] 5.4.4.2 Add missing boundary tests (negative index, empty string, large index)
- [x] 5.4.4.3 Rename `Model.switch_to_session/2` to `Model.switch_session/2` for consistency
- [x] 5.4.4.4 Simplify error pattern in `parse_session_args` (return message directly)
- [x] 5.4.4.5 Use `match?/2` in `is_numeric_target?/1`
- [x] 5.4.4.6 Extract `@ctrl_0_maps_to_index` module attribute
- [x] 5.4.4.7 Add helpful suggestions to error messages

---

## 5.5 Session Close Command

Implement the `/session close` command.

### 5.5.1 Close Handler
- [x] **Task 5.5.1** (completed 2025-12-06)

Implement the handler for closing sessions.

- [x] 5.5.1.1 Implement `execute_session({:close, target}, model)`
- [x] 5.5.1.2 Default to active session if no target
- [x] 5.5.1.3 Add `Model.remove_session/2` helper with active session switching
- [x] 5.5.1.4 Add TUI handler for `{:close_session, id, name}` action
- [x] 5.5.1.5 Write unit tests for close command (7 tests)
- [x] 5.5.1.6 Write unit tests for Model.remove_session/2 (6 tests)

### 5.5.2 Close Cleanup
- [x] **Task 5.5.2** (completed 2025-12-06 - already implemented in 5.5.1)

Proper cleanup when closing session - all cleanup was already implemented in Task 5.5.1.

- [x] 5.5.2.1 Stop session processes via SessionSupervisor (done in 5.5.1 TUI handler)
- [x] 5.5.2.2 Unregister from SessionRegistry (done by SessionSupervisor.stop_session/1)
- [x] 5.5.2.3 Unsubscribe from PubSub topic (done in 5.5.1 TUI handler)
- [ ] 5.5.2.4 Save session state for /resume (deferred to Phase 6)
- [x] 5.5.2.5 Write unit tests for cleanup (covered by 5.5.1 tests)

### 5.5.3 TUI Integration for Close
- [x] **Task 5.5.3** (completed 2025-12-06)

Add keyboard shortcut (Ctrl+W) for closing sessions.

- [x] 5.5.3.1 Add Ctrl+W event handler in `event_to_msg/2`
- [x] 5.5.3.2 Add `update(:close_active_session, state)` handler
- [x] 5.5.3.3 Handle no active session case with error message
- [x] 5.5.3.4 Reuse existing close logic (stop process, unsubscribe, remove_session)

Note: Session removal and adjacent session logic was already implemented in Task 5.5.1 via `Model.remove_session/2`.

### 5.5.4 Review Fixes and Improvements
- [x] **Task 5.5.4** (completed 2025-12-06)

Address code review findings for Section 5.5.

- [x] 5.5.4.1 Extract `do_close_session/3` helper to eliminate duplication between Ctrl+W handler and command handler
- [x] 5.5.4.2 Fix PubSub unsubscribe order (unsubscribe BEFORE stop_session to avoid race conditions)
- [x] 5.5.4.3 Add missing close command tests (ambiguous prefix, case-insensitive, prefix matching)
- [x] 5.5.4.4 Add Ctrl+W event handler tests

**Unit Tests for Section 5.5:**
- Test `/session close` closes active session
- Test `/session close 2` closes by index
- Test `/session close abc123` closes by ID
- Test close stops session processes
- Test close unregisters from registry
- Test TUI switches to adjacent session
- Test closing last session shows welcome

---

## 5.6 Session Rename Command

Implement the `/session rename` command.

### 5.6.1 Rename Handler
- [x] **Task 5.6.1** (completed 2025-12-06)

Implement the handler for renaming sessions.

- [x] 5.6.1.1 Implement `execute_session({:rename, name}, model)` with validation
- [x] 5.6.1.2 Validate new name (non-empty after trim, max 50 chars)
- [x] 5.6.1.3 Add Model.rename_session/3 helper to update session in model
- [x] 5.6.1.4 Add TUI handler for `{:rename_session, session_id, new_name}` action
- [x] 5.6.1.5 Write unit tests for rename command (6 tests)
- [x] 5.6.1.6 Write unit tests for Model.rename_session/3 (4 tests)

Note: Simplified design - sessions are local to TUI model, no SessionRegistry update needed. Returns `{:session_action, {:rename_session, session_id, new_name}}` for TUI handling.

### 5.6.2 TUI Integration for Rename
- [x] **Task 5.6.2** (completed in Task 5.6.1)

Handle `{:rename_session, session_id, new_name}` action in TUI - implemented in Task 5.6.1.

- [x] 5.6.2.1 Add handler in `handle_session_command/2` for rename action
- [x] 5.6.2.2 Call Model.rename_session/3 to update session name
- [x] 5.6.2.3 Tab label updates automatically on next render (uses session.name)

**Unit Tests for Section 5.6:**
- Test `/session rename NewName` renames active session
- Test rename fails for no active session
- Test rename fails for empty name
- Test rename fails for whitespace-only name
- Test rename fails for too-long name
- Test rename accepts name at max length
- Test Model.rename_session updates name
- Test Model.rename_session preserves other properties
- Test Model.rename_session handles non-existent session
- Test Model.rename_session preserves other sessions

---

## 5.7 Help and Error Handling

Implement help output and error handling for session commands.

### 5.7.1 Session Help
- [x] **Task 5.7.1** (completed 2025-12-06 - already implemented in Task 5.2.1)

Implement help output for session commands.

- [x] 5.7.1.1 Implement `execute_session(:help, _model)` - already exists
- [x] 5.7.1.2 Help includes all session commands with descriptions
- [x] 5.7.1.3 Help includes keyboard shortcuts section
- [x] 5.7.1.4 Unit tests exist for help output (3 tests)

Note: This functionality was implemented as part of Task 5.2.1 when the session command structure was created. The help handler returns `{:ok, help_text}` with properly formatted output.

### 5.7.2 Error Messages
- [x] **Task 5.7.2** (completed 2025-12-06 - already implemented inline)

Define clear error messages for all failure cases.

- [x] 5.7.2.1 Error messages defined inline for all session commands
- [x] 5.7.2.2 Consistent formatting: descriptive, actionable, contextual
- [x] 5.7.2.3 Unit tests exist for all error cases

Note: Error messages were implemented inline throughout the session command handlers. All messages follow consistent patterns: clear description, helpful suggestion, contextual info. See `notes/features/ws-5.7.2-error-messages.md` for full audit.

**Unit Tests for Section 5.7:**
- Test `/session` shows help
- Test `/session foo` (unknown subcommand) shows help
- Test error messages are clear and helpful
- Test all error cases have proper messages

---

## 5.8 Phase 5 Integration Tests

Comprehensive integration tests verifying all Phase 5 command components work together correctly.

### 5.8.1 Session New Command Integration
- [x] **Task 5.8.1** (completed 2025-12-06)

Test `/session new` command end-to-end.

- [x] 5.8.1.1 Create `test/jido_code/integration/session_phase5_test.exs`
- [x] 5.8.1.2 Test: `/session new /path` → session created → tab added → switched to new session
- [x] 5.8.1.3 Test: `/session new` (no path) → uses CWD → session created
- [x] 5.8.1.4 Test: `/session new --name=Foo` → custom name in tab and registry
- [x] 5.8.1.5 Test: `/session new` at limit (10) → error message → no session created
- [x] 5.8.1.6 Test: `/session new` duplicate path → error message → no session created
- [x] 5.8.1.7 Write all new command integration tests

Note: Integration tests cover all session commands (new, list, switch, close, rename) and TUI flow. The test file includes 25 comprehensive tests with proper setup isolation via Settings cache management.

### 5.8.2 Session List Command Integration
- [x] **Task 5.8.2** (completed 2025-12-06)

Test `/session list` command end-to-end.

- [x] 5.8.2.1 Test: Create 3 sessions → `/session list` → shows all 3 with indices
- [x] 5.8.2.2 Test: Active session marked with asterisk in list
- [x] 5.8.2.3 Test: Empty session list → helpful message shown
- [x] 5.8.2.4 Test: List shows truncated paths correctly
- [x] 5.8.2.5 Write all list command integration tests

Note: Implemented in Task 5.8.1 integration test file.

### 5.8.3 Session Switch Command Integration
- [x] **Task 5.8.3** (completed 2025-12-06)

Test `/session switch` command end-to-end.

- [x] 5.8.3.1 Test: `/session switch 2` → active session changes → view updates
- [x] 5.8.3.2 Test: `/session switch MyProject` → switches by name
- [x] 5.8.3.3 Test: `/session switch abc123` → switches by ID
- [x] 5.8.3.4 Test: `/session switch 99` (invalid) → error message → no change
- [x] 5.8.3.5 Test: Partial name match → switches to matching session
- [x] 5.8.3.6 Write all switch command integration tests

Note: Implemented in Task 5.8.1 integration test file.

### 5.8.4 Session Close Command Integration
- [x] **Task 5.8.4** (completed 2025-12-06)

Test `/session close` command end-to-end.

- [x] 5.8.4.1 Test: `/session close` → active session stopped → removed from tabs → switch to adjacent
- [x] 5.8.4.2 Test: `/session close 2` → specific session closed
- [x] 5.8.4.3 Test: Close last session → welcome screen appears
- [x] 5.8.4.4 Test: Close → processes terminated → registry updated → PubSub unsubscribed
- [x] 5.8.4.5 Write all close command integration tests

Note: Implemented in Task 5.8.1 integration test file.

### 5.8.5 Session Rename Command Integration
- [x] **Task 5.8.5** (completed 2025-12-06)

Test `/session rename` command end-to-end.

- [x] 5.8.5.1 Test: `/session rename NewName` → tab label updates → registry updates
- [x] 5.8.5.2 Test: `/session rename` with invalid name → error message → no change
- [x] 5.8.5.3 Test: Rename → `/session list` shows new name
- [x] 5.8.5.4 Write all rename command integration tests

Note: Implemented in Task 5.8.1 integration test file.

### 5.8.6 Command-TUI Flow Integration
- [x] **Task 5.8.6** (completed 2025-12-06)

Test command execution integrates properly with TUI state.

- [x] 5.8.6.1 Test: Command result {:add_session, session} → TUI model updated correctly
- [x] 5.8.6.2 Test: Command result {:switch_session, id} → TUI switches active session
- [x] 5.8.6.3 Test: Command result {:remove_session, id} → TUI removes from tabs
- [x] 5.8.6.4 Test: Command result {:update_session, session} → TUI updates session data
- [x] 5.8.6.5 Test: Command error → displayed in TUI feedback area
- [x] 5.8.6.6 Write all TUI flow integration tests

Note: Implemented in Task 5.8.1 integration test file. The "TUI command flow" describe block covers these scenarios.

**Integration Tests for Section 5.8:**
- All session commands work end-to-end
- Commands properly update TUI state
- Error cases handled with clear feedback
- Command results flow correctly to TUI

---

## Success Criteria

1. **New Command**: `/session new` creates sessions with path/name options
2. **List Command**: `/session list` shows all sessions with indices
3. **Switch Command**: `/session switch` works with index, ID, and name
4. **Close Command**: `/session close` stops and cleans up session
5. **Rename Command**: `/session rename` updates session name
6. **Help Output**: `/session` shows comprehensive help
7. **Path Resolution**: Relative paths, ~, ., .. all work
8. **Error Handling**: Clear messages for all error cases
9. **TUI Integration**: Commands update TUI model correctly
10. **Test Coverage**: Minimum 80% coverage for phase 5 code
11. **Integration Tests**: All Phase 5 components work together correctly (Section 5.8)

---

## Critical Files

**New Files:**
- `lib/jido_code/commands/session.ex` - Session command implementation (optional, or inline)
- `test/jido_code/commands/session_test.exs` - Session command tests
- `test/jido_code/integration/session_phase5_test.exs`

**Modified Files:**
- `lib/jido_code/commands.ex` - Add session command handlers
- `lib/jido_code/tui.ex` - Handle command result actions

---

## 5.9 Phase 5 Review Fixes

Address blockers, concerns, and improvements from the Phase 5 code review.

### 5.9.1 Security and Validation
- [x] **Task 5.9.1** (completed 2025-12-06)

- [x] 5.9.1.1 Add session path security restrictions (S1) - forbid system directories
- [x] 5.9.1.2 Add session name character validation (S2) - Unicode-aware whitelist
- [x] 5.9.1.3 Add tests for security improvements (14 tests)

### 5.9.2 Test Coverage
- [x] **Task 5.9.2** (completed 2025-12-06)

- [x] 5.9.2.1 Add keyboard shortcut tests for Ctrl+1-9,0 (B3) - 10 tests
- [x] 5.9.2.2 Add TUI model helper tests (B1) - 7 tests

### 5.9.3 Code Quality
- [x] **Task 5.9.3** (completed 2025-12-06)

- [x] 5.9.3.1 Extract shared ProviderKeys module (R1) - eliminate duplication
- [x] 5.9.3.2 Standardize error returns (CN1) - use strings consistently
- [x] 5.9.3.3 Remove redundant @doc false (CN3)
- [x] 5.9.3.4 Extract format_resolution_error helper (R2)
- [x] 5.9.3.5 Refactor truncate_path for pipe friendliness (E1)

Note: CN2 (make execute_session private) was skipped - function is public API used by TUI.

**Files Changed:**
- `lib/jido_code/config/provider_keys.ex` (new)
- `lib/jido_code/commands.ex`
- `lib/jido_code/tui.ex`
- `test/jido_code/commands_test.exs`
- `test/jido_code/tui/model_test.exs`

See `notes/features/ws-5.9-review-fixes.md` and `notes/summaries/ws-5.9-review-fixes.md` for details.

---

## Dependencies

- **Depends on Phase 1**: SessionSupervisor, SessionRegistry, Session struct
- **Depends on Phase 4**: TUI model structure with sessions
- **Phase 6 depends on this**: /resume command builds on close cleanup
