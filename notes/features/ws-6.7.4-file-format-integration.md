# Feature Plan: Persistence File Format Integration Tests (Task 6.7.4)

**Task:** 6.7.4 - Persistence File Format Integration Tests
**Phase:** Phase 6 - Session Persistence
**Date:** 2025-12-10
**Status:** Planning Complete, Ready for Implementation

---

## Problem Statement

### What Problem Are We Solving?

The persistence layer serializes session data to JSON files and deserializes them on resume. However, we need **end-to-end integration tests** that verify:

1. **Complete File Format**: All required fields present in saved JSON
2. **Message Serialization**: Conversation messages round-trip correctly (role as string, timestamps as ISO 8601)
3. **Todo Serialization**: Todos round-trip with status/active_form preserved
4. **Timestamp Format**: All timestamps use ISO 8601 format
5. **Error Handling**: Corrupted JSON files handled gracefully (skip, log warning)
6. **Data Integrity**: No data loss through save-resume cycles

**Current Test Coverage:**
- ✅ Unit tests for validation (persistence_test.exs lines 20-235)
- ✅ Unit tests for serialization (persistence_test.exs lines 616-710)
- ✅ Unit tests for corrupted JSON (persistence_test.exs line 865)
- ✅ Integration tests for save-resume cycles (session_phase6_test.exs)
- ❌ **Missing**: Explicit integration tests verifying actual JSON file contents
- ❌ **Missing**: Round-trip verification at file format level
- ❌ **Missing**: Tests reading actual JSON from disk and verifying structure

**Impact:**
- Without these tests, file format regressions could go unnoticed
- Changes to serialization logic might break backward compatibility
- Data integrity issues might not be caught until production
- No guarantee that JSON on disk matches expected schema

---

## Solution Overview

### High-Level Approach

Add comprehensive integration tests to the existing `test/jido_code/integration/session_phase6_test.exs` file that verify the persistence file format works correctly. These tests will:

1. **Create Real Sessions** - Use SessionSupervisor to create actual sessions
2. **Add Test Data** - Populate with messages, todos, varied data
3. **Close Sessions** - Trigger auto-save to create JSON files
4. **Read JSON Directly** - Parse files from disk, verify structure
5. **Verify Round-Trip** - Resume sessions, ensure data intact
6. **Test Error Cases** - Corrupted JSON, missing fields, etc.

### Key Design Decisions

**Decision 1: Add to Existing session_phase6_test.exs**
- **Choice:** Add new describe block to session_phase6_test.exs
- **Rationale:**
  - File already has Phase 6 integration test infrastructure
  - Reuses existing helpers (create_test_session, add_messages, add_todos)
  - Keeps all Phase 6 integration tests in one place
  - No need to duplicate setup/teardown logic
- **Location:** After existing tests, before final `end`

**Decision 2: Test at File Format Level**
- **Choice:** Read actual JSON files from disk, parse, verify structure
- **Rationale:**
  - Integration tests should verify actual on-disk format
  - Unit tests cover serialization functions
  - Need to verify JSON schema matches expectations
  - Catches issues with File.write!/JSON encoding
- **Approach:** Use `File.read!` + `Jason.decode!` to inspect actual files

**Decision 3: Test Data Integrity Through Round-Trip**
- **Choice:** Create → Close → Read JSON → Resume → Verify
- **Rationale:**
  - Ensures no data loss in full cycle
  - Verifies deserialization matches serialization
  - Tests real-world usage pattern
  - Catches subtle conversion bugs

**Decision 4: Test Error Handling Explicitly**
- **Choice:** Create corrupted JSON, verify graceful handling
- **Rationale:**
  - Production environments can have corrupted files
  - Need to ensure system doesn't crash
  - Should log warnings and skip bad files
  - Already partially tested (line 865) but need integration view

---

## Technical Details

### Persistence File Format (JSON Schema)

**Session File Structure** (from serialize_session/1):
```json
{
  "version": 1,
  "id": "uuid-v4-string",
  "name": "Session Name",
  "project_path": "/absolute/path/to/project",
  "config": {
    "provider": "anthropic",
    "model": "claude-3-5-haiku-20241022",
    "temperature": 0.7,
    "max_tokens": 4096
  },
  "closed_at": "2025-12-10T15:30:00.123456Z",
  "conversation": [
    {
      "id": "msg-uuid",
      "role": "user",
      "content": "Message content",
      "timestamp": "2025-12-10T15:30:00.123456Z"
    }
  ],
  "todos": [
    {
      "content": "Task description",
      "status": "in_progress",
      "active_form": "Working on task"
    }
  ]
}
```

**Key Serialization Rules** (from persistence.ex):

