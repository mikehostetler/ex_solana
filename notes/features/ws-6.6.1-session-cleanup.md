# Feature Planning: Session Cleanup (Task 6.6.1)

**Status:** Planning
**Task ID:** 6.6.1
**Phase:** 6 - Work Session Management
**Dependencies:**
- Task 6.3.1 (list_persisted/0) - COMPLETE
- Task 6.4.2 (delete_persisted/1) - COMPLETE

## 1. Problem Statement

### Why Session Cleanup is Needed

As users work with JidoCode over time, persisted session files accumulate in `~/.jido_code/sessions/`. Without cleanup:

1. **Disk Space Bloat**: Each session file contains conversation history, todos, and metadata. Over months/years, hundreds of old sessions could consume significant disk space (10MB max per file × 100s of sessions = GBs).

2. **Privacy Concerns**: Old session files may contain sensitive information (API keys mentioned in conversation, internal project details, etc.) that users want removed after a reasonable period.

3. **Performance Degradation**: The `list_persisted()` function reads and parses metadata from ALL JSON files. With hundreds of files, this operation slows down.

4. **Clutter**: Users resuming sessions see a long list of very old sessions they'll never use again, making it harder to find recent work.

### Current State

The persistence infrastructure provides:
- `list_persisted/0` - Returns ALL persisted sessions with metadata
- `delete_persisted/1` - Deletes a single session file (private function)
- No automated or manual cleanup mechanism

### Desired State

Add a `cleanup/1` function that:
- Accepts a max age in days (default 30)
- Automatically identifies and deletes sessions older than the cutoff
- Returns useful information about what was cleaned up
- Handles errors gracefully without failing on individual file issues

## 2. Solution Overview

### High-Level Approach

Implement a new **public** function `cleanup/1` in `JidoCode.Session.Persistence` that:

1. Calculates cutoff DateTime (now - max_age_days)
2. Gets list of all persisted sessions via `list_persisted/0`
3. Filters sessions where `closed_at` is older than cutoff
4. Deletes each old session using the existing private `delete_persisted/1`
5. Returns a result tuple with count and details

### Key Design Decisions

#### Decision 1: Use `list_persisted()` or `list_resumable()`?

**Choice:** Use `list_persisted()` (ALL sessions)

**Reasoning:**
- `list_resumable()` filters out sessions matching active session IDs/paths
- We want to clean up ALL old sessions, not just ones that aren't currently active
- Active sessions won't have old `closed_at` timestamps anyway (they're active!)
- Using `list_persisted()` is simpler and more correct

#### Decision 2: Return Value Design

**Choice:** Return `{:ok, result_map}` with detailed information

**Reasoning:**
```elixir
{:ok, %{
  deleted: 5,                    # Count of successfully deleted
  failed: 1,                     # Count that failed to delete
  skipped: 2,                    # Count with invalid timestamps
  deleted_ids: ["sess-1", ...],  # IDs of deleted sessions
  errors: [{"sess-x", reason}]   # Failed deletions with reasons
}}
```

