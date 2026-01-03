# Phase 1: File Operations & Core Tools

This phase implements the foundational file system tools that form the basis of all code manipulation. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All file operation tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "read_file", "arguments": {"path": "x.ex"}} │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.read_file(path, session_id: id)              │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.read_file(path)"             │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_read_file/3 invoked from Lua                    │
│  (Elixir function registered as jido.read_file)             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Security.atomic_read(path, project_root)                   │
│  - Path boundary validation                                 │
│  - Symlink resolution                                       │
│  - TOCTOU-safe file read                                    │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Bridge Function | Purpose |
|------|-----------------|---------|
| read_file | `jido.read_file(path)` | Read file contents with line numbers |
| write_file | `jido.write_file(path, content)` | Create/overwrite files |
| edit_file | `jido.edit_file(path, old, new)` | Search/replace modifications |
| multi_edit | `jido.multi_edit(path, edits)` | Atomic batch modifications |
| list_dir | `jido.list_dir(path)` | Directory listing |
| glob_search | `jido.glob(pattern, path)` | Pattern-based file finding |
| delete_file | `jido.delete_file(path)` | File removal |

---

## 1.1 Read File Tool

Implement the read_file tool for reading file contents with line numbers, offset support, and sensible defaults. The tool executes through the Lua sandbox via the `jido.read_file` bridge function.

### 1.1.1 Tool Definition ✅

Create the read_file tool definition with proper schema. This defines the interface for the LLM.

- [x] 1.1.1.1 Create `lib/jido_code/tools/definitions/file_read.ex` with module documentation
- [x] 1.1.1.2 Define tool schema with parameters:
  ```elixir
  %{
    name: "read_file",
    description: "Read file contents. Returns line-numbered output.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "Path to file"},
      %{name: "offset", type: :integer, required: false, description: "Line to start from (1-indexed)"},
      %{name: "limit", type: :integer, required: false, description: "Max lines to read (default: 2000)"}
    ]
  }
  ```
- [x] 1.1.1.3 Set default limit to 2000 lines in schema
- [x] 1.1.1.4 Register tool in definitions module (via delegation from FileSystem module)

### 1.1.2 Bridge Function Implementation ✅

Implement the Bridge function that executes within the Lua sandbox. This is the actual implementation.

- [x] 1.1.2.1 Add `lua_read_file/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_read_file(args, state, project_root) do
    case args do
      [path] -> do_read_file(path, %{}, state, project_root)
      [path, opts] -> do_read_file(path, decode_opts(opts), state, project_root)
      _ -> {[nil, "read_file requires path argument"], state}
    end
  end
  ```
- [x] 1.1.2.2 Use `Security.atomic_read/2` for TOCTOU-safe file reading
- [x] 1.1.2.3 Implement offset/limit support (skip first N lines, cap at limit)
- [x] 1.1.2.4 Format output with line numbers (cat -n style, 1-indexed):
  ```
       1→first line
       2→second line
  ```
- [x] 1.1.2.5 Truncate long lines at 2000 characters with `[truncated]` indicator
- [x] 1.1.2.6 Detect binary files (check for null bytes) and reject with clear message
- [x] 1.1.2.7 Return `{[content], state}` on success or `{[nil, error_msg], state}` on failure
- [x] 1.1.2.8 Register function in `Bridge.register/2`:
  ```elixir
  |> register_function("read_file", &lua_read_file/3, project_root)
  ```

### 1.1.3 Manager API ✅

Expose the tool through the Manager API for session-aware execution.

- [x] 1.1.3.1 Add `read_file/2` to `Tools.Manager` that accepts path and options
- [x] 1.1.3.2 Support `session_id` option to route to session-scoped manager
- [x] 1.1.3.3 Call bridge function through Lua: `jido.read_file(path, opts)`

### 1.1.4 Unit Tests for Read File ✅

- [x] Test read_file through sandbox returns line-numbered content
- [x] Test read_file with offset skips initial lines
- [x] Test read_file with limit caps output
- [x] Test read_file truncates long lines with indicator
- [x] Test read_file rejects binary files with clear error
- [x] Test read_file rejects paths outside project boundary (Security layer)
- [x] Test read_file handles non-existent files
- [x] Test read_file handles permission errors
- [x] Test read_file works through session-scoped manager

---

## 1.2 Write File Tool

Implement the write_file tool for creating/overwriting files through the Lua sandbox.

### 1.2.1 Tool Definition

