# Feature Planning: Section 6.4 Review Fixes

**Feature ID:** ws-6.4.3
**Status:** Planning
**Priority:** High
**Created:** 2025-12-10
**Review Source:** notes/reviews/section-6.4-review.md

## Executive Summary

This feature addresses all blockers, high-priority concerns, and recommended improvements identified in the comprehensive 7-agent review of Section 6.4 (Session Persistence Load and Resume functionality). The implementation achieved an A grade overall but requires security enhancements and code quality improvements before full production deployment.

**Overall Assessment:** Production-ready code with 2 high-severity security issues requiring immediate attention, plus several medium and low-priority improvements.

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

The Section 6.4 review (parallel 7-agent analysis) identified the following issues across security, testing, and code quality dimensions:

#### High-Priority Issues (Must Address)

1. **[H2] Missing File Integrity Verification**
   - **Severity:** CVSS 7-8 (High)
   - **Location:** `lib/jido_code/session/persistence.ex:624-641` (load function)
   - **Impact:** Session files have no checksums or HMAC signatures, allowing attackers with filesystem access to tamper with persisted sessions
   - **Attack Vector:** Modify `~/.jido_code/sessions/{uuid}.json` to inject malicious data (project paths, configs, conversation history)
   - **Likelihood:** Medium (requires local filesystem access, but no detection mechanism)
   - **Current State:** Vulnerable

2. **[H1] TOCTOU Race Condition in Resume**
   - **Severity:** CVSS 7-8 (High)
   - **Location:** `lib/jido_code/session/persistence.ex:1017-1025` (resume function)
   - **Impact:** Time-of-check-time-of-use gap between validating project path (line 1019) and starting session processes (line 1021) allows session to start with invalid/malicious project directory
   - **Attack Vector:** Symlink swap or directory replacement between validation and session startup
   - **Likelihood:** Low (requires precise timing and local access)
   - **Current State:** Partial protection via ownership checks

3. **[Testing Gap] Missing File Size Validation**
   - **Severity:** High (DoS vulnerability)
   - **Location:** `lib/jido_code/session/persistence.ex:624` (load function)
   - **Impact:** `load/1` doesn't enforce the 10MB limit defined in `@max_session_file_size`, unlike `load_session_metadata/1` which does
   - **Attack Vector:** Create oversized session files to exhaust memory during load
   - **Likelihood:** Medium (easy to exploit)
   - **Current State:** Vulnerable in load function, protected in list_persisted

#### Medium-Priority Issues (Should Address)

4. **[M3] No Rate Limiting on Resume Operations**
   - **Impact:** Enables brute force attacks or DoS via repeated resume attempts
   - **Recommendation:** Add rate limiting (5 attempts/minute per session ID)

5. **[M2] Project Path Not Re-Validated After Deserialization**
   - **Impact:** Deserialized project path from JSON not validated against symlink/traversal checks
   - **Recommendation:** Add comprehensive path security validation to resume flow (currently only checks existence)

6. **[Code Quality] Duplicate deserialize_list Pattern**
   - **Location:** `deserialize_messages/1` (lines 875-886) and `deserialize_todos/1` (lines 907-918)
   - **Impact:** 24 lines of near-identical code with same structure
   - **Recommendation:** Extract `deserialize_list/2` helper function

7. **[Code Quality] Missing Test Helper Module**
   - **Location:** Across `persistence_test.exs` and `persistence_resume_test.exs`
   - **Impact:** 100+ lines of test helper duplication
   - **Recommendation:** Create `test/support/session_test_helpers.ex`

#### Low-Priority Improvements (Nice to Have)

8. **[Code Quality] Extract timestamp helper**
   - 4 call sites using `DateTime.utc_now() |> DateTime.to_iso8601()`
   - Recommendation: Extract `current_timestamp_iso8601/0`

9. **[Documentation] Add @spec to helpers**
   - 3/10 private helper functions lack `@spec`
   - Improves Dialyzer analysis

10. **[Observability] Add structured logging**
    - State transitions in resume flow lack logging
    - Recommendation: Add Logger calls for debugging

11. **[Documentation] Document idempotency**
    - Idempotency behavior not explicitly documented
    - Clarify what happens on duplicate resume attempts

### Impact Analysis

| Issue | Security Impact | User Impact | Maintenance Impact |
|-------|----------------|-------------|-------------------|
| H2: HMAC signatures | High - prevents tampering | None (transparent) | Low (one-time implementation) |
| H1: TOCTOU fix | High - prevents race attacks | None (transparent) | Low (validation reordering) |
| Testing: File size | High - prevents DoS | None (transparent) | Low (add validation) |
| M3: Rate limiting | Medium - prevents abuse | Low (errors on spam) | Medium (new rate limiter) |
| M2: Path validation | Medium - defense in depth | None (transparent) | Low (add validation) |
| Code quality issues | None | None | Medium (reduces tech debt) |

### Business Justification

**Why fix now:**
- H2 (HMAC) and H1 (TOCTOU) are high-severity security issues that could be exploited by local attackers
- File size validation gap creates DoS vulnerability
- Code quality improvements reduce future maintenance burden
- All issues are addressable in single focused effort (~2-3 days)