1. **Messages** (lines 965-972):
   - `role`: Atom → String (`to_string(msg.role)`)
   - `timestamp`: DateTime → ISO 8601 string
   - `id`, `content`: Pass through

2. **Todos** (lines 975-982):
   - `status`: Atom → String (`to_string(todo.status)`)
   - `active_form`: Falls back to `content` if not present
   - All string keys (snake_case)

3. **Config** (lines 985-999):
   - Atoms → Strings (keys and values)
   - Nested maps serialized recursively
   - All string keys

4. **Timestamps** (lines 1002-1004):
   - All use `DateTime.to_iso8601/1`
   - `nil` → current time
   - Format: ISO 8601 with microseconds

### Deserialization Rules (from persistence.ex)

1. **Messages** (lines 1098-1110):
   - `role`: String → Atom (`String.to_existing_atom/1`)
   - `timestamp`: ISO string → DateTime
   - Validates required fields

2. **Todos** (lines 1118-1128):
   - `status`: String → Atom
   - `active_form`: String (snake_case)
   - Required fields: content, status

3. **Config** (lines 1156-1164):
   - Converts string keys → atom keys
   - Nested maps handled recursively

### File Locations

**Session Files:**
- Directory: `~/.jido_code/sessions/`
- Pattern: `{session_id}.json`
- Created by: `write_session_file/2` (line 947)

**Test Infrastructure:**
- Integration tests: `test/jido_code/integration/session_phase6_test.exs`
- Helpers available: `create_test_session/2`, `add_messages/2`, `add_todos/2`, `wait_for_file/2`

---

## Implementation Plan

### Step 1: Add File Format Verification Tests

**Test Goal:** Verify complete JSON structure after save

**Implementation:**
```elixir
describe "persistence file format integration" do
  test "saved JSON includes all required fields", %{tmp_base: tmp_base} do
    # Create session with full data
    session = create_test_session(tmp_base, "Format Test")

    add_messages(session.id, [
      %{role: :user, content: "Test message", timestamp: DateTime.utc_now()}
    ])

    add_todos(session.id, [
      %{content: "Test task", status: :in_progress, active_form: "Testing"}
    ])

    # Close and wait for file
    :ok = SessionSupervisor.stop_session(session.id)
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    wait_for_file(session_file)

    # Read and parse JSON
    json_content = File.read!(session_file)
    data = Jason.decode!(json_content)

    # Verify required fields present
    assert data["version"] == 1
    assert data["id"] == session.id
    assert data["name"] == "Format Test"
    assert data["project_path"] == session.project_path
    assert is_map(data["config"])
    assert is_binary(data["closed_at"])
    assert is_list(data["conversation"])
    assert is_list(data["todos"])
  end
end
```

**Assertions:**
- All top-level fields present
- Types correct (string, map, list)
- No missing keys

---

### Step 2: Test Message Serialization Format

**Test Goal:** Verify messages serialized correctly to JSON

**Implementation:**
```elixir
test "conversation messages serialized correctly", %{tmp_base: tmp_base} do
  session = create_test_session(tmp_base, "Messages Test")

  # Add messages with different roles
  timestamp = DateTime.utc_now()
  add_messages(session.id, [
    %{role: :user, content: "User message", timestamp: timestamp},
    %{role: :assistant, content: "Assistant reply", timestamp: timestamp},
    %{role: :system, content: "System message", timestamp: timestamp}
  ])

  # Close and read JSON
  :ok = SessionSupervisor.stop_session(session.id)
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  wait_for_file(session_file)

  data = File.read!(session_file) |> Jason.decode!()
  messages = data["conversation"]

  # Verify message structure
  assert length(messages) == 3

  [user_msg, assistant_msg, system_msg] = messages

  # Verify user message
  assert user_msg["role"] == "user"  # String, not atom
  assert user_msg["content"] == "User message"
  assert is_binary(user_msg["id"])
  assert is_binary(user_msg["timestamp"])

  # Verify assistant message
  assert assistant_msg["role"] == "assistant"
  assert assistant_msg["content"] == "Assistant reply"

  # Verify system message
  assert system_msg["role"] == "system"
  assert system_msg["content"] == "System message"
end
```

**Assertions:**
- Role as string (not atom)
- All message fields present
- Content preserved
- IDs unique

---

### Step 3: Test Todo Serialization Format

**Test Goal:** Verify todos serialized with status and active_form