- [ ] 1.2.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_write.ex`
- [ ] 1.2.1.2 Define schema:
  ```elixir
  %{
    name: "write_file",
    description: "Write content to file. Creates parent directories if needed.",
    parameters: [
      %{name: "path", type: :string, required: true, description: "Path for file"},
      %{name: "content", type: :string, required: true, description: "Content to write"}
    ]
  }
  ```
- [ ] 1.2.1.3 Register tool in definitions module

### 1.2.2 Bridge Function Implementation

- [ ] 1.2.2.1 Update existing `lua_write_file/3` in `bridge.ex` if needed
- [ ] 1.2.2.2 Use `Security.atomic_write/3` for TOCTOU-safe writing
- [ ] 1.2.2.3 Validate content size (max 10MB)
- [ ] 1.2.2.4 Create parent directories via `jido.mkdir_p` if needed
- [ ] 1.2.2.5 Return `{[true], state}` on success or `{[nil, error], state}` on failure

### 1.2.3 Unit Tests for Write File

- [ ] Test write_file through sandbox creates new file
- [ ] Test write_file creates parent directories
- [ ] Test write_file rejects paths outside boundary
- [ ] Test write_file rejects content exceeding 10MB
- [ ] Test write_file handles permission errors
- [ ] Test write_file atomic behavior (no partial writes)

---

## 1.3 Edit File Tool

Implement the edit_file tool for surgical search/replace modifications through the Lua sandbox.

### 1.3.1 Tool Definition

- [ ] 1.3.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_edit.ex`
- [ ] 1.3.1.2 Define schema:
  ```elixir
  %{
    name: "edit_file",
    description: "Replace exact string in file. old_string must be unique.",
    parameters: [
      %{name: "path", type: :string, required: true},
      %{name: "old_string", type: :string, required: true, description: "Exact text to replace"},
      %{name: "new_string", type: :string, required: true, description: "Replacement text"},
      %{name: "replace_all", type: :boolean, required: false, description: "Replace all occurrences"}
    ]
  }
  ```

### 1.3.2 Bridge Function Implementation

- [ ] 1.3.2.1 Add `lua_edit_file/3` to `bridge.ex`
- [ ] 1.3.2.2 Use `Security.atomic_read/2` to read current content
- [ ] 1.3.2.3 Implement multi-strategy matching:
  1. Exact string match (primary)
  2. Line-trimmed match (fallback)
  3. Whitespace-normalized match (fallback)
  4. Indentation-flexible match (fallback)
- [ ] 1.3.2.4 Count occurrences - error if multiple and `replace_all` is false
- [ ] 1.3.2.5 Use `Security.atomic_write/3` to write modified content
- [ ] 1.3.2.6 Return `{[count], state}` with replacement count or `{[nil, error], state}`
- [ ] 1.3.2.7 Register in `Bridge.register/2`

### 1.3.3 Unit Tests for Edit File

- [ ] Test edit_file with exact match succeeds
- [ ] Test edit_file with whitespace variations uses fallback
- [ ] Test edit_file with indentation differences uses fallback
- [ ] Test edit_file fails on multiple matches (without replace_all)
- [ ] Test edit_file with replace_all replaces all occurrences
- [ ] Test edit_file fails on no match
- [ ] Test edit_file validates boundary through sandbox

---

## 1.4 Multi-Edit Tool

Implement the multi_edit tool for atomic batch modifications through the Lua sandbox.

### 1.4.1 Tool Definition ✅

- [x] 1.4.1.1 Create tool definition in `lib/jido_code/tools/definitions/file_multi_edit.ex`
- [x] 1.4.1.2 Define schema with edits array:
  ```elixir
  %{
    name: "multi_edit_file",
    description: "Apply multiple edits atomically. All succeed or all fail.",
    parameters: [
      %{name: "path", type: :string, required: true},
      %{name: "edits", type: :array, required: true, items: :object, description: "Array of {old_string, new_string}"}
    ]
  }
  ```
- [x] 1.4.1.3 Add `multi_edit_file()` to `FileSystem.all/0` via defdelegate
- [x] 1.4.1.4 Create comprehensive definition tests

### 1.4.2 Handler Implementation ✅

- [x] 1.4.2.1 Add `MultiEdit` inner module to `lib/jido_code/tools/handlers/file_system.ex`
- [x] 1.4.2.2 Implement read-before-write check via `check_read_before_edit/2`
- [x] 1.4.2.3 Validate all edits can be applied (all old_strings found and unique)
- [x] 1.4.2.4 Apply edits sequentially in memory using multi-strategy matching
- [x] 1.4.2.5 Write result via single `Security.atomic_write/4` call
- [x] 1.4.2.6 Track file write in session state via `FileSystem.track_file_write/3`
- [x] 1.4.2.7 Emit telemetry for `:multi_edit` operation
- [x] 1.4.2.8 Return `{:ok, message}` or `{:error, message}` with embedded edit index

### 1.4.3 Unit Tests for Multi-Edit ✅

