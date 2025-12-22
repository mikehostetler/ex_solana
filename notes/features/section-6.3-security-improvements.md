# Feature: Section 6.3 Security & Quality Improvements

**Branch:** `feature/section-6.3-security-fixes`
**Based On:** Section 6.3 Code Review findings
**Review Document:** `notes/reviews/section-6.3-review.md`

---

## Problem Statement

The Section 6.3 review identified several critical security vulnerabilities and quality improvements needed in the session persistence implementation:

**Critical Security Issues:**
1. **Path Traversal Vulnerability** (HIGH) - Session IDs not validated, allowing arbitrary file access
2. **JSON DoS Vulnerability** (MEDIUM-HIGH) - No file size limits, allowing memory exhaustion
3. **Information Disclosure** (MEDIUM) - No access control, cross-project data leakage

**Quality Improvements:**
4. Error logging for visibility
5. Optimize duplicate ETS reads
6. Code duplication reduction

**Impact:**
- Security vulnerabilities could lead to data breaches, DoS attacks, or system compromise
- Missing error logs reduce operational visibility
- Code duplication increases maintenance burden

---

## Solution Overview

We'll address all issues in priority order, committing after each category:

### Phase 1: Critical Security Fixes (BLOCKERS)
1. Fix path traversal with UUID validation
2. Add file size limits for DoS prevention
3. Implement basic logging for errors

### Phase 2: Important Security (CONCERNS)
4. Add information disclosure protection (project-based filtering)
5. Fix atom exhaustion bypass in normalize_keys

### Phase 3: Performance & Quality (IMPROVEMENTS)
6. Optimize duplicate ETS reads
7. Add error logging
8. Extract common validation helpers (optional)

---

## Technical Details

**Files to Modify:**
- `lib/jido_code/session/persistence.ex` - Add validation, limits, logging
- `test/jido_code/session/persistence_test.exs` - Add security tests

**Dependencies:**
- Elixir Logger (already available)
- No new external dependencies needed

**Testing Strategy:**
- Add tests for path traversal attempts
- Add tests for large file handling
- Add tests for validation edge cases
- Ensure all existing tests still pass

---

## Success Criteria

### Phase 1 - Critical Security
- ✅ Session IDs validated against UUID v4 format
- ✅ Invalid session IDs rejected with clear error
- ✅ File size limit enforced (10MB max)
- ✅ Large files skipped gracefully
- ✅ Errors logged for operational visibility
- ✅ All tests pass

### Phase 2 - Important Security
- ✅ normalize_keys handles errors properly
- ✅ Unknown keys logged and skipped
- ✅ All tests pass

### Phase 3 - Performance & Quality
- ✅ Single ETS read in list_resumable/0
- ✅ Error logging comprehensive
- ✅ All tests pass
- ✅ No credo issues

---

## Implementation Plan

### Phase 1: Critical Security Fixes

#### Task 1.1: Fix Path Traversal Vulnerability
- [ ] Add UUID v4 validation regex
- [ ] Add `valid_session_id?/1` private function
- [ ] Update `session_file/1` to validate before use
- [ ] Add sanitization as fallback
- [ ] Add tests for various attack vectors:
  - `../` traversal attempts
  - Absolute path injection
  - Special characters
  - Invalid UUIDs
- [ ] Verify existing tests still pass

#### Task 1.2: Add File Size Limits
- [ ] Define `@max_session_file_size` constant (10MB)
- [ ] Add `validate_file_size/1` helper
- [ ] Update `load_session_metadata/1` to check size before reading
- [ ] Add tests for:
  - Files under limit (pass)
  - Files over limit (skipped)
  - File.stat errors (handled gracefully)
- [ ] Verify large file handling

#### Task 1.3: Add Basic Error Logging
- [ ] Add `require Logger` to module
- [ ] Log file size violations
- [ ] Log file read errors (non-:enoent)
- [ ] Log path validation failures
- [ ] Test log output manually

#### Commit: "fix(security): Add path validation and file size limits"

### Phase 2: Important Security Fixes

#### Task 2.1: Fix normalize_keys Atom Handling
- [ ] Define allowed keys list
- [ ] Update normalize_keys to validate against allowed list
- [ ] Log unknown keys
- [ ] Skip unknown keys instead of failing
- [ ] Add tests for unknown keys
- [ ] Verify error handling

#### Commit: "fix(security): Improve normalize_keys error handling"

### Phase 3: Performance & Quality Improvements

#### Task 3.1: Optimize Duplicate ETS Reads
- [ ] Refactor `list_resumable/0` to call `list_all()` once
- [ ] Extract both IDs and paths in single pass
- [ ] Verify performance with benchmarks (optional)
- [ ] Ensure tests still pass

#### Task 3.2: Comprehensive Error Logging
- [ ] Log all non-:enoent file system errors
- [ ] Add context to log messages (file path, reason)
- [ ] Use appropriate log levels (warning vs error)
- [ ] Document logging behavior

#### Commit: "refactor(perf): Optimize ETS reads and improve logging"

---

## Current Status

### ✅ What's Done
- [x] Review completed
- [x] Feature branch created
- [x] Planning document created

### 🔄 What's Next
- [ ] Phase 1: Critical security fixes
  - [ ] Path traversal protection
  - [ ] File size limits
  - [ ] Basic logging
- [ ] Phase 2: Important security fixes
- [ ] Phase 3: Performance improvements

### 🧪 How to Test

```bash
# Run all persistence tests
mix test test/jido_code/session/persistence_test.exs

# Run with coverage
mix test --cover

# Check for credo issues
mix credo lib/jido_code/session/persistence.ex --strict

# Manual security testing
iex -S mix
Persistence.session_file("../../../etc/passwd")  # Should fail
Persistence.session_file("not-a-uuid")  # Should fail
```

---

## Notes/Considerations

### Security Decisions
1. **UUID Validation**: Using strict UUID v4 regex prevents all path traversal
2. **File Size Limit**: 10MB is generous for session metadata (typical: <1MB)
3. **Logging**: Using Logger.warning for operational issues, not Logger.error

### Trade-offs
1. **Information Disclosure Fix**: Skipped for now as it requires architectural changes (project context in function calls)
2. **Validation Helpers**: Extracting common helpers is lower priority, can be done later
3. **DateTime Utility**: Can be addressed in a separate refactoring task

### Edge Cases Handled
- Malformed UUIDs
- Files larger than limit
- Missing or inaccessible files
- Concurrent file operations
- Unknown JSON keys

### Future Work
- Project-based access control (requires API changes)
- File locking for concurrent writes
- DateTime utility module extraction
- Validation helper consolidation

---

## Dependencies on Other Tasks

**Blocking:** None - all changes are self-contained

**Blocked By:** None

**Related:**
- Section 6.4 (Load Persisted Session) will benefit from these security fixes
- Future session resumption features will inherit these protections

---

## Risks

**Low Risk:**
- Changes are additive (validation, limits, logging)
- Comprehensive test coverage
- No breaking API changes

**Mitigation:**
- Test thoroughly before committing each phase
- Verify all existing tests pass
- Manual security testing for each fix
