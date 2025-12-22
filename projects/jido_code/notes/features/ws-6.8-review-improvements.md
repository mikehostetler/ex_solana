# Feature Planning: Phase 6 Review Improvements

**Feature ID:** ws-6.8
**Status:** Planning
**Priority:** Medium-High
**Created:** 2025-12-10
**Review Source:** notes/reviews/phase-06-review.md

## Executive Summary

This feature addresses findings from the comprehensive 7-agent review of Phase 6 (Session Persistence). While the implementation achieved an **A grade** and is **production-ready**, the review identified optimization opportunities and testing gaps that should be addressed to enhance maintainability, performance, and robustness.

**Key Focus Areas:**
- Security improvements (2 medium-severity issues)
- Testing gaps (concurrent operations, I/O failures)
- Performance optimizations (PBKDF2 caching, rate limit cleanup)
- Code organization (test helper consolidation, configuration extraction)

**Overall Assessment:** Production-ready with identified improvements that reduce technical debt and enhance system resilience.

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Technical Design](#technical-design)
4. [Implementation Plan](#implementation-plan)
5. [Testing Strategy](#testing-strategy)
6. [Success Criteria](#success-criteria)
7. [Risk Analysis](#risk-analysis)

---

## Problem Statement

### Review Findings Summary

The Phase 6 comprehensive review (7 specialized agents) identified improvements across four dimensions:

#### 1. Security Issues (2 Medium, 4 Low)

**Medium Severity:**

1. **Session ID Enumeration via Directory Listing**
   - **Location:** `lib/jido_code/session/persistence.ex:578-582`
   - **Issue:** `list_persisted()` returns `[]` on permission errors, masking security issues
   - **Impact:** User unaware sessions exist when permissions restricted
   - **Recommendation:** Return `{:error, :eacces}`, let caller handle
   - **Severity:** Medium (information disclosure, local attacker)

2. **Information Disclosure via Error Messages**
   - **Location:** `lib/jido_code/session/persistence.ex:380-384, 814-840`
   - **Issue:** Error messages reveal internal paths, UUID formats, crypto details
   - **Impact:** Local attacker learns about sessions, multi-user systems expose logs
   - **Recommendation:** Generic user-facing messages, detailed internal logging
   - **Severity:** Medium (information disclosure)

**Low Severity:**

3. **Weak Signing Key Derivation**
   - **Location:** `lib/jido_code/session/persistence/crypto.ex:124-138`
   - **Issue:** Hostname predictable ("localhost" on dev), compile-time salt static
   - **Impact:** Deterministic key derivation enables signature forgery on dev systems
   - **Recommendation:** Add per-machine secret file, multiple entropy sources
   - **Severity:** Low-Medium (requires local access)

4. **Resource Exhaustion via Unlimited Persisted Sessions**
   - **Location:** `lib/jido_code/session/persistence.ex:435-443`
   - **Issue:** No limit on persisted session count
   - **Impact:** Create 10,000 sessions until disk full (100MB+)
   - **Recommendation:** Max session count (e.g., 100), auto-cleanup on limit
   - **Severity:** Low (requires malicious local user)

5. **TOCTOU Mitigation Incomplete**
   - **Location:** `lib/jido_code/session/persistence.ex:1292-1301`
   - **Issue:** Re-validation only checks existence/type, not ownership/permissions
   - **Impact:** `chown`/`chmod` during startup window changes security properties
   - **Recommendation:** Cache stat info, compare ownership/permissions/inode
   - **Severity:** Low (requires precise timing, local access)

6. **Rate Limiting Bypass via Session ID Variation**
   - **Location:** `lib/jido_code/session/persistence.ex:1214`, `lib/jido_code/rate_limit.ex:72-96`
   - **Issue:** Rate limit keys on session ID, attacker creates multiple sessions
   - **Impact:** Create 100 sessions, resume each 5 times = 500 ops (bypass 5/60s)
   - **Recommendation:** Add global rate limit, track by user/process
   - **Severity:** Low (requires malicious local user)

#### 2. Testing Gaps (Critical & Medium Priority)

**Critical Gaps:**

1. **Concurrent Operations NOT TESTED**
   - Concurrent saves to same session
   - Resume while save in progress
   - Multiple resume attempts of same session
   - **Impact:** Real users may trigger these scenarios
   - **Recommendation:** New file `test/jido_code/session/persistence_concurrent_test.exs`

2. **I/O Failures MINIMAL TESTING**
   - Disk full during save
   - Permission errors during load
   - Directory deletion mid-operation
   - **Impact:** Will cause data loss in production
   - **Recommendation:** Add I/O failure mocking tests

3. **Race Conditions in Auto-Save**
   - Message added during save window
   - Todo updates during serialization
   - **Impact:** Could lose user data
   - **Recommendation:** Test concurrent modifications during save

#### 3. Performance Concerns (Medium Priority)

1. **Signing Key Recomputed on Every Save**
   - **Location:** `lib/jido_code/session/persistence/crypto.ex:124-138`
   - **Issue:** PBKDF2 (100k iterations) computed per save operation
   - **Impact:** Unnecessary CPU overhead
   - **Recommendation:** Cache signing key in crypto module

2. **Rate Limit Timestamp Lists Unbounded**
   - **Location:** `lib/jido_code/rate_limit.ex:72-96`
   - **Issue:** Timestamp lists grow without bounds
   - **Impact:** Memory growth over time
   - **Recommendation:** Cap at `limit * 2` entries

3. **Large Conversation Histories**
   - **Location:** `lib/jido_code/session/state.ex` (assumed)
   - **Issue:** `Enum.reverse/1` on every `get_messages/1` call
   - **Impact:** O(n) operation on potentially large lists
   - **Recommendation:** Store messages in correct order or paginate

4. **Cleanup Iteration Performance**
   - **Location:** `lib/jido_code/rate_limit.ex` cleanup logic
   - **Issue:** ALL rate limit entries iterated every minute
   - **Impact:** Performance degradation with many entries
   - **Recommendation:** TTL-based expiry or partitioned cleanup

#### 4. Code Organization (Medium-Low Priority)

**High Priority:**

1. **Helper Function Duplication**
   - **Location:** `test/jido_code/integration/session_phase6_test.exs:132-143`, `test/jido_code/commands_test.exs:2177-2188`
   - **Functions:** `wait_for_file/2`, `wait_for_persisted_file/2`
   - **Impact:** Test maintenance burden
   - **Recommendation:** Extract to `test/support/persistence_test_helpers.ex`

2. **Test Session Creation Pattern**
   - **Location:** 3+ instances across test files
   - **Impact:** Inconsistent test data
   - **Recommendation:** Create `SessionFactory.create_test_session/1`

3. **Test Setup Duplication**
   - **Location:** Multiple test files with identical setup
   - **Impact:** Maintenance burden
   - **Recommendation:** Extract to `PersistenceTestCase` module

**Medium Priority:**

4. **Hardcoded Configuration Values**
   - **Location:** `lib/jido_code/session/persistence.ex` (`@max_session_file_size`, `@cleanup_interval`)
   - **Location:** `lib/jido_code/rate_limit.ex` (`@default_limits`, `@cleanup_interval`)
   - **Impact:** Hard to configure per environment
   - **Recommendation:** Move to `config/runtime.exs`

5. **Resume Target Resolution Logic Duplication**
   - **Location:** `lib/jido_code/commands.ex:733-764`, `lib/jido_code/commands.ex:884-968`
   - **Impact:** Inconsistent behavior risk
   - **Recommendation:** Extract `Commands.TargetResolver.resolve_target/3`

6. **Timestamp Formatting Duplication**
   - **Location:** `lib/jido_code/session/persistence.ex:1002-1003`, `lib/jido_code/session/persistence.ex:918-927`
   - **Impact:** Harder to update
   - **Recommendation:** Consolidate into `Persistence.DateTime` module

### Impact Analysis

| Category | Issues | User Impact | Maintenance Impact | Production Risk |
|----------|--------|-------------|-------------------|-----------------|
| Security (Medium) | 2 | Low (transparent fixes) | Low (one-time fixes) | Low (defense-in-depth) |
| Security (Low) | 4 | None (transparent) | Low-Medium | Very Low |
| Testing Gaps | 3 | None (preventive) | High (catches bugs) | Medium (uncaught issues) |
| Performance | 4 | Low (minor speedups) | Low | Low (no known bottlenecks) |
| Code Organization | 6 | None | High (reduces debt) | Very Low |

### Business Justification

**Why address these improvements:**
- Testing gaps create risk of undetected issues in production
- Performance optimizations prevent future scalability problems
- Code organization reduces long-term maintenance costs
- Security improvements provide defense-in-depth
- All improvements are isolated, low-risk changes

**Why these are not blockers:**
- No critical severity issues
- Existing implementation is production-ready (A grade)
- All issues have low exploitation likelihood
- Can be addressed incrementally post-deployment

**Recommended Approach:**
- **Phase 1:** Immediate improvements (1-2 days)
- **Phase 2:** Near-term improvements (next sprint)
- **Phase 3:** Long-term refactoring (technical debt backlog)

---

## Solution Overview

### High-Level Approach

Address improvements in three prioritized phases:

#### Phase 1: Immediate Improvements (1-2 days)
**Priority: HIGH - Before production deployment**

1. Configuration extraction (hardcoded values → config/runtime.exs)
2. Rate limit timestamp list bounds
3. Signing key caching
4. Error message sanitization

**Rationale:** Quick wins with high impact, no API changes, minimal risk.

#### Phase 2: Near-Term Improvements (Next Sprint)
**Priority: MEDIUM - Post-deployment refinement**

1. Test helper consolidation
2. Concurrent operation tests
3. I/O failure tests
4. Session count limits
5. Improved TOCTOU protection

**Rationale:** Testing improvements catch future regressions, code organization reduces maintenance burden.

#### Phase 3: Long-Term Refactoring (Technical Debt)
**Priority: LOW - Future iterations**

1. Module extraction (Commands, Persistence sub-modules)
2. Pagination for large histories
3. Global rate limiting
4. Enhanced key derivation

**Rationale:** Larger refactorings require careful planning, lower immediate benefit.

### Design Decisions

#### Decision 1: Configuration Format

**Options Considered:**
1. Keep hardcoded module attributes
2. Move to `config/runtime.exs`
3. Add `/settings` command for runtime config

**Decision:** Move to `config/runtime.exs` (#2)

**Rationale:**
- Standard Elixir configuration pattern
- Environment-specific values (dev vs prod)
- No runtime complexity
- Easy to override in tests

**Example:**
```elixir
# config/runtime.exs
config :jido_code, :persistence,
  max_file_size: 10 * 1024 * 1024,
  max_sessions: 100,
  cleanup_age_days: 30

config :jido_code, :rate_limits,
  resume: [limit: 5, window_seconds: 60],
  cleanup_interval: :timer.minutes(5)
```

#### Decision 2: Test Helper Organization

**Options Considered:**
1. Leave duplicated in test files
2. Extract to `test/support/persistence_test_helpers.ex`
3. Create ExUnit case template (`PersistenceTestCase`)

**Decision:** Combination of #2 and #3

**Rationale:**
- Shared functions → `persistence_test_helpers.ex`
- Shared setup/teardown → `PersistenceTestCase`
- Follow existing `test/support/` pattern
- Enables `use PersistenceTestCase` in tests

**Structure:**
```elixir
# test/support/persistence_test_helpers.ex
defmodule JidoCode.PersistenceTestHelpers do
  def wait_for_file(path, retries \\ 50)
  def create_test_session(opts \\ [])
  def create_persisted_session(id, opts \\ [])
end

# test/support/persistence_test_case.ex
defmodule JidoCode.PersistenceTestCase do
  use ExUnit.CaseTemplate
  # Shared setup/teardown
end
```

#### Decision 3: Signing Key Caching Strategy

**Options Considered:**
1. Compute key once at module load (Agent/ETS)
2. Memoize in crypto module with TTL
3. Pass key as parameter to functions

**Decision:** ETS-based cache with lazy initialization (#1)

**Rationale:**
- Crypto module already stateless
- ETS provides process-independent cache
- Lazy init handles key rotation scenarios
- Zero API changes

**Implementation:**
```elixir
defp signing_key do
  case :ets.lookup(@crypto_cache, :signing_key) do
    [{:signing_key, key}] -> key
    [] ->
      key = derive_signing_key()
      :ets.insert(@crypto_cache, {:signing_key, key})
      key
  end
end
```

#### Decision 4: Concurrent Operation Testing Strategy

**Options Considered:**
1. Skip concurrent tests (too complex)
2. Use `Task.async` for simple concurrent tests
3. Full property-based testing with StreamData

**Decision:** Task-based concurrent tests (#2)

**Rationale:**
- Validates most critical scenarios
- Manageable complexity
- Fast execution
- No external dependencies

**Test Scenarios:**
- Concurrent saves to same session (expect atomic writes)
- Save + resume race (expect consistent state)
- Multiple resume attempts (expect first wins, others fail)

#### Decision 5: Error Message Sanitization

**Options Considered:**
1. Remove all paths/UUIDs from user messages
2. Two-tier messages (user-facing + detailed logs)
3. Configuration flag for verbose errors

**Decision:** Two-tier messages (#2)

**Rationale:**
- Users get actionable errors
- Developers get debugging details in logs
- Security without usability loss
- Standard pattern in production systems

**Example:**
```elixir
# Before
{:error, "Invalid project path: /home/user/secret-project"}

# After
{:error, :invalid_project_path}
Logger.warning("Project path validation failed", path: path, reason: reason)
```

---

## Technical Design

### Architecture Changes

#### 1. Configuration System

**Changes Required:**

**File:** `config/runtime.exs`
```elixir
config :jido_code, :persistence,
  max_file_size: System.get_env("JIDO_MAX_SESSION_SIZE", "10485760") |> String.to_integer(),
  max_sessions: System.get_env("JIDO_MAX_SESSIONS", "100") |> String.to_integer(),
  cleanup_age_days: System.get_env("JIDO_CLEANUP_DAYS", "30") |> String.to_integer()

config :jido_code, :rate_limits,
  resume: [
    limit: System.get_env("JIDO_RESUME_LIMIT", "5") |> String.to_integer(),
    window_seconds: System.get_env("JIDO_RESUME_WINDOW", "60") |> String.to_integer()
  ],
  cleanup_interval: :timer.minutes(5)
```

**File:** `lib/jido_code/session/persistence.ex` (lines 51-53)
```elixir
# Before
@max_session_file_size 10 * 1024 * 1024

# After
defp max_session_file_size do
  Application.get_env(:jido_code, :persistence)[:max_file_size]
end
```

**File:** `lib/jido_code/rate_limit.ex` (lines 29-35)
```elixir
# Before
@default_limits %{resume: %{limit: 5, window_seconds: 60}}

# After
defp default_limits do
  Application.get_env(:jido_code, :rate_limits, %{
    resume: %{limit: 5, window_seconds: 60}
  })
end
```

**Impact:** 6 call sites to update, all internal

#### 2. Signing Key Caching

**Changes Required:**

**File:** `lib/jido_code/session/persistence/crypto.ex`

**Add ETS table initialization:**
```elixir
@crypto_cache :jido_code_crypto_cache

def start_link(_opts) do
  :ets.new(@crypto_cache, [:set, :public, :named_table])
  {:ok, :ok}  # Dummy process, just for ETS ownership
end
```

**Modify `signing_key/0` (private function, line ~124):**
```elixir
# Before
defp signing_key do
  salt = @app_salt <> ":" <> hostname()
  :crypto.pbkdf2_hmac(@hash_algorithm, @app_salt, salt, @iterations, @key_length)
end

# After
defp signing_key do
  case :ets.lookup(@crypto_cache, :signing_key) do
    [{:signing_key, key}] ->
      key
    [] ->
      salt = @app_salt <> ":" <> hostname()
      key = :crypto.pbkdf2_hmac(@hash_algorithm, @app_salt, salt, @iterations, @key_length)
      :ets.insert(@crypto_cache, {:signing_key, key})
      key
  end
end

# Add cache invalidation for testing
def invalidate_key_cache do
  :ets.delete(@crypto_cache, :signing_key)
end
```

**Impact:** Internal only, no API changes

#### 3. Rate Limit Bounds

**Changes Required:**

**File:** `lib/jido_code/rate_limit.ex` (line ~110-120, `record_attempt/2`)

```elixir
# Before
updated_timestamps = [now | timestamps]
:ets.insert(@table_name, {lookup_key, updated_timestamps})

# After
# Cap at 2x limit to prevent unbounded growth
max_entries = limits.limit * 2
updated_timestamps =
  [now | timestamps]
  |> Enum.take(max_entries)
:ets.insert(@table_name, {lookup_key, updated_timestamps})
```

**Impact:** Internal only, prevents memory leak

#### 4. Error Message Sanitization

**Changes Required:**

**File:** `lib/jido_code/session/persistence.ex`

**Location 1: Line 380-384 (`list_persisted/0`)**
```elixir
# Before
[] -> []
{:error, reason} -> []  # Silently returns empty

# After
[] -> []
{:error, :eacces} -> {:error, :permission_denied}
{:error, :enoent} -> []  # Session dir doesn't exist yet
{:error, reason} ->
  Logger.warning("Failed to list sessions", reason: reason)
  {:error, :list_failed}
```

**Location 2: Line 814-840 (error messages throughout)**
```elixir
# Before
{:error, "Invalid UUID format: #{session_id}"}

# After
{:error, :invalid_session_id}
# Log details separately
Logger.debug("Session validation failed",
  session_id: session_id,
  reason: "invalid UUID format"
)
```

**Impact:** Callers must handle new error tuples, TUI displays generic messages

#### 5. Test Helper Consolidation

**New Files:**

**File:** `test/support/persistence_test_helpers.ex`
```elixir
defmodule JidoCode.PersistenceTestHelpers do
  @moduledoc """
  Shared test helpers for persistence tests.
  """

  alias JidoCode.Session
  alias JidoCode.Session.Persistence

  @doc "Wait for file to exist (async operations)"
  def wait_for_file(file_path, retries \\ 50)

  @doc "Create test session with defaults"
  def create_test_session(opts \\ [])

  @doc "Create persisted session file for testing"
  def create_persisted_session(session_id, opts \\ [])

  @doc "Clean up test sessions and files"
  def cleanup_test_sessions(session_ids)
end
```

**File:** `test/support/persistence_test_case.ex`
```elixir
defmodule JidoCode.PersistenceTestCase do
  @moduledoc """
  ExUnit case template for persistence tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoCode.PersistenceTestHelpers
      alias JidoCode.Session.Persistence

      setup do
        # Clean sessions directory
        sessions_dir = Persistence.sessions_dir()
        if File.exists?(sessions_dir) do
          File.rm_rf!(sessions_dir)
        end
        File.mkdir_p!(sessions_dir)

        on_exit(fn ->
          File.rm_rf!(sessions_dir)
        end)

        :ok
      end
    end
  end
end
```

**Impact:** 3 test files modified to use helpers

### Data Structure Changes

No data structure changes required. All improvements are internal optimizations.

### API Changes

Minimal API changes required:

1. **`list_persisted/0` return value** (Breaking)
   - Before: `[] | [persisted_session_metadata()]`
   - After: `{:ok, [persisted_session_metadata()]} | {:error, atom()}`
   - **Mitigation:** Update 5 call sites (Commands, TUI)

2. **Error tuple atoms** (Breaking)
   - Before: `{:error, "string message"}`
   - After: `{:error, :atom_reason}`
   - **Mitigation:** Update error handling in Commands module

3. **Configuration access** (Internal)
   - Module attributes → Application config
   - No external API impact

### Dependencies

No new dependencies required. All improvements use existing libraries:
- ETS (built-in Erlang)
- Application config (Elixir standard)
- ExUnit (test only)

---

## Implementation Plan

### Phase 1: Immediate Improvements (1-2 days)

#### Task 1.1: Extract Configuration to runtime.exs
**Priority:** HIGH | **Effort:** 1 hour | **Risk:** LOW

**Objective:** Move hardcoded values to `config/runtime.exs` for environment-specific configuration.

**Files Modified:**
- `config/runtime.exs` (create persistence and rate_limit sections)
- `lib/jido_code/session/persistence.ex:51-53` (max_file_size)
- `lib/jido_code/rate_limit.ex:29-35` (default_limits, cleanup_interval)

**Implementation Steps:**
1. Add configuration section to `config/runtime.exs`
2. Replace `@max_session_file_size` with `max_session_file_size()` private function
3. Update all 6 call sites to use function instead of attribute
4. Replace `@default_limits` with `default_limits()` function
5. Update `@cleanup_interval` access

**Test Requirements:**
- Existing tests should pass unchanged
- Add test in `persistence_test.exs` verifying config is read
- Add test in `rate_limit_test.exs` verifying config override

**Success Criteria:**
- `mix test` passes (232+ tests)
- Configuration values overridable via Application.put_env in tests
- No hardcoded values remain in modules

**Acceptance Test:**
```elixir
# In test
Application.put_env(:jido_code, :persistence, max_file_size: 1024)
assert Persistence.max_file_size() == 1024
```

---

#### Task 1.2: Bound Rate Limit Timestamp Lists
**Priority:** HIGH | **Effort:** 30 minutes | **Risk:** LOW

**Objective:** Cap timestamp lists at `limit * 2` to prevent memory growth.

**Files Modified:**
- `lib/jido_code/rate_limit.ex:110-120` (`record_attempt/2`)

**Implementation Steps:**
1. In `record_attempt/2`, after prepending new timestamp
2. Add `Enum.take(max_entries)` where `max_entries = limits.limit * 2`
3. Update docstring noting bounded behavior

**Test Requirements:**
- Add test: "record_attempt caps timestamp list at 2x limit"
- Verify memory doesn't grow with 100+ rapid attempts

**Success Criteria:**
- Timestamp list never exceeds `limit * 2` entries
- Rate limiting behavior unchanged (still enforces sliding window)
- No performance degradation

**Acceptance Test:**
```elixir
# Record 100 attempts
for _ <- 1..100, do: RateLimit.record_attempt(:resume, "test-key")

# Verify list bounded
[{_, timestamps}] = :ets.lookup(:jido_code_rate_limits, {:resume, "test-key"})
assert length(timestamps) <= 10  # limit=5, so 2x=10
```

---

#### Task 1.3: Cache Signing Key in Crypto Module
**Priority:** HIGH | **Effort:** 1 hour | **Risk:** LOW

**Objective:** Cache PBKDF2-derived signing key to avoid recomputation on every save.

**Files Modified:**
- `lib/jido_code/session/persistence/crypto.ex:124-138` (`signing_key/0`)
- `lib/jido_code/session/persistence/crypto.ex` (add ETS initialization)

**Implementation Steps:**
1. Add `@crypto_cache` table name constant
2. Create ETS table in `start_link/1` (or Application startup)
3. Modify `signing_key/0` to check cache first
4. Add `invalidate_key_cache/0` for testing
5. Update module documentation

**Test Requirements:**
- Add test: "signing_key returns same key on multiple calls"
- Add test: "invalidate_key_cache clears cache"
- Verify existing crypto tests still pass (24 tests)
- Performance test: measure 100 saves before/after (expect ~100x speedup)

**Success Criteria:**
- Signing key computed once per application lifetime
- `invalidate_key_cache/0` available for tests
- All existing crypto tests pass

**Acceptance Test:**
```elixir
# Clear cache
Crypto.invalidate_key_cache()

# Time first call (slow)
{time1, key1} = :timer.tc(fn -> Crypto.signing_key() end)

# Time second call (fast)
{time2, key2} = :timer.tc(fn -> Crypto.signing_key() end)

assert key1 == key2
assert time2 < time1 / 10  # At least 10x faster
```

---

#### Task 1.4: Sanitize Error Messages
**Priority:** MEDIUM | **Effort:** 1.5 hours | **Risk:** MEDIUM (breaking change)

**Objective:** Return error atoms instead of strings, log details internally.

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (10+ error return sites)
- `lib/jido_code/commands.ex` (error handling for persistence calls)
- `lib/jido_code/tui.ex` (error display, if applicable)

**Implementation Steps:**
1. Audit all `{:error, "string"}` returns in persistence.ex
2. Replace with `{:error, :atom}` + Logger call
3. Update Commands module error handling
4. Add user-friendly error messages in Commands
5. Update tests expecting string errors

**Error Mapping:**
```elixir
# Before → After
"Invalid UUID format: #{id}" → :invalid_session_id
"Project path not found: #{path}" → :project_path_not_found
"Failed to parse JSON" → :invalid_file_format
```

**Test Requirements:**
- Update ~20 tests expecting string errors
- Add test: "errors contain no sensitive information"
- Verify Commands displays user-friendly messages

**Success Criteria:**
- No file paths, UUIDs, or crypto details in user-facing errors
- Detailed information available in logs
- All tests passing

**Acceptance Test:**
```elixir
# Invalid session ID
{:error, reason} = Persistence.load("invalid-uuid")
assert reason == :invalid_session_id
refute is_binary(reason)  # No string leakage
```

---

### Phase 2: Near-Term Improvements (Next Sprint)

#### Task 2.1: Extract Test Helpers
**Priority:** MEDIUM | **Effort:** 2 hours | **Risk:** LOW

**Objective:** Consolidate duplicated test helpers into shared modules.

**Files Created:**
- `test/support/persistence_test_helpers.ex`
- `test/support/persistence_test_case.ex`

**Files Modified:**
- `test/jido_code/integration/session_phase6_test.exs`
- `test/jido_code/commands_test.exs`
- `test/jido_code/session/persistence_test.exs`

**Implementation Steps:**
1. Create `PersistenceTestHelpers` module
2. Extract `wait_for_file/2` (2 duplicates)
3. Extract session creation patterns (3+ duplicates)
4. Create `PersistenceTestCase` with shared setup
5. Update test files to use helpers
6. Remove duplicated code

**Test Requirements:**
- All 232+ existing tests must pass unchanged
- No new test coverage required
- Verify test execution time unchanged

**Success Criteria:**
- Zero test helper duplication
- Tests use `use PersistenceTestCase`
- All tests passing

**Lines of Code Saved:** ~150 lines

---

#### Task 2.2: Add Concurrent Operation Tests
**Priority:** HIGH | **Effort:** 3 hours | **Risk:** MEDIUM

**Objective:** Test concurrent persistence operations (save, load, resume).

**Files Created:**
- `test/jido_code/session/persistence_concurrent_test.exs`

**Implementation Steps:**
1. Create new test file with `async: false`
2. Test: Concurrent saves to same session
3. Test: Save during resume operation
4. Test: Multiple resume attempts of same session
5. Test: Concurrent cleanup operations
6. Use `Task.async/await` for concurrency

**Test Scenarios:**
```elixir
describe "concurrent saves" do
  test "atomic writes prevent corruption"
  test "last writer wins without errors"
end

describe "save-resume race conditions" do
  test "resume during save waits for completion"
  test "save during resume fails gracefully"
end

describe "multiple resume attempts" do
  test "only first resume succeeds"
  test "subsequent resumes get file_not_found"
end
```

**Test Requirements:**
- 8-10 concurrent operation tests
- Tests must be deterministic (no flakiness)
- Use proper synchronization primitives

**Success Criteria:**
- Tests pass consistently (run 10 times without failure)
- Identifies any actual race conditions
- Tests complete in <5 seconds

**Expected Outcome:** May find bugs requiring fixes.

---

#### Task 2.3: Add I/O Failure Tests
**Priority:** MEDIUM | **Effort:** 2 hours | **Risk:** LOW

**Objective:** Test error handling for I/O failures (disk full, permissions, etc.).

**Files Modified:**
- `test/jido_code/session/persistence_test.exs`

**Implementation Steps:**
1. Mock `File.write/2` to return `{:error, :enospc}` (disk full)
2. Mock `File.read/1` to return `{:error, :eacces}` (permission denied)
3. Test directory deletion during operations
4. Test corrupted file handles
5. Verify graceful error handling

**Test Scenarios:**
```elixir
describe "I/O failures" do
  test "save handles disk full gracefully"
  test "load handles permission denied"
  test "cleanup handles file deletion mid-operation"
  test "list_persisted handles directory access errors"
end
```

**Test Requirements:**
- 6-8 I/O failure tests
- Use mocking (avoid actual I/O failures)
- Verify error messages and logging

**Success Criteria:**
- No crashes on I/O errors
- Appropriate error tuples returned
- Logs contain diagnostic information

---

#### Task 2.4: Add Session Count Limit
**Priority:** LOW-MEDIUM | **Effort:** 2 hours | **Risk:** LOW

**Objective:** Prevent resource exhaustion by limiting persisted session count.

**Files Modified:**
- `config/runtime.exs` (add `max_sessions` config)
- `lib/jido_code/session/persistence.ex` (`save/1`)

**Implementation Steps:**
1. Add `max_sessions` to config (default: 100)
2. In `save/1`, check session count before saving
3. Return `{:error, :session_limit_reached}` if exceeded
4. Add warning at 80% capacity
5. Update documentation

**Logic:**
```elixir
def save(session_id) do
  with :ok <- check_session_limit() do
    # existing save logic
  end
end

defp check_session_limit do
  count = length(list_persisted())
  max = max_sessions()

  cond do
    count >= max -> {:error, :session_limit_reached}
    count >= max * 0.8 ->
      Logger.warning("Approaching session limit: #{count}/#{max}")
      :ok
    true -> :ok
  end
end
```

**Test Requirements:**
- Test: Save fails when limit reached
- Test: Warning logged at 80%
- Test: Cleanup reduces count below limit

**Success Criteria:**
- Cannot exceed configured session limit
- Clear error message returned
- Auto-cleanup can free space

---

#### Task 2.5: Enhanced TOCTOU Protection
**Priority:** LOW | **Effort:** 1.5 hours | **Risk:** MEDIUM

**Objective:** Cache file stats and verify ownership/permissions unchanged.

**Files Modified:**
- `lib/jido_code/session/persistence.ex:1292-1301` (`revalidate_project_path/1`)

**Implementation Steps:**
1. In initial validation, capture `File.stat/1` (permissions, ownership, inode)
2. Store stat info in persisted session or validation result
3. In `revalidate_project_path/1`, re-stat and compare
4. Return error if ownership/permissions changed
5. Add tests for permission changes

**Stat Comparison:**
```elixir
defp revalidate_project_path(path, original_stat) do
  with {:ok, current_stat} <- File.stat(path),
       :ok <- validate_stat_unchanged(original_stat, current_stat) do
    Security.validate_path(path)
  end
end

defp validate_stat_unchanged(original, current) do
  if original.uid == current.uid and
     original.gid == current.gid and
     original.inode == current.inode do
    :ok
  else
    {:error, :path_security_changed}
  end
end
```

**Test Requirements:**
- Test: Resume fails if ownership changes
- Test: Resume fails if permissions changes
- Test: Resume succeeds if stats unchanged
- Platform-specific handling (Windows)

**Success Criteria:**
- Detects ownership changes during TOCTOU window
- Graceful handling of stat unavailable (Windows)
- Tests pass on Linux (skip on Windows)

**Note:** May skip 3 tests on non-POSIX platforms (existing pattern).

---

### Phase 3: Long-Term Refactoring (Technical Debt)

#### Task 3.1: Extract Module: Commands.TargetResolver
**Priority:** LOW | **Effort:** 2 hours | **Risk:** LOW

**Objective:** Extract duplicated target resolution logic from Commands module.

**Files Created:**
- `lib/jido_code/commands/target_resolver.ex`

**Files Modified:**
- `lib/jido_code/commands.ex:733-764` (resume command)
- `lib/jido_code/commands.ex:884-968` (sessions command)

**Implementation Steps:**
1. Create `Commands.TargetResolver` module
2. Extract `resolve_target/3` function
3. Handle numeric index vs UUID vs name
4. Update Commands to delegate
5. Add unit tests for resolver

**Deferred Rationale:** Low priority, no functional benefit, larger refactor scope.

---

#### Task 3.2: Add Pagination for Large Message Histories
**Priority:** LOW | **Effort:** 4 hours | **Risk:** MEDIUM

**Objective:** Avoid O(n) reverse operations on large conversation histories.

**Files Modified:**
- `lib/jido_code/session/state.ex` (store messages in correct order)
- `lib/jido_code/session/persistence.ex` (serialize without reverse)

**Deferred Rationale:** No reports of performance issues, requires State module refactor.

---

#### Task 3.3: Add Global Rate Limiting
**Priority:** LOW | **Effort:** 3 hours | **Risk:** MEDIUM

**Objective:** Prevent rate limit bypass via multiple session IDs.

**Files Modified:**
- `lib/jido_code/rate_limit.ex` (add global operation limiting)

**Deferred Rationale:** Low exploitation risk, requires process/user tracking design.

---

#### Task 3.4: Enhanced Key Derivation
**Priority:** LOW | **Effort:** 4 hours | **Risk:** HIGH

**Objective:** Use per-machine secret file and multiple entropy sources.

**Files Created:**
- `~/.jido_code/machine_secret` (generated on first run)

**Files Modified:**
- `lib/jido_code/session/persistence/crypto.ex`

**Deferred Rationale:** Breaking change (re-sign all sessions), low threat (local attack only).

---

## Testing Strategy

### Test Coverage Goals

| Component | Current Coverage | Target Coverage | New Tests Required |
|-----------|-----------------|-----------------|-------------------|
| Configuration | N/A | 90% | 5 tests |
| Rate Limit Bounds | 95% | 95% | 1 test |
| Crypto Caching | 100% | 100% | 2 tests |
| Error Messages | 80% | 90% | 5 tests |
| Test Helpers | N/A | N/A | 0 (refactor only) |
| Concurrent Ops | 0% | 80% | 10 tests |
| I/O Failures | 20% | 70% | 8 tests |
| Session Limits | 0% | 90% | 4 tests |
| TOCTOU | 50% | 80% | 3 tests |

**Total New Tests:** ~38 tests
**Total Tests After:** 270+ tests

### Testing Approach

#### Unit Tests
- Configuration reading (5 tests)
- Rate limit bounds (1 test)
- Crypto caching (2 tests)
- Error message format (5 tests)
- Session count limiting (4 tests)

#### Integration Tests
- Concurrent operations (10 tests in new file)
- I/O failure scenarios (8 tests)
- TOCTOU race conditions (3 tests)

#### Performance Tests
- Signing key cache speedup (benchmark)
- Rate limit memory bounds (memory test)

### Test Execution Strategy

**Phase 1 Tests:**
- Run after each task completion
- All existing tests must pass
- CI pipeline unchanged

**Phase 2 Tests:**
- New test files added incrementally
- May identify bugs requiring fixes
- Separate PR per test suite

**Regression Testing:**
- Full suite run before/after each phase
- 232+ existing tests must pass
- No new Credo warnings

---

## Success Criteria

### Phase 1 Success Criteria

1. **Configuration Extraction**
   - [ ] All hardcoded values moved to config/runtime.exs
   - [ ] Environment variables supported (e.g., `JIDO_MAX_SESSIONS`)
   - [ ] Tests can override config via `Application.put_env`
   - [ ] No change in runtime behavior

2. **Rate Limit Bounds**
   - [ ] Timestamp lists capped at `limit * 2`
   - [ ] Memory usage bounded under load
   - [ ] No change in rate limiting behavior

3. **Crypto Caching**
   - [ ] Signing key computed once per application lifetime
   - [ ] 10x+ speedup in save operations (measured)
   - [ ] Cache invalidation works in tests

4. **Error Sanitization**
   - [ ] No file paths in user-facing errors
   - [ ] No UUIDs in user-facing errors
   - [ ] Detailed logging available for debugging
   - [ ] Commands module displays friendly messages

**Overall Phase 1:**
- [ ] All 232+ existing tests passing
- [ ] 5-10 new tests added
- [ ] No new Credo warnings
- [ ] No performance regressions

### Phase 2 Success Criteria

1. **Test Helpers**
   - [ ] Zero duplicated test helper functions
   - [ ] `PersistenceTestCase` used in 3+ test files
   - [ ] 150+ lines of code removed

2. **Concurrent Tests**
   - [ ] 10+ concurrent operation tests
   - [ ] Tests pass consistently (10 runs, 0 failures)
   - [ ] Any race conditions identified and documented

3. **I/O Failure Tests**
   - [ ] 8+ I/O failure scenarios tested
   - [ ] No crashes on I/O errors
   - [ ] Error handling verified

4. **Session Limits**
   - [ ] Cannot exceed configured session count
   - [ ] Warning logged at 80% capacity
   - [ ] Error message clear and actionable

5. **Enhanced TOCTOU**
   - [ ] Detects ownership changes during resume
   - [ ] Tests pass on Linux (may skip on Windows)
   - [ ] Graceful handling of unavailable stats

**Overall Phase 2:**
- [ ] 270+ total tests passing
- [ ] Test coverage > 80% for all Phase 6 code
- [ ] Test execution time < 30 seconds for Phase 6 suite
- [ ] No flaky tests

### Phase 3 Success Criteria

Deferred to future planning. Success criteria TBD based on priority.

---

## Risk Analysis

### Implementation Risks

| Risk | Severity | Likelihood | Mitigation |
|------|----------|-----------|------------|
| Breaking API changes in error handling | Medium | High | Phased rollout, update all callers |
| ETS caching adds complexity | Low | Low | Simple cache, well-tested pattern |
| Concurrent tests flaky | Medium | Medium | Proper synchronization, retries |
| Configuration migration issues | Low | Low | Backward compatible defaults |
| TOCTOU tests platform-specific | Low | Medium | Skip on Windows, document |

### Production Impact Risks

| Risk | Severity | Likelihood | Mitigation |
|------|----------|-----------|------------|
| Error message changes confuse users | Low | Low | Clear documentation, gradual rollout |
| Configuration changes break deployments | Medium | Low | Backward compatible defaults |
| Caching causes stale key issues | Low | Very Low | Cache invalidation tested |
| Session limits cause unexpected failures | Medium | Low | High default (100), clear errors |

### Rollback Plan

**Phase 1 Rollback:**
- Configuration: Revert to module attributes
- Rate limit: Remove `.take()` call
- Crypto: Remove ETS cache, use direct computation
- Errors: Revert to string errors

**Phase 2 Rollback:**
- Test helpers: No production impact (test-only)
- Limits: Remove check in `save/1`
- TOCTOU: Revert to existence-only check

**Rollback Trigger:**
- Any test failure in CI
- Performance regression > 10%
- User-reported errors from API changes

---

## Phase Plan Updates

### Phase 06 Plan Updates Required

**File:** `notes/planning/work-session/phase-06.md`

#### Section 6.1: Persistence Data Structure
- No changes (complete)

#### Section 6.2: Session Saving
- Task 6.2.3: Manual save command (optional) - REMAINS SKIPPED
- Add note about configuration extraction

#### Section 6.3: Session Listing
- Update Task 6.3.1 note: `list_persisted/0` now returns `{:ok, list} | {:error, reason}`

#### Section 6.4: Session Restoration
- Task 6.4.4: Security Review Fixes - MARK COMPLETE
- Add Task 6.4.5: **Review Improvements** (this feature plan)
  - 6.4.5.1: Configuration extraction
  - 6.4.5.2: Performance optimizations (crypto cache, rate limits)
  - 6.4.5.3: Error sanitization
  - 6.4.5.4: Enhanced testing (concurrent, I/O failures)
  - 6.4.5.5: Test helper consolidation
  - 6.4.5.6: Session count limits
  - 6.4.5.7: Enhanced TOCTOU protection

#### Section 6.5: Resume Command
- No changes (complete)

#### Section 6.6: Cleanup and Maintenance
- No changes (complete)

#### Section 6.7: Phase 6 Integration Tests
- Add Task 6.7.7: **Concurrent Operation Tests**
- Add Task 6.7.8: **I/O Failure Tests**

### New Success Criteria

Add to Section: Success Criteria (line 586+):

12. **Configuration Management**: All hardcoded values configurable via runtime.exs
13. **Performance Optimization**: Crypto key cached, rate limits bounded
14. **Concurrent Safety**: Concurrent operations tested, no race conditions
15. **Error Handling**: I/O failures handled gracefully, no information leakage
16. **Test Quality**: Helpers consolidated, zero duplication, > 270 tests

---

## Appendix

### Related Documents

- **Review Document:** `notes/reviews/phase-06-review.md`
- **Phase Plan:** `notes/planning/work-session/phase-06.md`
- **Previous Security Fixes:** `notes/features/ws-6.4.3-review-fixes.md`
- **Section 6.4 Review:** `notes/reviews/section-6.4-review.md`

### Key Files Reference

**Production Code:**
- `lib/jido_code/session/persistence.ex` (1374 lines)
- `lib/jido_code/session/persistence/crypto.ex` (164 lines)
- `lib/jido_code/rate_limit.ex` (226 lines)
- `lib/jido_code/commands.ex` (1371 lines)
- `config/runtime.exs` (configuration)

**Test Code:**
- `test/jido_code/session/persistence_test.exs`
- `test/jido_code/session/persistence_crypto_test.exs`
- `test/jido_code/rate_limit_test.exs`
- `test/jido_code/integration/session_phase6_test.exs`
- `test/jido_code/commands_test.exs`

**New Test Files:**
- `test/jido_code/session/persistence_concurrent_test.exs` (Phase 2)
- `test/support/persistence_test_helpers.ex` (Phase 2)
- `test/support/persistence_test_case.ex` (Phase 2)

### Effort Estimation

**Phase 1:** 4 hours
- Task 1.1: 1 hour
- Task 1.2: 0.5 hours
- Task 1.3: 1 hour
- Task 1.4: 1.5 hours

**Phase 2:** 11.5 hours
- Task 2.1: 2 hours
- Task 2.2: 3 hours
- Task 2.3: 2 hours
- Task 2.4: 2 hours
- Task 2.5: 1.5 hours
- Task 2.6: 1 hour (documentation)

**Phase 3:** 13 hours (deferred)
- Task 3.1: 2 hours
- Task 3.2: 4 hours
- Task 3.3: 3 hours
- Task 3.4: 4 hours

**Total Effort:** 15.5 hours (Phase 1 + Phase 2)

### Timeline Estimate

**Phase 1:** 1 working day
**Phase 2:** 2 working days
**Total:** 3 working days

### Implementation Order

The tasks should be completed in this order to minimize risk and dependencies:

**Day 1 (Phase 1):**
1. Task 1.2: Rate limit bounds (low risk, no dependencies)
2. Task 1.3: Crypto caching (low risk, performance win)
3. Task 1.1: Configuration extraction (moderate risk, affects all)
4. Task 1.4: Error sanitization (breaking change, test thoroughly)

**Day 2-3 (Phase 2):**
1. Task 2.1: Test helpers (no risk, enables other tasks)
2. Task 2.2: Concurrent tests (may find bugs)
3. Task 2.3: I/O failure tests (may find bugs)
4. Task 2.4: Session limits (feature addition)
5. Task 2.5: Enhanced TOCTOU (security improvement)

---

**End of Feature Planning Document**