- [x] Test multi_edit applies all edits atomically
- [x] Test multi_edit validates all edits before applying any
- [x] Test multi_edit preserves edit order (sequential application)
- [x] Test multi_edit returns failing edit index on error
- [x] Test multi_edit with session context (read-before-write)
- [x] Test multi_edit telemetry emission
- [x] Test multi_edit with various error conditions

---

## 1.5 List Directory Tool

Implement the list_dir tool for directory listing through the Lua sandbox.

### 1.5.1 Tool Definition ✅

- [x] 1.5.1.1 Create tool definition in `lib/jido_code/tools/definitions/list_dir.ex`
- [x] 1.5.1.2 Define schema:
  ```elixir
  %{
    name: "list_dir",
    description: "List directory contents with type indicators.",
    parameters: [
      %{name: "path", type: :string, required: true},
      %{name: "ignore_patterns", type: :array, required: false, description: "Glob patterns to ignore"}
    ]
  }
  ```
- [x] 1.5.1.3 Add `list_dir()` to `FileSystem.all/0` via defdelegate
- [x] 1.5.1.4 Create comprehensive definition tests (25 tests)
- [x] 1.5.1.5 Create ListDir handler with ignore_patterns support

### 1.5.2 Bridge Function Implementation ✅

- [x] 1.5.2.1 Update existing `lua_list_dir/3` in `bridge.ex` with options support
- [x] 1.5.2.2 Use `Security.validate_path/3` before listing
- [x] 1.5.2.3 Add file type indicators (directory vs file) - entries now return `{name, type}` tables
- [x] 1.5.2.4 Apply ignore patterns via `ignore_patterns` option with glob matching
- [x] 1.5.2.5 Sort entries (directories first, then alphabetically)
- [x] 1.5.2.6 Return as Lua array: `{[entries], state}` with typed entries
- [x] 1.5.2.7 Update bridge tests (12 tests for lua_list_dir)

### 1.5.3 Unit Tests for List Directory ✅

- [x] Test list_dir returns directory contents with type indicators
- [x] Test list_dir sorts directories first then alphabetically
- [x] Test list_dir applies ignore patterns (multiple patterns, wildcards)
- [x] Test list_dir validates boundary (path traversal rejection)
- [x] Test list_dir handles non-existent path
- [x] Test list_dir handles file path (not directory)
- [x] Test list_dir handles empty directory
- [x] Test list_dir handles subdirectory listing
- [x] Test list_dir handles missing path argument
- [x] 12 handler tests added to file_system_test.exs

---

## 1.6 Glob Search Tool

Implement the glob_search tool for pattern-based file finding through the Lua sandbox.

### 1.6.1 Tool Definition ✅

- [x] 1.6.1.1 Create tool definition in `lib/jido_code/tools/definitions/glob_search.ex`
- [x] 1.6.1.2 Define schema:
  ```elixir
  %{
    name: "glob_search",
    description: "Find files matching glob pattern (**, *, {a,b}).",
    parameters: [
      %{name: "pattern", type: :string, required: true, description: "Glob pattern"},
      %{name: "path", type: :string, required: false, description: "Base directory"}
    ]
  }
  ```
- [x] 1.6.1.3 Add `glob_search()` to `FileSystem.all/0` via defdelegate
- [x] 1.6.1.4 Create GlobSearch handler with Path.wildcard and mtime sorting
- [x] 1.6.1.5 Create comprehensive definition tests (26 tests)

### 1.6.2 Bridge Function Implementation ✅

- [x] 1.6.2.1 Add `lua_glob/3` to `bridge.ex`
- [x] 1.6.2.2 Use `Path.wildcard/2` for pattern matching
- [x] 1.6.2.3 Filter results through `Security.validate_path/3` (all must be within boundary)
- [x] 1.6.2.4 Sort by modification time (newest first)
- [x] 1.6.2.5 Return as Lua array of paths
- [x] 1.6.2.6 Register in `Bridge.register/2`
- [x] 1.6.2.7 Create 11 bridge tests for lua_glob

### 1.6.3 Unit Tests for Glob Search

- [x] Test glob_search with ** pattern through sandbox
- [x] Test glob_search with extension filter (*.ex)
- [x] Test glob_search with directory prefix
- [x] Test glob_search filters results within boundary
- [x] Test glob_search handles empty results
- [x] Test glob_search with brace expansion (*.{ex,exs})
- [x] Test glob_search with ? wildcard pattern
- [x] Test glob_search validates boundary rejects path traversal
- [x] Test glob_search returns error for missing pattern
- [x] Test glob_search returns error for non-existent base path
- [x] Test glob_search sorts by modification time newest first

### 1.6.4 Section 1.6 Review Fixes

Code review findings addressed:

- [x] Extract duplicated helpers to GlobMatcher module
  - `filter_within_boundary/2` with symlink validation
  - `sort_by_mtime_desc/1`
  - `make_relative/2`
