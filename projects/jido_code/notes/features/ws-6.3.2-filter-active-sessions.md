# Feature: Task 6.3.2 - Filter Active Sessions

**Task:** Implement `list_resumable/0` to exclude already-active sessions from persisted list
**Branch:** `feature/ws-6.3.2-filter-active-sessions`
**Phase:** 6.3 Session Listing (Persisted)

---

## Problem Statement

When listing persisted sessions for resumption, we need to exclude sessions that are already active. This prevents users from attempting to resume a session that's currently running, which would cause conflicts.

**Impact:**
- Prevents duplicate session conflicts
- Provides clean UX for session resumption
- Enforces single-session-per-project constraint

---

## Solution Overview

Implement `list_resumable/0` that:
1. Gets list of all persisted sessions via `list_persisted/0`
2. Gets list of active session IDs via `SessionRegistry.list_ids/0`
3. Gets list of active project paths via `SessionRegistry.list_all/0`
4. Filters out sessions matching either active ID or active project path

**Key Decisions:**
- Filter by both ID and project_path for safety
- Use existing SessionRegistry functions (no new APIs needed)
- Return same metadata format as `list_persisted/0`

---

## Technical Details

**Files Modified:**
- `lib/jido_code/session/persistence.ex` - Add `list_resumable/0`
- `test/jido_code/session/persistence_test.exs` - Add filtering tests

**Dependencies:**
- `JidoCode.SessionRegistry.list_ids/0` - Get active session IDs
- `JidoCode.SessionRegistry.list_all/0` - Get active sessions with project paths
- `list_persisted/0` - Get all persisted sessions

**Data Flow:**
```
list_resumable/0
  ├─> SessionRegistry.list_ids() → [active_ids]
  ├─> SessionRegistry.list_all() → [active_sessions] → extract project_paths
  ├─> list_persisted() → [persisted_sessions]
  └─> Filter: reject if id in active_ids OR project_path in active_paths
```

---

## Success Criteria

- ✅ `list_resumable/0` returns empty list when no persisted sessions
- ✅ `list_resumable/0` excludes sessions with active ID
- ✅ `list_resumable/0` excludes sessions with active project_path
- ✅ `list_resumable/0` includes persisted sessions with no conflicts
- ✅ All tests pass (target: 85+ total tests)
- ✅ No credo issues

---

## Implementation Plan

### Step 1: Implement `list_resumable/0`
- [x] Add function to `lib/jido_code/session/persistence.ex`
- [x] Get active IDs using `SessionRegistry.list_ids/0`
- [x] Get active project paths from `SessionRegistry.list_all/0`
- [x] Filter persisted list by both ID and project_path
- [x] Add @spec and documentation

### Step 2: Write Unit Tests
- [x] Test empty persisted list returns empty
- [x] Test excludes session with matching ID
- [x] Test excludes session with matching project_path
- [x] Test includes session with no conflicts
- [x] Test handles multiple active sessions
- [x] Test handles multiple persisted sessions

### Step 3: Integration & Documentation
- [x] Run full test suite
- [x] Fix any credo issues
- [x] Update phase plan checkboxes
- [x] Write summary document

---

## Current Status

### ✅ What Works
- `list_resumable/0` implemented and tested
- Filters by both session ID and project_path
- 8 new tests added (85 total tests)
- All tests passing
- No credo issues
- Phase plan updated
- Summary document complete

### 🔄 What's Next
- Ready for commit and merge to work-session
- Next task: 6.4.1 - Load Persisted Session

### 🧪 How to Run
```bash
mix test test/jido_code/session/persistence_test.exs
mix credo lib/jido_code/session/persistence.ex
```

**Test Results:**
```
85 tests, 0 failures
No credo issues
```

---

## Notes/Considerations

**Edge Cases:**
- No persisted sessions → return []
- No active sessions → return all persisted
- All persisted are active → return []
- Session ID matches but different project_path → still excluded (safety first)

**Future Improvements:**
- Could add filtering options (by project name, date range, etc.)
- Could add metadata about why session isn't resumable

**Risks:**
- None - simple filtering logic with existing functions