**Implementation:**
```elixir
test "todos serialized correctly", %{tmp_base: tmp_base} do
  session = create_test_session(tmp_base, "Todos Test")

  # Add todos with different statuses
  add_todos(session.id, [
    %{content: "Task 1", status: :pending, active_form: "Waiting for task 1"},
    %{content: "Task 2", status: :in_progress, active_form: "Working on task 2"},
    %{content: "Task 3", status: :completed, active_form: "Task 3 done"}
  ])

  # Close and read JSON
  :ok = SessionSupervisor.stop_session(session.id)
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  wait_for_file(session_file)

  data = File.read!(session_file) |> Jason.decode!()
  todos = data["todos"]

  # Verify todo structure
  assert length(todos) == 3

  [todo1, todo2, todo3] = todos

  # Verify pending todo
  assert todo1["content"] == "Task 1"
  assert todo1["status"] == "pending"  # String, not atom
  assert todo1["active_form"] == "Waiting for task 1"

  # Verify in_progress todo
  assert todo2["content"] == "Task 2"
  assert todo2["status"] == "in_progress"
  assert todo2["active_form"] == "Working on task 2"

  # Verify completed todo
  assert todo3["content"] == "Task 3"
  assert todo3["status"] == "completed"
  assert todo3["active_form"] == "Task 3 done"
end
```

**Assertions:**
- Status as string (not atom)
- active_form present (snake_case)
- Content preserved

---

### Step 4: Test Timestamp Format

**Test Goal:** Verify all timestamps use ISO 8601 format

**Implementation:**
```elixir
test "timestamps in ISO 8601 format", %{tmp_base: tmp_base} do
  session = create_test_session(tmp_base, "Timestamps Test")

  # Add message with known timestamp
  now = DateTime.utc_now()
  add_messages(session.id, [
    %{role: :user, content: "Time test", timestamp: now}
  ])

  # Close and read JSON
  :ok = SessionSupervisor.stop_session(session.id)
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  wait_for_file(session_file)

  data = File.read!(session_file) |> Jason.decode!()

  # Verify closed_at is ISO 8601
  closed_at = data["closed_at"]
  assert {:ok, _datetime, _offset} = DateTime.from_iso8601(closed_at)

  # Verify message timestamp is ISO 8601
  message_timestamp = hd(data["conversation"])["timestamp"]
  assert {:ok, parsed_time, _offset} = DateTime.from_iso8601(message_timestamp)

  # Should be close to original timestamp (within 1 second)
  diff = DateTime.diff(parsed_time, now, :second)
  assert abs(diff) <= 1
end
```

**Assertions:**
- Timestamps parseable as ISO 8601
- Timestamps accurate (no data loss)
- Format includes microseconds

---

### Step 5: Test Round-Trip Data Integrity

**Test Goal:** Verify data preserved through save-resume cycle

**Implementation:**
```elixir
test "round-trip preserves all data", %{tmp_base: tmp_base} do
  session = create_test_session(tmp_base, "Round-Trip Test")

  # Add complex data
  timestamp = DateTime.utc_now()
  add_messages(session.id, [
    %{role: :user, content: "Message 1", timestamp: timestamp},
    %{role: :assistant, content: "Reply 1", timestamp: timestamp}
  ])

  add_todos(session.id, [
    %{content: "Task 1", status: :pending, active_form: "Pending task"},
    %{content: "Task 2", status: :completed, active_form: "Done task"}
  ])

  # Close (save)
  :ok = SessionSupervisor.stop_session(session.id)
  session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
  wait_for_file(session_file)

  # Resume (load)
  {:ok, resumed_session} = Persistence.resume(session.id)

  # Verify session metadata
  assert resumed_session.id == session.id
  assert resumed_session.name == "Round-Trip Test"
  assert resumed_session.project_path == session.project_path

  # Get state from resumed session
  messages = Session.State.get_messages(resumed_session.id)
  todos = Session.State.get_todos(resumed_session.id)

  # Verify messages preserved
  assert length(messages) == 2
  assert hd(messages).role == :user  # Atom, not string
  assert hd(messages).content == "Message 1"

  # Verify todos preserved
  assert length(todos) == 2
  assert hd(todos).status == :pending  # Atom, not string
  assert hd(todos).content == "Task 1"
  assert hd(todos).active_form == "Pending task"
end
```

**Assertions:**
- All data survives round-trip
- Types converted back correctly (strings → atoms)
- No data loss or corruption

---

### Step 6: Test Corrupted JSON Handling

**Test Goal:** Verify graceful handling of corrupted files