**Why not defer:**
- Security vulnerabilities should not ship to production
- Fixing post-release requires backward compatibility planning for HMAC signatures
- Test coverage gaps may hide future regressions

---

## Solution Overview

### High-Level Approach

The solution addresses issues in three phases:

1. **Phase 1: Security Enhancements** (Priority: Critical)
   - Add HMAC signature infrastructure for file integrity
   - Fix TOCTOU race condition with re-validation
   - Add file size validation to `load/1`

2. **Phase 2: Defense in Depth** (Priority: High)
   - Add rate limiting for resume operations
   - Re-validate project path after deserialization
   - Enhance path security validation

3. **Phase 3: Code Quality** (Priority: Medium)
   - Extract duplicate code patterns
   - Create test helper module
   - Add specs, logging, documentation

### Design Decisions

#### Decision 1: HMAC vs Digital Signatures

**Options Considered:**
1. HMAC-SHA256 with application secret key
2. RSA digital signatures with public/private keypair
3. Age encryption library (modern alternative)

**Selected:** HMAC-SHA256

**Rationale:**
- **Pro:** Simple implementation, fast performance, adequate for single-user CLI
- **Pro:** No key distribution needed (secret derived from application)
- **Pro:** Standard Erlang `:crypto` module support
- **Con:** Shared secret model (vs public/private key)
- **Con:** All sessions signed with same key (acceptable for single-user)

**Implementation Approach:**
- Derive signing key from mix project salt + hostname (deterministic but machine-specific)
- Add `signature` field to persisted session JSON
- Sign JSON payload (excluding signature field itself) with HMAC-SHA256
- Verify signature on load, reject tampered files
- Graceful migration: Accept unsigned files from v1.0.0, warn once, auto-sign on next save