- [x] Fix error atom `:file_not_found` → `:enoent` for consistency
- [x] Add symlink validation to `filter_within_boundary/2`
- [x] Document rescue clause with specific exception types
- [x] Make boolean in `with` statement idiomatic (`ensure_exists/1`)
- [x] Add missing test cases:
  - Character class `[abc]` patterns
  - Dot file exclusion
  - Symlinks pointing outside boundary
  - GlobMatcher helper function tests

---

## 1.7 Delete File Tool

Implement the delete_file tool for file removal through the Lua sandbox.

### 1.7.1 Tool Definition

- [ ] 1.7.1.1 Create tool definition in `lib/jido_code/tools/definitions/delete_file.ex`
- [ ] 1.7.1.2 Define schema:
  ```elixir
  %{
    name: "delete_file",
    description: "Delete a file (not directories).",
    parameters: [
      %{name: "path", type: :string, required: true, description: "Path to file"}
    ]
  }
  ```

### 1.7.2 Bridge Function Implementation

- [ ] 1.7.2.1 Update existing `lua_delete_file/3` in `bridge.ex` if needed
- [ ] 1.7.2.2 Use `Security.validate_path/3` before deletion
- [ ] 1.7.2.3 Verify target is a file (not directory)
- [ ] 1.7.2.4 Delete file with `File.rm/1`
- [ ] 1.7.2.5 Return `{[true], state}` or `{[nil, error], state}`

### 1.7.3 Unit Tests for Delete File

- [ ] Test delete_file removes existing file through sandbox
- [ ] Test delete_file fails for non-existent file
- [ ] Test delete_file fails for directories
- [ ] Test delete_file validates boundary
- [ ] Test delete_file handles permission errors

---

## 1.8 Phase 1 Integration Tests

Comprehensive integration tests verifying all Phase 1 tools work together through the Lua sandbox.

### 1.8.1 Sandbox Integration

Verify tools execute through the sandbox correctly.

- [ ] 1.8.1.1 Create `test/jido_code/integration/tools_phase1_test.exs`
- [ ] 1.8.1.2 Test: All tools execute through `Tools.Manager` → Lua → Bridge → Security chain
- [ ] 1.8.1.3 Test: Lua VM has dangerous functions removed (os.execute, io.popen unavailable)
- [ ] 1.8.1.4 Test: Session-scoped managers are isolated

### 1.8.2 File Lifecycle Integration

Test complete file lifecycle workflows through sandbox.

- [ ] 1.8.2.1 Test: write_file → read_file → edit_file → read_file verifies content
- [ ] 1.8.2.2 Test: write_file → multi_edit → read_file verifies all changes
- [ ] 1.8.2.3 Test: write_file → delete_file → read_file returns error
- [ ] 1.8.2.4 Test: Create multiple files → glob_search finds them
- [ ] 1.8.2.5 Test: mkdir_p → list_dir shows contents

### 1.8.3 Security Boundary Integration

Test security boundaries are enforced at both layers.

- [ ] 1.8.3.1 Test: All tools reject paths outside project boundary
- [ ] 1.8.3.2 Test: Symlinks resolved and validated
- [ ] 1.8.3.3 Test: Path traversal attempts blocked (../../etc/passwd)
- [ ] 1.8.3.4 Test: Direct Lua execution of os.execute fails (sandbox restriction)

---

## Phase 1 Success Criteria

1. **read_file**: Line-numbered content via `jido.read_file` bridge
2. **write_file**: Atomic writes via `jido.write_file` bridge
3. **edit_file**: Multi-strategy matching via `jido.edit_file` bridge
4. **multi_edit**: Atomic batch edits via `jido.multi_edit` bridge
5. **list_dir**: Directory listing via `jido.list_dir` bridge
6. **glob_search**: Pattern matching via `jido.glob` bridge
7. **delete_file**: File removal via `jido.delete_file` bridge
8. **All tools execute through Lua sandbox** (defense-in-depth)
9. **Test Coverage**: Minimum 80% for Phase 1 tools

---

## Phase 1 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add/update bridge functions
- `lib/jido_code/tools/manager.ex` - Expose tool APIs
- `lib/jido_code/tools/security.ex` - Ensure atomic operations exist

**New Files:**
- `lib/jido_code/tools/definitions/file_read.ex`
- `lib/jido_code/tools/definitions/file_write.ex`
- `lib/jido_code/tools/definitions/file_edit.ex`
- `lib/jido_code/tools/definitions/file_multi_edit.ex`
- `lib/jido_code/tools/definitions/list_dir.ex`
- `lib/jido_code/tools/definitions/glob_search.ex`
- `lib/jido_code/tools/definitions/delete_file.ex`
- `test/jido_code/tools/bridge_file_ops_test.exs`
- `test/jido_code/integration/tools_phase1_test.exs`