This provides:
- Success count for user feedback ("Cleaned up 5 old sessions")
- Error transparency (don't hide failures)
- Detailed results for logging/debugging
- Idempotent behavior (multiple runs safe)

#### Decision 3: Error Handling Strategy

**Choice:** Continue-on-error with detailed error collection

**Reasoning:**
- If session #3 fails to delete, still try to delete #4, #5, etc.
- Collect all errors in result map
- Log warnings for failures but don't crash
- Partial success is better than total failure

#### Decision 4: Public vs Private Function

**Choice:** Make `cleanup/1` **public** (not private)

**Reasoning:**
- Will be called from TUI command handler (`/resume cleanup`)
- May be useful in IEx for manual cleanup
- Could be called from a future scheduled cleanup task
- The existing `delete_persisted/1` stays private (implementation detail)

## 3. Technical Details

### Module Location

**File:** `lib/jido_code/session/persistence.ex`

**Section:** Add after session restoration functions (around line 1220)

### Function Signature

```elixir
@doc """
Cleans up old persisted sessions by deleting files older than max_age_days.

Scans all persisted session files and deletes those whose `closed_at` timestamp
is older than the specified maximum age. Continues on errors, collecting all
failures into the result map.

## Parameters

- `max_age_days` - Maximum age in days (default: 30). Sessions closed more than
  this many days ago will be deleted.

## Returns

`{:ok, result_map}` where result_map contains:
- `:deleted` - Count of successfully deleted sessions
- `:failed` - Count of sessions that failed to delete
- `:skipped` - Count of sessions with invalid timestamps
- `:deleted_ids` - List of session IDs that were deleted
- `:errors` - List of tuples `{session_id, reason}` for failures

Returns `{:ok, %{deleted: 0, ...}}` if no sessions are old enough to delete.

## Examples

    iex> Persistence.cleanup()
    {:ok, %{deleted: 5, failed: 0, skipped: 0, deleted_ids: [...], errors: []}}

    iex> Persistence.cleanup(7)  # Clean up sessions older than 1 week
    {:ok, %{deleted: 12, failed: 1, skipped: 0, deleted_ids: [...], errors: [...]}}

## Safety

This function is safe to run multiple times:
- Already-deleted sessions won't be found by list_persisted/0
- Invalid/missing files are handled gracefully
- Errors are collected but don't prevent cleanup of other sessions
"""
@spec cleanup(pos_integer()) :: {:ok, map()}
def cleanup(max_age_days \\ 30)
```

### Implementation Strategy

```elixir
def cleanup(max_age_days \\ 30) when is_integer(max_age_days) and max_age_days > 0 do
  # 1. Calculate cutoff time
  cutoff = DateTime.add(DateTime.utc_now(), -max_age_days * 86400, :second)

  # 2. Get all persisted sessions
  sessions = list_persisted()

  # 3. Filter old sessions and collect results
  {deleted_ids, errors, skipped_count} =
    sessions
    |> Enum.reduce({[], [], 0}, fn session, {del_acc, err_acc, skip_acc} ->
      case parse_and_check_timestamp(session, cutoff) do
        :skip ->
          # Invalid timestamp - don't delete, just skip
          {del_acc, err_acc, skip_acc + 1}

        :too_recent ->
          # Not old enough - skip
          {del_acc, err_acc, skip_acc}

        :should_delete ->
          # Attempt deletion
          case delete_persisted(session.id) do
            :ok ->
              {[session.id | del_acc], err_acc, skip_acc}

            {:error, reason} ->
              Logger.warning("Failed to delete old session #{session.id}: #{inspect(reason)}")
              {del_acc, [{session.id, reason} | err_acc], skip_acc}
          end
      end
    end)

  # 4. Return results
  {:ok, %{
    deleted: length(deleted_ids),
    failed: length(errors),
    skipped: skipped_count,
    deleted_ids: Enum.reverse(deleted_ids),
    errors: Enum.reverse(errors)
  }}
end
```

### Helper Function

```elixir
# Private helper to parse timestamp and determine action
defp parse_and_check_timestamp(session, cutoff) do
  case DateTime.from_iso8601(session.closed_at) do
    {:ok, closed_at, _offset} ->
      if DateTime.compare(closed_at, cutoff) == :lt do
        :should_delete
      else
        :too_recent
      end

    {:error, _reason} ->
      # Invalid timestamp - skip this session
      Logger.warning("Skipping session #{session.id} with invalid timestamp: #{session.closed_at}")
      :skip
  end
end
```

### Edge Cases to Handle

1. **Invalid Timestamps**: If `closed_at` is malformed, skip the session and log warning
2. **File Already Deleted**: `delete_persisted/1` already handles this (returns `:ok`)
3. **Permission Errors**: Collect as error, continue with others
4. **Empty Sessions List**: Returns `{:ok, %{deleted: 0, failed: 0, skipped: 0, ...}}`
5. **All Sessions Recent**: Returns successful result with 0 deletions
6. **Negative max_age_days**: Guard clause prevents this (compile-time check)
7. **Zero max_age_days**: Guard clause prevents this
8. **Very Large max_age_days**: Works fine, just deletes more sessions

### Error Handling Details

| Error Scenario | Behavior | Result Impact |
|---------------|----------|---------------|
| Invalid `closed_at` | Skip session, log warning | Increment `skipped` count |
| File missing | `delete_persisted/1` returns `:ok` | Increment `deleted` count |
| Permission denied | Log warning, collect error | Increment `failed` count |
| Invalid session ID | Won't occur (from `list_persisted/0`) | N/A |
| Disk full | Unlikely (deleting, not writing) | Increment `failed` count |

## 4. Success Criteria

### Functional Requirements

- [ ] Function accepts max_age_days parameter with default of 30
- [ ] Correctly calculates cutoff DateTime
- [ ] Deletes only sessions older than cutoff
- [ ] Does NOT delete recent sessions
- [ ] Returns accurate count of deleted sessions
- [ ] Collects and reports all errors
- [ ] Handles invalid timestamps gracefully
- [ ] Idempotent (safe to run multiple times)

### Non-Functional Requirements

- [ ] No crashes on individual file errors
- [ ] Performance acceptable for 100+ session files
- [ ] Clear logging of warnings/errors
- [ ] Clean, readable implementation
- [ ] Well-documented with @doc and @spec

### Test Coverage

- [ ] All test cases pass (see Section 6)
- [ ] Covers happy path, error path, and edge cases
- [ ] At least 95% line coverage for cleanup/1

## 5. Implementation Plan

### Step 1: Implement Core Function

**Time Estimate:** 30 minutes

1. Add function signature with @doc and @spec
2. Implement cutoff calculation
3. Implement session filtering logic
4. Implement deletion loop with error collection
5. Add logging statements

**Verification:** Code compiles, dialyzer passes

### Step 2: Implement Helper Function

**Time Estimate:** 15 minutes

1. Add `parse_and_check_timestamp/2` private function
2. Handle all DateTime parsing cases
3. Add warning logging for invalid timestamps

**Verification:** Code compiles, dialyzer passes

### Step 3: Write Unit Tests

**Time Estimate:** 60 minutes

1. Create test file or add to `persistence_test.exs`
2. Implement all test cases (see Section 6)
3. Run tests and verify 100% pass rate

**Verification:** `mix test test/jido_code/session/persistence_test.exs`

### Step 4: Manual Testing

**Time Estimate:** 20 minutes

1. Create several test sessions with different timestamps
2. Run cleanup with various max_age_days values
3. Verify correct sessions deleted
4. Check error handling with permission-denied file

**Verification:** Manual inspection of `~/.jido_code/sessions/`

### Step 5: Code Review and Documentation

**Time Estimate:** 15 minutes

1. Run `mix credo --strict`
2. Run `mix dialyzer`
3. Review inline documentation
4. Check error messages are clear

**Verification:** No credo warnings, no dialyzer errors

### Total Estimated Time: 2.5 hours

## 6. Testing Strategy

### Unit Tests

**Test File:** `test/jido_code/session/persistence_test.exs`

**New Test Module:** Add `describe "cleanup/1"` block

```elixir
describe "cleanup/1" do
  setup do
    # Ensure clean sessions directory
    dir = Persistence.sessions_dir()
    File.mkdir_p!(dir)

    # Create test sessions with different ages
    now = DateTime.utc_now()

    sessions = [
      # Old sessions (should be deleted)
      create_test_session("old-1", DateTime.add(now, -40 * 86400, :second)),
      create_test_session("old-2", DateTime.add(now, -35 * 86400, :second)),
      create_test_session("old-3", DateTime.add(now, -31 * 86400, :second)),

      # Recent sessions (should NOT be deleted)
      create_test_session("recent-1", DateTime.add(now, -29 * 86400, :second)),
      create_test_session("recent-2", DateTime.add(now, -1 * 86400, :second)),
      create_test_session("recent-3", now),

      # Invalid timestamp (should be skipped)
      create_test_session_with_bad_timestamp("invalid-1")
    ]

    %{sessions: sessions, now: now}
  end

  test "deletes sessions older than 30 days by default", %{sessions: sessions} do
    assert {:ok, result} = Persistence.cleanup()

    assert result.deleted == 3
    assert result.failed == 0
    assert result.skipped == 1  # Invalid timestamp
    assert length(result.deleted_ids) == 3
    assert "old-1" in result.deleted_ids
    assert "old-2" in result.deleted_ids
    assert "old-3" in result.deleted_ids

    # Verify files actually deleted
    refute File.exists?(Persistence.session_file("old-1"))
    refute File.exists?(Persistence.session_file("old-2"))
    refute File.exists?(Persistence.session_file("old-3"))

    # Verify recent sessions still exist
    assert File.exists?(Persistence.session_file("recent-1"))
    assert File.exists?(Persistence.session_file("recent-2"))
    assert File.exists?(Persistence.session_file("recent-3"))
  end

  test "accepts custom max_age_days parameter" do
    assert {:ok, result} = Persistence.cleanup(7)

    # Should delete everything older than 7 days
    assert result.deleted == 5  # old-1, old-2, old-3, recent-1 (29 days)
  end

  test "returns zero deletions when all sessions are recent" do
    # Clean up old sessions first
    Persistence.cleanup(7)

    # Now cleanup again
    assert {:ok, result} = Persistence.cleanup(30)

    assert result.deleted == 0
    assert result.failed == 0
    assert result.errors == []
  end

  test "is idempotent - safe to run multiple times" do
    assert {:ok, result1} = Persistence.cleanup()
    assert result1.deleted == 3

    # Run again immediately
    assert {:ok, result2} = Persistence.cleanup()
    assert result2.deleted == 0  # Nothing left to delete
  end

  test "handles empty sessions directory gracefully" do
    # Delete all sessions
    Persistence.list_persisted()
    |> Enum.each(fn s -> Persistence.session_file(s.id) |> File.rm() end)

    assert {:ok, result} = Persistence.cleanup()

    assert result.deleted == 0
    assert result.failed == 0
    assert result.skipped == 0
  end

  test "skips sessions with invalid timestamps" do
    # Create session with malformed closed_at
    bad_session = %{
      "version" => 1,
      "id" => "bad-timestamp",
      "name" => "Test",
      "project_path" => "/tmp/test",
      "config" => %{},
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-01T00:00:00Z",
      "closed_at" => "not-a-valid-date",
      "conversation" => [],
      "todos" => []
    }

    path = Persistence.session_file("bad-timestamp")
    File.write!(path, Jason.encode!(bad_session))

    assert {:ok, result} = Persistence.cleanup()

    assert result.skipped >= 1
    # Bad session should NOT be deleted
    assert File.exists?(path)
  end

  test "continues cleanup even if one deletion fails" do
    # This test is tricky - need to make one file undeletable
    # Strategy: Create sessions, then make one read-only

    # Create old sessions
    Persistence.cleanup(0)  # Clean slate

    create_test_session("delete-1", DateTime.add(DateTime.utc_now(), -40 * 86400, :second))
    create_test_session("delete-2", DateTime.add(DateTime.utc_now(), -40 * 86400, :second))

    # Make one file read-only (platform-dependent)
    protected_path = Persistence.session_file("delete-1")
    File.chmod!(protected_path, 0o444)

    assert {:ok, result} = Persistence.cleanup()

    # Should delete delete-2 even though delete-1 failed
    assert result.deleted >= 1
    assert result.failed >= 1  # delete-1 should fail

    # Cleanup
    File.chmod!(protected_path, 0o644)
    File.rm(protected_path)
  end

  test "validates max_age_days is positive" do
    # These should fail at compile time or raise ArgumentError
    # Guard clause: when is_integer(max_age_days) and max_age_days > 0

    assert_raise FunctionClauseError, fn ->
      Persistence.cleanup(0)
    end

    assert_raise FunctionClauseError, fn ->
      Persistence.cleanup(-1)
    end
  end

  test "works with very large max_age_days" do
    # Should delete everything
    assert {:ok, result} = Persistence.cleanup(36500)  # 100 years

    # All old sessions should be deleted
    assert result.deleted >= 3
  end

  test "returns detailed error information" do
    # Create scenario with multiple error types
    create_test_session("good-old", DateTime.add(DateTime.utc_now(), -40 * 86400, :second))
    create_test_session_with_bad_timestamp("bad-ts")

    # Make one read-only
    protected = "protected-old"
    create_test_session(protected, DateTime.add(DateTime.utc_now(), -40 * 86400, :second))
    protected_path = Persistence.session_file(protected)
    File.chmod!(protected_path, 0o444)

    assert {:ok, result} = Persistence.cleanup()

    # Check all result fields present
    assert Map.has_key?(result, :deleted)
    assert Map.has_key?(result, :failed)
    assert Map.has_key?(result, :skipped)
    assert Map.has_key?(result, :deleted_ids)
    assert Map.has_key?(result, :errors)

    # Errors should be tuples of {session_id, reason}
    if result.failed > 0 do
      assert is_list(result.errors)
      {id, reason} = hd(result.errors)
      assert is_binary(id)
      assert is_tuple(reason) or is_atom(reason)
    end

    # Cleanup
    File.chmod!(protected_path, 0o644)
    File.rm(protected_path)
  end
end
```

### Test Helper Functions

```elixir
# In test setup or test_helper.exs
defp create_test_session(id, closed_at) do
  session = Persistence.new_session(%{
    id: id,
    name: "Test Session",
    project_path: "/tmp/test",
    created_at: DateTime.to_iso8601(closed_at),
    updated_at: DateTime.to_iso8601(closed_at),
    closed_at: DateTime.to_iso8601(closed_at)
  })

  :ok = Persistence.write_session_file(id, session)
  session
end

defp create_test_session_with_bad_timestamp(id) do
  bad_session = %{
    "version" => 1,
    "id" => id,
    "name" => "Test",
    "project_path" => "/tmp/test",
    "config" => %{},
    "created_at" => "2024-01-01T00:00:00Z",
    "updated_at" => "2024-01-01T00:00:00Z",
    "closed_at" => "invalid-timestamp",
    "conversation" => [],
    "todos" => []
  }

  path = Persistence.session_file(id)
  File.write!(path, Jason.encode!(bad_session))
  bad_session
end
```

### Integration Testing

After implementing cleanup/1, test integration with future TUI command:

```elixir
# Future test in TUI command handler tests
test "/resume cleanup command" do
  # Create old sessions
  # Execute command
  # Verify user sees "Cleaned up N old sessions"
end
```

## 7. Edge Cases Analysis

### Edge Case Matrix

| Scenario | Input | Expected Output | Notes |
|----------|-------|----------------|-------|
| All sessions recent | `cleanup(30)` | `deleted: 0` | Normal case, nothing to do |
| All sessions old | `cleanup(30)` | `deleted: N` | Deletes all N sessions |
| Mixed ages | `cleanup(30)` | `deleted: X` | Deletes only old ones |
| Empty directory | `cleanup(30)` | `deleted: 0` | Graceful, no error |
| Invalid timestamp | `cleanup(30)` | `skipped: 1` | Skips invalid, continues |
| Permission denied | `cleanup(30)` | `failed: 1` | Collects error, continues |
| Already deleted | `cleanup(30)` | `deleted: N` | Idempotent |
| Very small max_age | `cleanup(1)` | `deleted: N` | Works correctly |
| Very large max_age | `cleanup(999999)` | `deleted: N` | Deletes all |
| Negative max_age | `cleanup(-1)` | Compile error | Guard clause |
| Zero max_age | `cleanup(0)` | Compile error | Guard clause |
| Non-integer max_age | `cleanup(3.5)` | Compile error | Type error |

### Boundary Conditions

1. **Exactly 30 days old**: Session at exactly 30.0 days is deleted (< comparison)
2. **One second under 30 days**: Not deleted
3. **Maximum file size**: Cleanup doesn't read file contents, only metadata
4. **Concurrent cleanup calls**: Safe due to filesystem atomicity
5. **Cleanup during session creation**: Safe, new session has recent timestamp

## 8. Performance Considerations

### Current Performance

- `list_persisted/0` reads metadata from ALL session files
- With 100 files: ~100ms (parsing JSON headers)
- With 1000 files: ~1s (linear growth)

### Cleanup Performance

- For 100 old sessions: ~200ms (100ms list + 100ms delete)
- Deletion is fast (single File.rm call per file)
- No performance concerns for realistic usage (< 1000 sessions)

### Future Optimization

If performance becomes an issue:
1. Add index file with timestamps (avoid parsing all JSON)
2. Batch deletions
3. Background cleanup process

Not needed for MVP.

## 9. Future Enhancements

### Automatic Scheduled Cleanup

Future task could add:
```elixir
# In application.ex or session supervisor
def schedule_cleanup do
  # Run cleanup every 24 hours
  :timer.apply_interval(86400 * 1000, Persistence, :cleanup, [30])
end
```

### Configurable Max Age

Add to settings.json:
```json
{
  "session_cleanup_days": 30
}
```

### Cleanup on Startup

Run cleanup automatically when TUI starts (configurable).

### Archive Instead of Delete

Option to move old sessions to archive folder instead of deleting.

## 10. Documentation Updates

### Module Documentation

Update `@moduledoc` in `persistence.ex` to mention cleanup:

```elixir
@moduledoc """
Session persistence schema and utilities.

...

## Session Cleanup

Old persisted sessions can be cleaned up using `cleanup/1`:

    # Delete sessions older than 30 days
    Persistence.cleanup()

    # Delete sessions older than 7 days
    Persistence.cleanup(7)

See `cleanup/1` for details.
"""
```

### CLAUDE.md

Add to "Key Modules" table:

```markdown
| `JidoCode.Session.Persistence` | Session save/load/cleanup with JSON storage |
```

## 11. Summary

### What We're Building

A `cleanup/1` function that safely removes old persisted session files based on age.

### Why It Matters

Prevents disk bloat, protects privacy, improves performance, reduces clutter.

### Key Features

- Default 30-day retention
- Graceful error handling
- Detailed result reporting
- Idempotent operation
- Well-tested

### Implementation Checklist

- [ ] Implement `cleanup/1` function
- [ ] Implement `parse_and_check_timestamp/2` helper
- [ ] Add comprehensive unit tests (11+ test cases)
- [ ] Run credo and dialyzer
- [ ] Manual testing with real session files
- [ ] Update module documentation
- [ ] Mark task complete in phase-06.md

### Estimated Effort

**2.5 hours** total implementation and testing time.

### Dependencies

All dependencies complete:
- Task 6.3.1: `list_persisted/0` exists
- Task 6.4.2: `delete_persisted/1` exists (private)

### Next Steps

1. Implement the cleanup function
2. Write and run tests
3. Verify with manual testing
4. Proceed to Task 6.6.2 (Delete Command)