**Alternative Considered:** Age encryption
- Modern, simple encryption library
- Adds external dependency
- Overkill for integrity verification (don't need confidentiality)
- Rejected due to added complexity vs HMAC

#### Decision 2: TOCTOU Fix Strategy

**Options Considered:**
1. Re-validate project path after session start
2. Use file locking on project directory
3. Validate inside atomic transaction

**Selected:** Re-validate after session start

**Rationale:**
- **Pro:** Simplest implementation, no external dependencies
- **Pro:** Catches both race conditions and validation errors
- **Pro:** Cleanup mechanism already exists (`restore_state_or_cleanup/2`)
- **Con:** Brief window where invalid session might start (acceptable, cleaned up immediately)
- **Con:** Wasted process startup on invalid path (rare case, acceptable cost)

**Implementation:**
- Add `revalidate_project_path/1` function
- Call from `restore_state_or_cleanup/2` before restore operations
- Includes full security checks (symlink, traversal, ownership)
- Leverage existing cleanup on failure pattern

**Alternative Rejected:** File locking
- Complex cross-platform implementation
- Risk of stale locks
- Doesn't prevent all attack vectors (attacker could hold lock)

#### Decision 3: Rate Limiting Architecture

**Options Considered:**
1. ETS-based rate limiter with sliding window
2. Hammer library (production-grade rate limiting)
3. Simple GenServer with exponential backoff

**Selected:** ETS-based sliding window

**Rationale:**
- **Pro:** No external dependencies
- **Pro:** Adequate for single-user CLI use case
- **Pro:** Lightweight, minimal overhead
- **Con:** Not production-grade for multi-tenant (but not needed)
- **Con:** Resets on application restart (acceptable)

**Implementation:**
- Create `JidoCode.RateLimit` module
- ETS table with `{operation_key, attempts, window_start}` tuples
- Sliding window: 5 attempts per 60 seconds per session_id
- Return `{:error, :rate_limit_exceeded}` with retry-after timestamp
- Automatic cleanup of old entries (> 5 minutes)

**Alternative Considered:** Hammer library
- Production-grade, battle-tested
- Adds dependency
- Overkill for CLI use case
- Rejected due to simplicity needs

#### Decision 4: Backward Compatibility for HMAC

**Strategy:** Graceful migration

**Implementation:**
- Version 1 files (pre-HMAC) accepted with warning
- Check for presence of `signature` field
- Log warning once: "Session file lacks signature, will be signed on next save"
- Auto-upgrade on next save operation
- Schema version remains 1 (backward compatible)

**Alternative Rejected:** Require re-generation
- Forces users to lose persisted sessions
- Poor user experience
- Unnecessary given graceful migration path

---

## Technical Design

### Architecture Changes

#### 1. HMAC Signature Infrastructure

**New Module:** `JidoCode.Session.Persistence.Crypto`

```elixir
defmodule JidoCode.Session.Persistence.Crypto do
  @moduledoc """
  Cryptographic operations for session file integrity.

  Uses HMAC-SHA256 to sign and verify session files, preventing
  tampering by attackers with filesystem access.
  """

  @doc """
  Signs a session map, returning map with `signature` field.
  """
  @spec sign_session(map()) :: map()
  def sign_session(session)

  @doc """
  Verifies a session signature, returns :ok or {:error, reason}.
  """
  @spec verify_signature(map()) :: :ok | {:error, :invalid_signature | :missing_signature}
  def verify_signature(session)

  @doc """
  Derives HMAC signing key from application salt and hostname.
  """
  @spec derive_signing_key() :: binary()
  defp derive_signing_key()

  @doc """
  Computes HMAC-SHA256 signature of session payload.
  """
  @spec compute_signature(map(), binary()) :: binary()
  defp compute_signature(session, key)
end
```

**Integration Points:**
- `write_session_file/2`: Sign before JSON encoding
- `load/1`: Verify signature after JSON decode
- Graceful fallback for unsigned v1 files

**File Format Change:**
```json
{
  "version": 1,
  "id": "...",
  "name": "...",
  // ... all existing fields ...
  "signature": "base64_encoded_hmac_sha256"
}
```

**Key Derivation:**
```elixir
defp derive_signing_key do
  app_salt = Application.get_env(:jido_code, :signing_salt, "jido_code_default_salt")
  hostname = :inet.gethostname() |> elem(1) |> to_string()
  :crypto.hash(:sha256, app_salt <> hostname)
end
```

**Security Properties:**
- Deterministic key per machine (survives app restart)
- Unique per hostname (prevents signature replay across machines)
- Uses standard Erlang `:crypto` module (no external deps)

#### 2. TOCTOU Race Condition Fix

**Changes to `restore_state_or_cleanup/2`:**

```elixir
defp restore_state_or_cleanup(session_id, persisted) do
  with :ok <- revalidate_project_path(persisted.project_path),
       :ok <- restore_conversation(session_id, persisted.conversation),
       :ok <- restore_todos(session_id, persisted.todos),
       :ok <- delete_persisted(session_id) do
    :ok
  else
    error ->
      alias JidoCode.SessionSupervisor
      SessionSupervisor.stop_session(session_id)
      error
  end
end
```

**New Function: `revalidate_project_path/1`**

```elixir
@spec revalidate_project_path(String.t()) :: :ok | {:error, atom()}
defp revalidate_project_path(path) do
  alias JidoCode.Tools.Security

  with :ok <- validate_project_path(path),
       :ok <- Security.validate_path_safe(path, File.cwd!()) do
    :ok
  end
end
```

**Validation Order:**
1. Basic validation (exists, is directory) - already done
2. **NEW:** Symlink safety check (Security.validate_symlink_safe/1)
3. **NEW:** Path traversal check (Security.validate_path_safe/2)
4. **NEW:** Re-validation after session start (catch TOCTOU)

**Error Flow:**
- Validation fails → Session stopped via existing cleanup → Error returned
- Window reduced to milliseconds (startup → revalidate)

#### 3. File Size Validation in load/1

**Simple Addition:**

```elixir
def load(session_id) when is_binary(session_id) do
  path = session_file(session_id)

  with {:ok, %{size: size}} <- File.stat(path),
       :ok <- validate_file_size(size, session_id),  # <-- ADD THIS
       {:ok, content} <- File.read(path),
       {:ok, data} <- Jason.decode(content),
       {:ok, session} <- deserialize_session(data) do
    {:ok, session}
  else
    {:error, :enoent} ->
      {:error, :not_found}
    {:error, %Jason.DecodeError{} = error} ->
      {:error, {:invalid_json, error}}
    {:error, reason} ->
      {:error, reason}
  end
end
```

**Reuse Existing Helper:**
- `validate_file_size/2` already exists (line 754-762)
- Returns `{:error, :file_too_large}` if > 10MB
- Logs warning with file size details

#### 4. Rate Limiting Infrastructure

**New Module:** `JidoCode.RateLimit`

```elixir
defmodule JidoCode.RateLimit do
  @moduledoc """
  Simple ETS-based rate limiting for session operations.

  Implements sliding window rate limiting to prevent abuse
  of expensive operations like session resume.
  """

  use GenServer

  @table_name :jido_code_rate_limits
  @default_limit 5
  @default_window_seconds 60

  @doc """
  Checks if operation is allowed under rate limit.
  Returns :ok or {:error, :rate_limit_exceeded, retry_after_seconds}.
  """
  @spec check_rate_limit(atom(), String.t()) ::
    :ok | {:error, :rate_limit_exceeded, pos_integer()}
  def check_rate_limit(operation, key)

  @doc """
  Records an attempt for rate limiting tracking.
  """
  @spec record_attempt(atom(), String.t()) :: :ok
  def record_attempt(operation, key)

  @doc """
  Resets rate limit for a key (useful for tests).
  """
  @spec reset(atom(), String.t()) :: :ok
  def reset(operation, key)

  # GenServer callbacks for periodic cleanup
  def init(_), do: {:ok, %{}}
  def handle_info(:cleanup, state)
end
```

**Integration:**

```elixir
def resume(session_id) when is_binary(session_id) do
  with :ok <- RateLimit.check_rate_limit(:resume, session_id),
       {:ok, persisted} <- load(session_id),
       # ... rest of resume logic ...
    do
    RateLimit.record_attempt(:resume, session_id)
    {:ok, session}
  end
end
```

**Rate Limit Configuration:**
- Operation: `:resume`
- Limit: 5 attempts
- Window: 60 seconds
- Key: session_id (prevent spam per session)

#### 5. Enhanced Project Path Validation

**New Validation in rebuild_session/1:**

```elixir
defp rebuild_session(persisted) do
  alias JidoCode.Session
  alias JidoCode.Tools.Security

  # Validate project path with full security checks
  with :ok <- Security.validate_path_safe(persisted.project_path, File.cwd!()),
       :ok <- validate_directory_ownership(persisted.project_path) do

    config = %{
      provider: Map.get(persisted.config, "provider"),
      # ... rest of config conversion ...
    }

    session = %Session{
      id: persisted.id,
      name: persisted.name,
      project_path: persisted.project_path,
      config: config,
      created_at: persisted.created_at,
      updated_at: DateTime.utc_now()
    }

    Session.validate(session)
  end
end
```

**Security Checks Applied:**
1. Path within allowed boundary (cwd)
2. No symlink escapes
3. No path traversal (../)
4. Directory ownership validation
5. Already running session check (existing)

#### 6. Code Quality Improvements

**Extract deserialize_list/2 Helper:**

```elixir
# Generalized list deserialization with fail-fast
defp deserialize_list(items, deserializer_fn, error_key) when is_list(items) do
  items
  |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
    case deserializer_fn.(item) do
      {:ok, deserialized} -> {:cont, {:ok, [deserialized | acc]}}
      {:error, reason} -> {:halt, {:error, {error_key, reason}}}
    end
  end)
  |> case do
    {:ok, items} -> {:ok, Enum.reverse(items)}
    error -> error
  end
end

defp deserialize_list(_, _, error_key), do: {:error, error_key}

# Usage
defp deserialize_messages(messages) do
  deserialize_list(messages, &deserialize_message/1, :invalid_message)
end

defp deserialize_todos(todos) do
  deserialize_list(todos, &deserialize_todo/1, :invalid_todo)
end
```

**Savings:** 24 lines reduced to ~8 lines + 15-line helper = net -1 lines but better maintainability

**Create test/support/session_test_helpers.ex:**

```elixir
defmodule JidoCode.SessionTestHelpers do
  @moduledoc """
  Shared test helpers for session persistence tests.
  """

  alias JidoCode.Session.Persistence

  @doc "Generates deterministic UUID v4 for testing"
  def test_uuid(index \\ 0)

  @doc "Creates persisted session map with defaults"
  def create_persisted_session(id, name, project_path, opts \\ [])

  @doc "Creates Session struct for testing"
  def create_test_session(id, name, project_path, opts \\ [])

  @doc "Cleans up all session files in sessions directory"
  def cleanup_all_sessions()

  @doc "Stops all running sessions and clears registry"
  def cleanup_active_sessions()
end
```

**Impact:** Eliminates 100+ lines of duplication across test files

---

## Implementation Plan

### Phase 1: Security Enhancements (Priority: Critical)

**Estimated Effort:** 1-1.5 days

#### Task 1.1: Add HMAC Signature Infrastructure

**Subtasks:**
1. Create `lib/jido_code/session/persistence/crypto.ex`
   - Implement `sign_session/1`
   - Implement `verify_signature/1`
   - Implement `derive_signing_key/0`
   - Implement `compute_signature/2`

2. Update `write_session_file/2` to sign sessions
   - Call `Crypto.sign_session/1` before JSON encode
   - Preserve all existing fields

3. Update `load/1` to verify signatures
   - Call `Crypto.verify_signature/1` after JSON decode
   - Implement graceful fallback for unsigned v1 files
   - Log warning on unsigned files (once per session)

4. Add configuration for signing salt
   - Add `:signing_salt` to `config/config.exs`
   - Generate secure default salt
   - Document in CLAUDE.md

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (lines 476-497, 624-641)
- `lib/jido_code/session/persistence/crypto.ex` (NEW)
- `config/config.exs` (add signing_salt)

**Tests Required:**
- Test signature generation and verification
- Test tampered file detection
- Test graceful handling of unsigned files
- Test cross-machine signature validation (should fail)
- Test signature with various payload sizes

**Success Criteria:**
- All tampered session files rejected
- Unsigned files accepted with warning
- No functional regression

#### Task 1.2: Fix TOCTOU Race Condition

**Subtasks:**
1. Create `revalidate_project_path/1` function
   - Full security validation suite
   - Symlink checks
   - Traversal checks
   - Ownership validation

2. Update `restore_state_or_cleanup/2`
   - Add revalidation as first step in with pipeline
   - Verify cleanup on validation failure

3. Update error messages
   - Add `:project_path_security_violation` error
   - Distinguish from initial validation errors

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (lines 1017-1089)

**Tests Required:**
- Test symlink attack prevention
- Test directory swap during resume
- Test cleanup on validation failure
- Test legitimate resume still works

**Success Criteria:**
- No TOCTOU vulnerability
- Cleanup occurs on validation failure
- All existing tests pass

#### Task 1.3: Add File Size Validation to load/1

**Subtasks:**
1. Add `File.stat/1` call to `load/1`
2. Add `validate_file_size/2` call
3. Add test for oversized file rejection

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (line 624)
- `test/jido_code/session/persistence_test.exs` (add test)

**Tests Required:**
- Test load fails for 11MB file
- Test load succeeds for 9MB file
- Test error message includes file size

**Success Criteria:**
- All oversized files rejected
- Error message informative
- No regression

### Phase 2: Defense in Depth (Priority: High)

**Estimated Effort:** 1 day

#### Task 2.1: Add Rate Limiting

**Subtasks:**
1. Create `lib/jido_code/rate_limit.ex` module
   - GenServer with ETS table
   - Sliding window implementation
   - Automatic cleanup

2. Integrate into `resume/1`
   - Check before load
   - Record attempt after success

3. Add configuration
   - Rate limit per operation
   - Configurable limits and windows

4. Add to application supervision tree
   - Start RateLimit GenServer

**Files Modified:**
- `lib/jido_code/rate_limit.ex` (NEW)
- `lib/jido_code/session/persistence.ex` (line 1017)
- `lib/jido_code/application.ex` (add to supervision tree)
- `config/config.exs` (add rate limit config)

**Tests Required:**
- Test rate limit enforcement
- Test reset after window expires
- Test different operations isolated
- Test cleanup of old entries

**Success Criteria:**
- 6th resume attempt in 60s fails
- Rate limit resets after window
- No false positives

#### Task 2.2: Re-validate Project Path After Deserialization

**Subtasks:**
1. Update `rebuild_session/1`
   - Add Security.validate_path_safe/2 call
   - Add ownership validation

2. Add comprehensive path security tests
   - Test symlink rejection
   - Test traversal rejection
   - Test ownership violation

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (lines 1043-1066)
- `test/jido_code/session/persistence_resume_test.exs` (add tests)

**Tests Required:**
- Test malicious path in persisted file rejected
- Test symlink in deserialized path rejected
- Test legitimate paths still work

**Success Criteria:**
- All insecure paths rejected
- Defense in depth achieved
- No false positives

### Phase 3: Code Quality (Priority: Medium)

**Estimated Effort:** 0.5 day

#### Task 3.1: Extract Duplicate Code

**Subtasks:**
1. Extract `deserialize_list/3` helper
2. Refactor `deserialize_messages/1` and `deserialize_todos/1`
3. Extract `current_timestamp_iso8601/0` helper
4. Add specs to remaining helper functions

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (lines 875-918)

**Tests Required:**
- Verify all existing tests still pass
- No functional changes

**Success Criteria:**
- Code reduction: ~24 lines saved
- No test failures
- Improved maintainability

#### Task 3.2: Create Test Helper Module

**Subtasks:**
1. Create `test/support/session_test_helpers.ex`
2. Extract common test helpers from both test files
3. Update test files to use helpers
4. Remove duplication

**Files Modified:**
- `test/support/session_test_helpers.ex` (NEW)
- `test/jido_code/session/persistence_test.exs` (refactor)
- `test/jido_code/session/persistence_resume_test.exs` (refactor)

**Tests Required:**
- All existing tests pass with helpers
- Helper functions tested independently

**Success Criteria:**
- 100+ lines of duplication removed
- Test clarity improved
- No test failures

#### Task 3.3: Documentation and Logging

**Subtasks:**
1. Add structured logging to resume flow
   - Log validation start/success/failure
   - Log restore steps
   - Log cleanup triggers

2. Document idempotency behavior
   - What happens on duplicate resume
   - File deletion semantics

3. Add missing @spec to helpers
   - `parse_datetime/1`
   - `format_datetime/1`
   - `sanitize_session_id/1`

**Files Modified:**
- `lib/jido_code/session/persistence.ex` (add Logger calls, @spec)

**Tests Required:**
- No functional tests needed
- Verify Dialyzer passes

**Success Criteria:**
- All helpers have @spec
- Key operations logged
- Idempotency documented

### Phase 4: Testing and Validation

**Estimated Effort:** 0.5 day

#### Task 4.1: Comprehensive Test Suite

**New Tests Required:**

1. **HMAC Signature Tests** (10 tests)
   - Valid signature passes
   - Invalid signature fails
   - Tampered content detected
   - Missing signature handled gracefully
   - Unsigned v1 file accepted with warning
   - Signature verification performance
   - Cross-machine signature fails
   - Large payload signature
   - Empty payload signature
   - Malformed signature field

2. **TOCTOU Tests** (5 tests)
   - Symlink swap attack prevented
   - Directory deletion during resume
   - Ownership change during resume
   - Revalidation success path
   - Cleanup on revalidation failure

3. **Rate Limit Tests** (8 tests)
   - 5 attempts succeed
   - 6th attempt fails
   - Window expiration resets
   - Different sessions independent
   - Different operations independent
   - Cleanup removes old entries
   - Reset function works
   - Concurrent access safe

4. **File Size Tests** (3 tests)
   - Load rejects 11MB file
   - Load accepts 9MB file
   - Error message includes size

5. **Path Validation Tests** (6 tests)
   - Symlink in deserialized path rejected
   - Traversal in deserialized path rejected
   - Malicious path in JSON rejected
   - Ownership violation rejected
   - Legitimate complex paths accepted
   - Revalidation after session start

**Test Files:**
- `test/jido_code/session/persistence/crypto_test.exs` (NEW)
- `test/jido_code/rate_limit_test.exs` (NEW)
- `test/jido_code/session/persistence_test.exs` (additions)
- `test/jido_code/session/persistence_resume_test.exs` (additions)

**Total New Tests:** 32 tests

#### Task 4.2: Security Audit

**Manual Testing:**
1. Attempt to tamper with session file (should fail)
2. Attempt symlink attack (should fail)
3. Attempt rate limit bypass (should fail)
4. Verify DoS protection (should reject large files)
5. Verify graceful migration from unsigned files

**Automated Security Tests:**
- Run all new security tests
- Verify all tests pass
- Check test coverage (target: 90%+)

#### Task 4.3: Integration Testing

**End-to-End Scenarios:**
1. Save → Load → Verify signature
2. Resume with all fixes applied
3. Upgrade from unsigned to signed
4. Rate limit enforcement during rapid resume
5. Large session (near limit) handling

**Performance Testing:**
- Signature overhead: < 5ms per operation
- Rate limit overhead: < 1ms per check
- No regression in load/resume times

---

## Testing Strategy

### Test Coverage Goals

| Component | Current Coverage | Target Coverage | New Tests |
|-----------|-----------------|-----------------|-----------|
| HMAC Crypto | N/A (new) | 95% | 10 tests |
| Rate Limiter | N/A (new) | 90% | 8 tests |
| Load function | 90% | 95% | 3 tests |
| Resume function | 85% | 95% | 11 tests |
| Validation | 95% | 98% | 6 tests |

**Total New Tests:** 32 tests
**Total Existing Tests:** 28 tests for Section 6.4
**New Total:** 60 tests for persistence module

### Test Organization

```
test/jido_code/session/
├── persistence_test.exs                 # Schema, save, load, list (16 tests + 3 new)
├── persistence_resume_test.exs          # Resume flow (12 tests + 11 new)
├── persistence_crypto_test.exs          # NEW: HMAC signatures (10 tests)
└── persistence_security_test.exs        # NEW: Security validations (6 tests)

test/jido_code/
├── rate_limit_test.exs                  # NEW: Rate limiting (8 tests)

test/support/
└── session_test_helpers.ex              # NEW: Shared test helpers
```

### Critical Test Cases

#### 1. HMAC Tampering Detection

```elixir
test "detects tampered session content" do
  # Save session with signature
  session_id = test_uuid(0)
  session = create_persisted_session(session_id, "Test", "/tmp")
  :ok = Persistence.write_session_file(session_id, session)

  # Tamper with file
  path = Persistence.session_file(session_id)
  {:ok, content} = File.read(path)
  {:ok, data} = Jason.decode(content)
  tampered = %{data | "name" => "Hacked"}
  File.write!(path, Jason.encode!(tampered))

  # Load should fail
  assert {:error, :invalid_signature} = Persistence.load(session_id)
end
```

#### 2. TOCTOU Race Condition

```elixir
test "prevents symlink swap during resume" do
  session_id = test_uuid(0)
  real_dir = "/tmp/real"
  symlink = "/tmp/link"
  File.mkdir_p!(real_dir)

  # Create persisted session pointing to real dir
  persisted = create_persisted_session(session_id, "Test", real_dir)
  :ok = Persistence.write_session_file(session_id, persisted)

  # Simulate race: replace with symlink after validation
  # (In practice, revalidation catches this)

  # Resume should detect and fail
  assert {:error, _} = Persistence.resume(session_id)
end
```

#### 3. Rate Limit Enforcement

```elixir
test "enforces rate limit on resume operations" do
  session_id = test_uuid(0)
  persisted = create_persisted_session(session_id, "Test", tmp_dir)

  # Attempt 1-5: should succeed
  for _ <- 1..5 do
    :ok = Persistence.write_session_file(session_id, persisted)
    assert {:ok, _} = Persistence.resume(session_id)
    SessionSupervisor.stop_session(session_id)
    :ok = Persistence.write_session_file(session_id, persisted)
  end

  # Attempt 6: should fail with rate limit
  assert {:error, :rate_limit_exceeded, retry_after} = Persistence.resume(session_id)
  assert retry_after > 0
end
```

### Testing Tools

- **ExUnit:** Primary test framework
- **Bypass:** HTTP mocking (if needed for future web integrations)
- **Mox:** Mocking (for RateLimit tests with time control)
- **Dialyzer:** Static analysis for type correctness
- **Credo:** Code quality checks

### Regression Testing

All existing 28 tests must pass without modification (except for signature warnings on unsigned files).

**Regression Test Plan:**
1. Run full test suite before changes
2. Run after each subtask
3. Fix any failures immediately
4. Track coverage changes

---

## Success Criteria

### Functional Requirements

- [ ] All session files signed with HMAC-SHA256
- [ ] Tampered files rejected on load
- [ ] TOCTOU race condition eliminated
- [ ] File size validation enforced in load/1
- [ ] Rate limiting prevents abuse (5/min)
- [ ] Project path re-validated after deserialization
- [ ] All security checks passing

### Non-Functional Requirements

- [ ] No performance regression (< 5ms overhead)
- [ ] Graceful migration from unsigned files
- [ ] All existing tests pass
- [ ] 32+ new tests added
- [ ] Test coverage > 90% for new code
- [ ] Dialyzer passes with no warnings
- [ ] Credo passes with no issues

### Code Quality Requirements

- [ ] deserialize_list/3 helper extracted
- [ ] Test helper module created
- [ ] 100+ lines of duplication removed
- [ ] All helpers have @spec
- [ ] Structured logging added
- [ ] Idempotency documented

### Documentation Requirements

- [ ] CLAUDE.md updated with security model
- [ ] HMAC signature process documented
- [ ] Rate limiting configuration documented
- [ ] Migration guide for unsigned files
- [ ] Security audit results documented

### Security Validation

- [ ] Manual tampering attempt blocked
- [ ] Symlink attack prevented
- [ ] Rate limit bypass attempt blocked
- [ ] DoS via large file prevented
- [ ] No new vulnerabilities introduced

---

## Risk Analysis

### Technical Risks

#### Risk 1: HMAC Key Management

**Description:** Signing key derivation might be too simplistic

**Likelihood:** Low
**Impact:** Medium (key predictability)
**Mitigation:**
- Use strong salt configured per installation
- Include hostname in key derivation
- Consider future enhancement to user-configurable key
- Document key derivation in security audit

**Contingency:**
- Phase 2 could add encrypted key storage
- Could migrate to Age encryption library if needed

#### Risk 2: Rate Limiter State Loss

**Description:** ETS table resets on app restart, rate limits don't persist

**Likelihood:** High (normal behavior)
**Impact:** Low (acceptable for CLI)
**Mitigation:**
- Document behavior
- Rate limits are per-session-id (stateless key)
- Short window (60s) means quick reset anyway

**Contingency:**
- If abuse detected, could persist to DETS
- Could add exponential backoff on repeated failures

#### Risk 3: Backward Compatibility

**Description:** Unsigned files might cause confusion

**Likelihood:** Medium
**Impact:** Low (graceful fallback)
**Mitigation:**
- Clear warning message
- Auto-upgrade on next save
- Document migration process

**Contingency:**
- Could add `--force-resign` CLI command
- Could auto-sign all files on app startup

### Process Risks

#### Risk 4: Implementation Time Underestimate

**Description:** 3-day estimate might be optimistic

**Likelihood:** Medium
**Impact:** Medium (schedule slip)
**Mitigation:**
- Break into small, testable increments
- Prioritize high-severity fixes first
- Code quality improvements deferrable

**Contingency:**
- Ship Phase 1 (security) first
- Defer Phase 3 (code quality) if needed

#### Risk 5: Test Coverage Gaps

**Description:** New tests might miss edge cases

**Likelihood:** Low
**Impact:** High (security bypass)
**Mitigation:**
- Comprehensive test plan (32 tests)
- Security-focused test cases
- Manual security audit
- Code review by security-expert

**Contingency:**
- Add tests retroactively if issues found
- Bug bounty mindset: reward finding gaps

### Dependencies

**Internal Dependencies:**
- `JidoCode.Tools.Security` module (already exists)
- `JidoCode.Session.State` module (already exists)
- `JidoCode.SessionSupervisor` module (already exists)

**External Dependencies:**
- None (all Erlang stdlib)

**Dependency Risks:**
- None identified (no new external deps)

---

## Appendix A: Consultation Summary

### Security Expert Consultation (HMAC Approach)

**Question:** What's the best approach for session file integrity verification?

**Recommendation:**
- HMAC-SHA256 adequate for single-user CLI
- Key derivation: app salt + hostname
- Graceful migration from unsigned files
- Consider Age encryption for future multi-user

**Rationale:**
- No confidentiality needed (session files not sensitive)
- Integrity verification sufficient
- HMAC simpler than public/private key crypto
- Standard library support (no deps)

### Elixir Expert Consultation (Rate Limiting Patterns)

**Question:** Best rate limiting approach for Elixir CLI?

**Recommendation:**
- ETS-based sliding window
- GenServer for management and cleanup
- Per-operation and per-key granularity
- Avoid external deps (Hammer overkill)

**Pattern:**
```elixir
# Sliding window with automatic cleanup
{key, attempts_list, window_start} = :ets.lookup(@table, key)
recent_attempts = Enum.filter(attempts_list, &within_window?/1)
if length(recent_attempts) < @limit, do: :ok, else: {:error, :rate_limit_exceeded}
```

### Senior Engineer Consultation (TOCTOU Fix)

**Question:** How to eliminate TOCTOU race in resume operation?

**Recommendation:**
- Re-validate after session start (simplest)
- Use existing cleanup-on-failure pattern
- Full security validation suite (symlink, traversal, ownership)
- Acceptable brief window (caught immediately)

**Alternative Considered:**
- File locking: Complex, platform-specific, doesn't prevent all attacks
- Atomic validation: Not possible across process boundaries

**Selected Approach:** Re-validation with cleanup

---

## Appendix B: File Locations Reference

### Implementation Files

| File | Lines | Changes |
|------|-------|---------|
| `lib/jido_code/session/persistence.ex` | 624-641, 1017-1089 | Add signature verify, revalidation, file size check |
| `lib/jido_code/session/persistence/crypto.ex` | NEW | HMAC signature implementation |
| `lib/jido_code/rate_limit.ex` | NEW | Rate limiting GenServer |
| `lib/jido_code/application.ex` | - | Add RateLimit to supervision tree |

### Test Files

| File | Changes |
|------|---------|
| `test/jido_code/session/persistence_test.exs` | Add 3 file size tests |
| `test/jido_code/session/persistence_resume_test.exs` | Add 11 security tests |
| `test/jido_code/session/persistence_crypto_test.exs` | NEW: 10 signature tests |
| `test/jido_code/session/persistence_security_test.exs` | NEW: 6 validation tests |
| `test/jido_code/rate_limit_test.exs` | NEW: 8 rate limit tests |
| `test/support/session_test_helpers.ex` | NEW: Shared helpers |

### Configuration Files

| File | Changes |
|------|---------|
| `config/config.exs` | Add signing_salt, rate_limit config |

### Documentation Files

| File | Changes |
|------|---------|
| `CLAUDE.md` | Document security model, HMAC process |
| `notes/features/ws-6.4.3-review-fixes.md` | This document |
| `notes/reviews/section-6.4-review.md` | Reference document |

---

## Appendix C: Dependencies and Requirements

### Elixir Dependencies (No Changes)

All functionality uses Erlang stdlib:
- `:crypto` - HMAC-SHA256 (already available)
- `:ets` - Rate limit storage (already available)
- `Jason` - JSON encoding (already in deps)
- `File`, `Path` - File operations (stdlib)

### Configuration Requirements

**New Configuration in config/config.exs:**

```elixir
config :jido_code, :persistence,
  signing_salt: System.get_env("JIDO_CODE_SIGNING_SALT", "jido_code_default_salt_change_me"),
  max_session_file_size: 10 * 1024 * 1024  # 10MB (already exists)

config :jido_code, :rate_limit,
  resume_limit: 5,
  resume_window_seconds: 60,
  cleanup_interval_seconds: 300
```

**Environment Variables (Optional):**
- `JIDO_CODE_SIGNING_SALT` - Custom signing salt (security enhancement)

---

## Appendix D: Migration and Rollback

### Migration Strategy

**Phase 1: Graceful Introduction (v1.1.0)**
- Add signature support
- Accept unsigned files with warning
- Auto-sign on next save
- No breaking changes

**Phase 2: Deprecation Notice (v1.2.0)**
- Warn on unsigned files
- Recommend re-signing
- Still accept unsigned

**Phase 3: Enforce Signatures (v2.0.0)**
- Reject unsigned files
- Major version bump (breaking change)
- Provide migration tool

### Rollback Plan

**If Issues Found Post-Deployment:**

1. **Disable Signature Verification:**
   - Add config flag: `verify_signatures: false`
   - Rollback to accept all files
   - Investigate issue

2. **Disable Rate Limiting:**
   - Add config flag: `enable_rate_limit: false`
   - Remove from resume flow
   - Investigate performance impact

3. **Full Rollback:**
   - Revert to commit before changes
   - Keep signed files (forward compatible)
   - Unsigned files still work

**Rollback Testing:**
- Test signed files work without verification
- Test unsigned files continue working
- No data loss on rollback

---

## Appendix E: Timeline and Milestones

### Detailed Timeline

**Week 1: Security Enhancements**

**Day 1:**
- [ ] Morning: Implement HMAC crypto module (4h)
- [ ] Afternoon: Integrate signature generation (2h)
- [ ] Evening: Write crypto tests (2h)

**Day 2:**
- [ ] Morning: Implement signature verification (2h)
- [ ] Morning: Add graceful unsigned file handling (2h)
- [ ] Afternoon: Fix TOCTOU with revalidation (3h)
- [ ] Evening: Add file size validation (1h)

**Day 3:**
- [ ] Morning: Implement rate limiter (4h)
- [ ] Afternoon: Integrate rate limiting (2h)
- [ ] Evening: Write rate limit tests (2h)

**Day 4:**
- [ ] Morning: Add path re-validation (2h)
- [ ] Afternoon: Extract duplicate code (3h)
- [ ] Evening: Create test helpers (3h)

**Day 5:**
- [ ] Morning: Add logging and documentation (3h)
- [ ] Afternoon: Run full test suite (2h)
- [ ] Evening: Security audit and fixes (3h)

### Milestones

- **M1:** HMAC signatures working (Day 1 EOD)
- **M2:** All high-priority fixes complete (Day 2 EOD)
- **M3:** Rate limiting and path validation done (Day 3 EOD)
- **M4:** Code quality improvements complete (Day 4 EOD)
- **M5:** All tests passing, ready for review (Day 5 EOD)

### Definition of Done

- [ ] All code changes implemented
- [ ] All 32 new tests passing
- [ ] All existing tests passing (no regression)
- [ ] Test coverage > 90%
- [ ] Dialyzer passing
- [ ] Credo passing
- [ ] Documentation updated
- [ ] Security audit completed
- [ ] Code review approved
- [ ] PR merged to main branch

---

## Document Metadata

**Author:** Feature Planning Agent
**Date Created:** 2025-12-10
**Last Updated:** 2025-12-10
**Version:** 1.0
**Status:** Planning Complete - Ready for Implementation
**Reviewers:** security-expert, elixir-expert, senior-engineer-reviewer
**Related Documents:**
- `notes/reviews/section-6.4-review.md` (source review)
- `notes/features/ws-6.4.1-load-persisted-session.md` (original feature)
- `notes/features/ws-6.4.2-resume-session.md` (original feature)
- `CLAUDE.md` (project documentation)

**Change Log:**
- 2025-12-10: Initial comprehensive planning document created
