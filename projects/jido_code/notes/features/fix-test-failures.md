# Fix All Remaining Test Failures

**Status**: 🚧 In Progress
**Branch**: `feature/fix-test-failures`
**Created**: 2025-12-12

---

## Problem Statement

The JidoCode test suite has **302 failing tests out of 2508 total tests** (11.6% failure rate). Analysis reveals these failures fall into 5 systematic categories:

1. **Model Configuration Issues** (~85 failures, 28%) - Tests using outdated model name `"claude-3-5-sonnet"`
2. **Process/GenServer Not Started** (~131 failures, 43%) - Tests calling GenServers that aren't running
3. **Pattern Match Failures** (~58 failures, 19%) - Tests expecting wrong return value from `cleanup/1`
4. **Unknown Registry Errors** (~24 failures, 8%) - Tests referencing registries not started
5. **Other Errors** (~4 failures, 1%) - Miscellaneous issues

These are **test infrastructure issues**, not bugs in the application code. The application is production-ready; the tests need systematic cleanup.

---

## Solution Overview

Fix test failures through 5 systematic phases:

### Phase 1: Model Name Cleanup (2 hours)
Replace `"claude-3-5-sonnet"` with valid `"claude-3-5-haiku-20241022"` across test files.

### Phase 2: Fix cleanup/1 Return Value (30 minutes)
Update pattern matching to handle `{:ok, result}` return value from `Persistence.cleanup/1`.

### Phase 3: Infrastructure Setup (4-6 hours)
Add proper test setup to ensure GenServers and Registries are started.

### Phase 4: Registry-Specific Fixes (1 hour)
Address any remaining registry lookup failures.

### Phase 5: Final Cleanup (1-2 hours)
Fix remaining miscellaneous errors.

**Total Estimated Effort**: 9-12 hours

---

## Implementation Plan

### Phase 1: Model Name Cleanup ✅ COMPLETE

**Goal**: Fix 85 model configuration failures

**Steps**:
1. ✅ Find all occurrences of `"claude-3-5-sonnet"` in test files
2. ✅ Replace with `"claude-3-5-haiku-20241022"`
3. ✅ Run affected test files to verify
4. ✅ Commit changes

**Files Updated**:
- `test/jido_code/config_test.exs`
- `test/jido_code/commands_test.exs`
- `test/jido_code/settings_test.exs`
- `test/jido_code/tui_test.exs`
- `test/jido_code/help_text_test.exs`
- `test/jido_code/tui/pubsub_bridge_test.exs`

**Results**:
- Failures reduced from 302 to ~217
- All model validation errors eliminated

---

### Phase 2: Fix cleanup/1 Return Value ⏸️ PENDING

**Goal**: Fix 58 pattern match failures in cleanup tests

**Issue**: `Persistence.cleanup/1` returns `{:ok, result}` but tests expect bare `result`

**File to Update**:
- `test/jido_code/session/persistence_cleanup_test.exs`

**Pattern**:
```elixir
# Before:
result = Persistence.cleanup(30)
assert result.deleted == 1

# After:
{:ok, result} = Persistence.cleanup(30)
assert result.deleted == 1
```

**Verification**:
```bash
mix test test/jido_code/session/persistence_cleanup_test.exs
```

---

### Phase 3: Infrastructure Setup ⏸️ PENDING

**Goal**: Fix 131 GenServer/Process failures

**Root Cause**: Tests calling functions that need running GenServers without proper setup

**Approach**:

1. **Global Application Start** - Add to `test/test_helper.exs`:
   ```elixir
   {:ok, _} = Application.ensure_all_started(:jido_code)
   ExUnit.start(exclude: [:llm])
   ```

2. **Per-Test Setup** - Use existing helpers from `SessionTestHelpers`:
   ```elixir
   setup do
     JidoCode.Test.SessionTestHelpers.setup_session_supervisor()
   end
   ```

3. **Async Settings** - Change tests using shared resources to `async: false`

**Test Files Needing Updates**:
- Tool tests (`test/jido_code/tools/**/*_test.exs`)
- Integration tests (`test/jido_code/integration/**/*_test.exs`)
- Session tests needing SessionSupervisor

**Verification**:
```bash
mix test test/jido_code/tools/
mix test test/jido_code/integration/
```

---

### Phase 4: Registry-Specific Fixes ⏸️ PENDING

**Goal**: Fix 24 registry lookup failures

**Registries Needed**:
- `JidoCode.SessionProcessRegistry`
- `Phoenix.PubSub` (JidoCode.PubSub)
- `JidoCode.AgentRegistry`

**Approach**: Ensure Application.start initializes all registries (likely resolved by Phase 3)

---

### Phase 5: Final Cleanup ⏸️ PENDING

**Goal**: Fix remaining ~4 miscellaneous errors

**Approach**: Investigate individually and apply targeted fixes

---

## Success Criteria

- ✅ Zero test failures (excluding LLM-tagged tests)
- ✅ No "Model not found" errors
- ✅ No "no process" errors
- ✅ No registry lookup errors
- ✅ All cleanup tests passing
- ✅ Test suite runs in < 15 seconds

**Target**: 2508 tests, 0 failures (excluding 90 LLM-tagged tests)

---

## Progress Tracking

| Phase | Status | Tests Fixed | Time Spent |
|-------|--------|-------------|------------|
| Phase 1: Model Names | ✅ Complete | 85 | 2h |
| Phase 2: cleanup/1 | ⏸️ Pending | 58 | - |
| Phase 3: Infrastructure | ⏸️ Pending | 131 | - |
| Phase 4: Registry | ⏸️ Pending | 24 | - |
| Phase 5: Misc | ⏸️ Pending | 4 | - |
| **TOTAL** | **28% Complete** | **85/302** | **2h/12h** |

---

## Current Status

**Last Updated**: 2025-12-12 10:15 EST

**What Works**:
- ✅ Phase 1 complete - all model configuration errors fixed
- ✅ Test suite compiles successfully
- ✅ 85 fewer failures (302 → 217)

**What's Next**:
- Start Phase 2: Fix cleanup/1 pattern matching (30 min, easy win)
- Then Phase 3: Infrastructure setup (main effort)

**How to Run**:
```bash
# Check current status
git status
git log --oneline -5

# Run tests
mix test                          # Full suite
mix test --only llm              # LLM tests (requires API key)
mix test --exclude llm           # Non-LLM tests

# Check failure count
mix test 2>&1 | tail -1
```

---

## Risk Assessment

**Overall Risk**: LOW-MEDIUM

- **Phase 1**: ✅ LOW (complete, mechanical changes)
- **Phase 2**: LOW (simple pattern matching)
- **Phase 3**: MEDIUM (async changes may expose race conditions)
- **Phase 4**: LOW (likely fixed by Phase 3)
- **Phase 5**: LOW (small number of issues)

---

## Notes

### Design Decisions

1. **Model Name Strategy**: Use valid production model names in tests, not mocks
2. **cleanup/1 Return**: Tests match API (returns `{:ok, result}`), not vice versa
3. **Infrastructure**: Global Application.start more reliable than per-test mocking
4. **Async Settings**: Explicit `async: false` better than flaky tests

### Future Improvements

- Add compile-time model validation
- Create test performance benchmarks
- Document test infrastructure requirements
- Consider test categorization by infrastructure needs
