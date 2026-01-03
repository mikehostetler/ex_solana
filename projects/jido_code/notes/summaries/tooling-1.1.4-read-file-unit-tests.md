# Task 1.1.4: Read File Unit Tests

**Status**: Complete
**Branch**: `feature/1.1.4-read-file-permission-test`
**Plan Reference**: `notes/planning/tooling/phase-01-tools.md` - Section 1.1.3

## Summary

Completed the remaining unit test for read_file: permission error handling. Most tests for task 1.1.4 were already implemented as part of task 1.1.3 (Manager API).

## Test Coverage Summary

All 8 test cases from task 1.1.4 are now covered:

| Test Case | Status | Location |
|-----------|--------|----------|
| Read with valid path returns line-numbered content | Done (1.1.2) | `bridge_test.exs`, `manager_test.exs` |
| Read with offset skips initial lines | Done (1.1.3) | `manager_test.exs` |
| Read with limit caps output | Done (1.1.3) | `manager_test.exs` |
| Read truncates long lines | Done (1.1.2) | `bridge_test.exs` |
| Read rejects binary files | Done (1.1.2) | `bridge_test.exs` |
| Read rejects paths outside project boundary | Done (1.1.2) | `bridge_test.exs`, `manager_test.exs` |
| Read handles non-existent files | Done (1.1.2) | `bridge_test.exs`, `manager_test.exs` |
| Read handles permission errors | Done (1.1.4) | `bridge_test.exs`, `manager_test.exs` |

## Changes Made

### Modified Test Files

1. **`test/jido_code/tools/bridge_test.exs`**
   - Added permission error test for `lua_read_file`
   - Uses `File.chmod!/2` to create unreadable file
   - Verifies error message contains "permission", "eacces", or "denied"

2. **`test/jido_code/session/manager_test.exs`**
   - Added permission error test for `Manager.read_file/2`
   - Tests full stack from Manager → Lua → Bridge → Security
   - Ensures permissions are restored after test for cleanup

## Test Results

```
69 bridge tests, 0 failures
38 session manager tests, 0 failures
```

## Implementation Notes

The permission error test pattern:

```elixir
# Create file and remove read permissions
file_path = Path.join(tmp_dir, "no_read.txt")
File.write!(file_path, "secret")
File.chmod!(file_path, 0o200)  # write-only

# Attempt read - should fail
{:error, msg} = Manager.read_file(session.id, "no_read.txt")

# Restore permissions for cleanup
File.chmod!(file_path, 0o644)

# Verify error message
assert msg =~ "permission" or msg =~ "eacces" or msg =~ "denied"
```

## Next Steps

Task 1.2: Write File Tool
- Create write_file tool definition
- Implement handler with atomic writes
- Add content size validation (max 10MB)
- Implement read-before-write requirement for existing files