**Implementation:**
```elixir
test "handles corrupted JSON files gracefully", %{tmp_base: tmp_base} do
  import ExUnit.CaptureLog

  # Create sessions directory
  sessions_dir = Persistence.sessions_dir()
  File.mkdir_p!(sessions_dir)

  # Create a good session file
  good_id = Uniq.UUID.uuid4()
  good_session = %{
    version: 1,
    id: good_id,
    name: "Good Session",
    project_path: Path.join(tmp_base, "good"),
    config: %{provider: "anthropic", model: "claude-3-5-haiku-20241022"},
    closed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
    conversation: [],
    todos: []
  }
  good_path = Path.join(sessions_dir, "#{good_id}.json")
  File.write!(good_path, Jason.encode!(good_session))

  # Create a corrupted JSON file
  corrupted_id = Uniq.UUID.uuid4()
  corrupted_path = Path.join(sessions_dir, "#{corrupted_id}.json")
  File.write!(corrupted_path, "{invalid json content")

  # List persisted should skip corrupted file and include good one
  log = capture_log(fn ->
    sessions = Persistence.list_persisted()

    # Should have only the good session
    assert length(sessions) == 1
    assert hd(sessions).id == good_id
    assert hd(sessions).name == "Good Session"
  end)

  # Should log warning about corrupted file
  assert log =~ "corrupted" or log =~ "invalid" or log =~ "failed"
end
```

**Assertions:**
- Corrupted files skipped
- Good files still loaded
- Warning logged
- System doesn't crash

---

## Success Criteria

### Tests Implemented ✅

- [ ] Test 1: Saved JSON includes all required fields (version, id, name, config, etc.)
- [ ] Test 2: Conversation messages serialized correctly (role as string, timestamps)
- [ ] Test 3: Todos serialized correctly (status as string, active_form present)
- [ ] Test 4: Timestamps in ISO 8601 format (parseable, accurate)
- [ ] Test 5: Round-trip preserves all data (save → resume → verify)
- [ ] Test 6: Corrupted JSON handled gracefully (skip, log warning)

**Total:** 6 comprehensive file format integration tests

### Test Results ✅

- [ ] All new tests passing (6/6)
- [ ] All existing tests still passing (23 phase6 + 145 commands)
- [ ] No compilation warnings
- [ ] Execution time reasonable (< 10 seconds for new tests)

### Documentation ✅

- [ ] Feature plan written (this document)
- [ ] Implementation summary written
- [ ] Phase plan updated (Task 6.7.4 marked complete)
- [ ] Test descriptions clear and comprehensive

### Code Quality ✅

- [ ] Tests follow existing patterns from session_phase6_test.exs
- [ ] Reuse existing helpers (create_test_session, add_messages, etc.)
- [ ] Clear, descriptive test names
- [ ] Proper setup/teardown for clean test environment

---

## Testing Approach

### Test Categories

**1. Structure Tests (2 tests):**
- Required fields present (Test 1)
- Correct data types (Test 1)

**2. Serialization Tests (2 tests):**
- Messages format (Test 2)
- Todos format (Test 3)

**3. Format Tests (1 test):**
- ISO 8601 timestamps (Test 4)

**4. Integration Tests (1 test):**
- Round-trip data integrity (Test 5)

**5. Error Handling Tests (1 test):**
- Corrupted JSON (Test 6)

### Assertion Strategy

**File Reading:**
- Use `File.read!` to get raw JSON
- Use `Jason.decode!` to parse
- Verify actual on-disk format

**Data Verification:**
- Check field presence with `data["key"]`
- Verify types with `is_binary`, `is_map`, `is_list`
- Check values with `assert data["key"] == expected`

**Round-Trip:**
- Create → Close → Resume → Get State
- Compare original data with retrieved data
- Verify type conversions (string ↔ atom)

**Error Cases:**
- Use `ExUnit.CaptureLog` for log verification
- Create malformed files manually
- Verify system continues working

---

## Notes and Considerations

### Scope Clarification

**What is Tested:**
- Actual JSON file structure on disk
- Serialization format (strings, not atoms)
- Timestamp format (ISO 8601)
- Round-trip data integrity
- Error handling for corrupted files

**What is NOT Tested (Already Covered):**
- Validation logic (persistence_test.exs)
- Serialization functions (persistence_test.exs)
- Save-resume cycles (session_phase6_test.exs - Test 1)
- Auto-save behavior (session_phase6_test.exs - Tests 10-15)

**Rationale:** Task 6.7.4 focuses on FILE FORMAT, not functionality. We're verifying the JSON schema and structure.

### Dependencies

**Requires (Already Complete):**
- Task 6.4: Persistence save/resume implemented
- Task 6.7.1: Basic integration test infrastructure
- Task 6.7.2: Auto-save integration tests

**Provides:**
- Comprehensive file format verification
- Documentation of expected JSON schema
- Safety net for format changes

### Reusable Helpers

**From session_phase6_test.exs:**
- `create_test_session/2` - Creates session with temp project
- `add_messages/2` - Adds messages to session
- `add_todos/2` - Adds todos to session
- `wait_for_file/2` - Polls for file creation

**No new helpers needed** - existing infrastructure sufficient

---

## Implementation Status

**Phase:** Planning Complete ✅
**Next Step:** Implement Test 1 (required fields)
**Current Branch:** feature/ws-6.7.4-file-format-integration

---

**End of Feature Plan**
