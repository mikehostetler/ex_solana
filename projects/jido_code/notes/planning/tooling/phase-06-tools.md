# Phase 6: Testing & Polish

This final phase focuses on comprehensive integration testing, advanced search tools (if time permits), documentation, and performance optimization. All tests verify that tools work correctly through the Lua sandbox per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Goals in This Phase

| Goal | Priority |
|------|----------|
| Comprehensive integration tests (sandbox verification) | Critical |
| Cross-session isolation tests | Critical |
| Concurrent execution tests | Critical |
| Codebase search (embeddings) | Optional |
| Repository map (AST) | Optional |
| Tool reference documentation | Required |
| Security model documentation | Required |
| Performance optimization | Required |

---

## 6.1 Comprehensive Integration Tests

End-to-end tests verifying complete tool chains work together correctly through the Lua sandbox.

### 6.1.1 Full Tool Chain Tests

Test realistic workflows using multiple tools through the sandbox.

- [ ] 6.1.1.1 Create `test/jido_code/integration/full_workflow_test.exs`
- [ ] 6.1.1.2 Test: File creation workflow through sandbox
  ```
  glob_search (jido.glob) ->
  read_file (jido.read_file) ->
  write_file (jido.write_file) ->
  edit_file (jido.edit_file) ->
  grep_search (jido.grep) ->
  git_command (jido.git)
  ```
- [ ] 6.1.1.3 Test: Bug fix workflow through sandbox
  ```
  grep_search (jido.grep) ->
  read_file (jido.read_file) ->
  edit_file (jido.edit_file) ->
  run_exunit (jido.exunit) ->
  git_command (jido.git)
  ```
- [ ] 6.1.1.4 Test: Refactoring workflow through sandbox
  ```
  find_references (jido.lsp_references) ->
  multi_edit (jido.multi_edit) ->
  get_diagnostics (jido.lsp_diagnostics) ->
  run_exunit (jido.exunit)
  ```
- [ ] 6.1.1.5 Test: Documentation workflow through sandbox
  ```
  fetch_elixir_docs (jido.docs) ->
  read_file (jido.read_file) ->
  edit_file (jido.edit_file) ->
  mix_task (jido.mix_task format)
  ```

### 6.1.2 Sandbox Verification Tests

Verify the Lua sandbox security layer is working.

- [ ] 6.1.2.1 Test: All tools execute through Manager → Lua → Bridge → Security chain
- [ ] 6.1.2.2 Test: Lua VM dangerous functions removed (os.execute, io.popen)
- [ ] 6.1.2.3 Test: Direct Lua code cannot bypass security
- [ ] 6.1.2.4 Test: Bridge functions properly validate all inputs

### 6.1.3 Error Recovery Tests

Test error handling and recovery across tool chains through sandbox.

- [ ] 6.1.3.1 Test: edit_file fails → original file preserved
- [ ] 6.1.3.2 Test: Background process fails → error captured and returned
- [ ] 6.1.3.3 Test: LSP connection lost → graceful degradation
- [ ] 6.1.3.4 Test: Network timeout → cached results used (web tools)
- [ ] 6.1.3.5 Test: Concurrent edits → conflict detection

---

## 6.2 Cross-Session Tool Isolation Tests

Ensure tools respect session boundaries and don't leak state between sessions.

### 6.2.1 Session Isolation

Test that sessions are properly isolated in the sandbox.

- [ ] 6.2.1.1 Create `test/jido_code/integration/session_isolation_test.exs`
- [ ] 6.2.1.2 Test: Session A Lua sandbox state doesn't affect Session B
- [ ] 6.2.1.3 Test: Session A file tracking doesn't affect Session B
- [ ] 6.2.1.4 Test: Session A background processes (shell_ids) isolated from Session B
- [ ] 6.2.1.5 Test: Session A todo list separate from Session B
- [ ] 6.2.1.6 Test: Session A IEx bindings separate from Session B
- [ ] 6.2.1.7 Test: Session A subagent tasks (task_ids) isolated from Session B
- [ ] 6.2.1.8 Test: Session close cleans up Lua sandbox and all resources

### 6.2.2 State Persistence

Test session state persistence and restoration with sandbox.

- [ ] 6.2.2.1 Test: Session save preserves Lua sandbox state
- [ ] 6.2.2.2 Test: Session save preserves read file tracking
- [ ] 6.2.2.3 Test: Session save preserves todo list
- [ ] 6.2.2.4 Test: Session save preserves IEx bindings
- [ ] 6.2.2.5 Test: Session resume restores Lua sandbox state
- [ ] 6.2.2.6 Test: Corrupted session data handled gracefully

---

## 6.3 Concurrent Tool Execution Tests

Test tools running simultaneously through sandbox without interference.

### 6.3.1 Parallel Execution

Test parallel tool execution through sandbox.

- [ ] 6.3.1.1 Create `test/jido_code/integration/concurrent_tools_test.exs`
- [ ] 6.3.1.2 Test: Multiple grep_search calls in parallel (same session)
- [ ] 6.3.1.3 Test: Multiple read_file calls in parallel (same session)
- [ ] 6.3.1.4 Test: bash_execute while bash_background running (same session)
- [ ] 6.3.1.5 Test: Multiple subagents in parallel (same session)
- [ ] 6.3.1.6 Test: Mixed read/write operations (should serialize within session)
- [ ] 6.3.1.7 Test: Parallel tool calls across different sessions (independent)

### 6.3.2 Resource Contention

Test resource contention handling through sandbox.

- [ ] 6.3.2.1 Test: Concurrent edits to same file (same session) → conflict detected
- [ ] 6.3.2.2 Test: Concurrent writes create conflict
- [ ] 6.3.2.3 Test: Background process output retrieval during new command
- [ ] 6.3.2.4 Test: LSP requests during file changes

---

## 6.4 Advanced Search Tools (Optional)

Implement advanced semantic search if time permits. These also route through the Lua sandbox.

### 6.4.1 Codebase Search Tool

Implement semantic code search with embeddings through sandbox.

- [ ] 6.4.1.1 Create `lib/jido_code/tools/definitions/codebase_search.ex`
- [ ] 6.4.1.2 Define schema:
  ```elixir
  %{
    name: "codebase_search",
    description: "Semantic search across codebase using embeddings.",
    parameters: [
      %{name: "query", type: :string, required: true, description: "Natural language query"},
      %{name: "file_type", type: :string, required: false, description: "Filter by file type"},
      %{name: "limit", type: :integer, required: false, description: "Max results"}
    ]
  }
  ```
- [ ] 6.4.1.3 Add `lua_codebase_search/3` to Bridge
- [ ] 6.4.1.4 Implement file chunking strategy
- [ ] 6.4.1.5 Generate embeddings for code chunks
- [ ] 6.4.1.6 Store embeddings in vector index
- [ ] 6.4.1.7 Query with cosine similarity
- [ ] 6.4.1.8 Return ranked results with snippets
- [ ] 6.4.1.9 Register in `Bridge.register/2`

### 6.4.2 Repository Map Tool

Implement AST-based repository structure mapping through sandbox.

- [ ] 6.4.2.1 Create `lib/jido_code/tools/definitions/repo_map.ex`
- [ ] 6.4.2.2 Define schema:
  ```elixir
  %{
    name: "repo_map",
    description: "Generate repository structure map from AST.",
    parameters: [
      %{name: "path", type: :string, required: false, description: "Subdirectory to map"},
      %{name: "depth", type: :integer, required: false, description: "Max depth"},
      %{name: "include_private", type: :boolean, required: false, description: "Include private functions"}
    ]
  }
  ```
- [ ] 6.4.2.3 Add `lua_repo_map/3` to Bridge
- [ ] 6.4.2.4 Parse Elixir files with Code.string_to_quoted
- [ ] 6.4.2.5 Extract module structure:
  - Module name and location
  - Public function signatures
  - Type definitions
  - Module attributes (@moduledoc, @doc)
- [ ] 6.4.2.6 Generate tree representation
- [ ] 6.4.2.7 Cache AST parsing results
- [ ] 6.4.2.8 Register in `Bridge.register/2`

### 6.4.3 Unit Tests for Advanced Search

- [ ] Test codebase_search through sandbox finds semantically relevant code
- [ ] Test codebase_search ranking accuracy
- [ ] Test repo_map through sandbox generates correct structure
- [ ] Test repo_map respects depth limit

---

## 6.5 Documentation

Create comprehensive documentation for all tools and the sandbox architecture.

### 6.5.1 Tool Reference Documentation

Create reference documentation for each tool.

- [ ] 6.5.1.1 Create `guides/tools/file-operations.md`
  - Document read_file, write_file, edit_file, multi_edit, list_dir, glob_search, delete_file
  - Include Bridge function names (jido.read_file, etc.)
  - Include examples for each
  - Document error conditions
- [ ] 6.5.1.2 Create `guides/tools/search-shell.md`
  - Document grep_search, bash_execute, bash_background, bash_output, kill_shell
  - Include Bridge function names
  - Include examples for each
  - Document timeout and output limits
- [ ] 6.5.1.3 Create `guides/tools/git-lsp.md`
  - Document git_command, get_diagnostics, get_hover_info, go_to_definition, find_references
  - Include Bridge function names
  - Include examples for each
  - Document LSP requirements
- [ ] 6.5.1.4 Create `guides/tools/web-agent.md`
  - Document web_fetch, web_search, spawn_subagent, todo_write, todo_read, ask_user
  - Include Bridge function names
  - Include examples for each
  - Document domain restrictions
- [ ] 6.5.1.5 Create `guides/tools/elixir-runtime.md`
  - Document iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit
  - Include Bridge function names
  - Include examples for each
  - Document safety considerations

### 6.5.2 Tool Development Guide

Create guide for developing new tools with the sandbox architecture.

- [ ] 6.5.2.1 Create `guides/developer/tool-development.md`
- [ ] 6.5.2.2 Document tool definition structure
- [ ] 6.5.2.3 Document Bridge function implementation pattern:
  ```elixir
  def lua_my_tool(args, state, project_root) do
    case args do
      [required_arg] -> do_my_tool(required_arg, %{}, state, project_root)
      [required_arg, opts] -> do_my_tool(required_arg, decode_opts(opts), state, project_root)
      _ -> {[nil, "my_tool requires required_arg"], state}
    end
  end
  ```
- [ ] 6.5.2.4 Document Manager API implementation
- [ ] 6.5.2.5 Document testing requirements (sandbox execution)
- [ ] 6.5.2.6 Document security considerations
- [ ] 6.5.2.7 Include complete example tool implementation

### 6.5.3 Security Model Documentation

Document the security model including Lua sandbox.

- [ ] 6.5.3.1 Create `guides/developer/security-model.md`
- [ ] 6.5.3.2 Document defense-in-depth architecture:
  - Layer 1: Lua sandbox (dangerous functions removed)
  - Layer 2: Security module (path validation, command allowlist)
- [ ] 6.5.3.3 Reference [ADR-0001](../../decisions/0001-tool-security-architecture.md)
- [ ] 6.5.3.4 Document path boundary validation
- [ ] 6.5.3.5 Document command allowlist
- [ ] 6.5.3.6 Document domain restrictions (web tools)
- [ ] 6.5.3.7 Document session isolation
- [ ] 6.5.3.8 Document the Bridge function security pattern

---

## 6.6 Performance Optimization

Optimize tool performance for large codebases while maintaining sandbox security.

### 6.6.1 Tool Result Caching

Implement caching for expensive operations (outside Lua, but results accessible via Bridge).

- [ ] 6.6.1.1 Create `lib/jido_code/tools/cache.ex`
- [ ] 6.6.1.2 Implement ETS-based cache with TTL
- [ ] 6.6.1.3 Add cache keys based on tool + args hash
- [ ] 6.6.1.4 Add cache invalidation on file changes
- [ ] 6.6.1.5 Cache expensive operations:
  - grep_search results (5 minute TTL)
  - glob_search results (1 minute TTL)
  - web_fetch results (15 minute TTL)
  - LSP diagnostics (30 second TTL)
  - repo_map results (10 minute TTL)
- [ ] 6.6.1.6 Bridge functions should check cache before expensive operations

### 6.6.2 Output Streaming

Implement streaming for large outputs through sandbox.

- [ ] 6.6.2.1 Create streaming interface for tool results
- [ ] 6.6.2.2 Stream bash_execute output incrementally (via Bridge)
- [ ] 6.6.2.3 Stream grep_search results incrementally (via Bridge)
- [ ] 6.6.2.4 Stream read_file content for large files (via Bridge)
- [ ] 6.6.2.5 Update TUI to display streaming output

### 6.6.3 Parallel Tool Execution

Optimize parallel execution where safe within sandbox.

- [ ] 6.6.3.1 Identify parallelizable tool combinations
- [ ] 6.6.3.2 Implement parallel execution infrastructure
- [ ] 6.6.3.3 Add concurrency limits to prevent resource exhaustion
- [ ] 6.6.3.4 Test parallel execution performance gains

### 6.6.4 Performance Tests

Create performance benchmarks for tools through sandbox.

- [ ] 6.6.4.1 Create `test/jido_code/performance/tools_benchmark_test.exs`
- [ ] 6.6.4.2 Benchmark grep_search through sandbox on large codebase
- [ ] 6.6.4.3 Benchmark glob_search through sandbox with many files
- [ ] 6.6.4.4 Benchmark read_file through sandbox with large files
- [ ] 6.6.4.5 Benchmark concurrent tool execution through sandbox
- [ ] 6.6.4.6 Document performance characteristics

---

## 6.7 Final Integration Tests

Final comprehensive tests before release.

### 6.7.1 Smoke Tests

Quick tests to verify basic functionality through sandbox.

- [ ] 6.7.1.1 Create `test/jido_code/integration/smoke_test.exs`
- [ ] 6.7.1.2 Test each tool with minimal valid input through sandbox
- [ ] 6.7.1.3 Test each tool with invalid input (error handling)
- [ ] 6.7.1.4 Test tool registration and discovery
- [ ] 6.7.1.5 Test tool execution through executor → manager → Lua → bridge chain

### 6.7.2 Stress Tests

Tests under load conditions through sandbox.

- [ ] 6.7.2.1 Create `test/jido_code/integration/stress_test.exs`
- [ ] 6.7.2.2 Test 100+ concurrent tool calls through sandbox
- [ ] 6.7.2.3 Test memory usage under load (Lua VM + Elixir)
- [ ] 6.7.2.4 Test recovery from resource exhaustion
- [ ] 6.7.2.5 Test long-running background processes

---

## Phase 6 Success Criteria

1. **Integration Tests**: All tool chain workflows pass through sandbox
2. **Sandbox Verification**: Lua security layer verified working
3. **Session Isolation**: Tools respect session boundaries (separate sandboxes)
4. **Concurrent Execution**: No race conditions or data corruption
5. **Documentation**: All tools documented with Bridge function names
6. **Security Documentation**: Sandbox architecture clearly documented
7. **Performance**: Acceptable performance on large codebases
8. **Test Coverage**: Minimum 80% overall test coverage

---

## Phase 6 Critical Files

**New Files:**
- `test/jido_code/integration/full_workflow_test.exs`
- `test/jido_code/integration/session_isolation_test.exs`
- `test/jido_code/integration/concurrent_tools_test.exs`
- `test/jido_code/integration/smoke_test.exs`
- `test/jido_code/integration/stress_test.exs`
- `test/jido_code/performance/tools_benchmark_test.exs`
- `lib/jido_code/tools/cache.ex`
- `guides/tools/file-operations.md`
- `guides/tools/search-shell.md`
- `guides/tools/git-lsp.md`
- `guides/tools/web-agent.md`
- `guides/tools/elixir-runtime.md`
- `guides/developer/tool-development.md`
- `guides/developer/security-model.md`

**Optional Files (Advanced Search):**
- `lib/jido_code/tools/definitions/codebase_search.ex`
- `lib/jido_code/tools/definitions/repo_map.ex`

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add caching integration, streaming support

---

## Summary: All Phases Complete

Upon completion of Phase 6, JidoCode will have:

| Category | Tools | Bridge Functions |
|----------|-------|------------------|
| File Operations | read_file, write_file, edit_file, multi_edit, list_dir, glob_search, delete_file | jido.read_file, jido.write_file, jido.edit_file, jido.multi_edit, jido.list_dir, jido.glob, jido.delete_file |
| Code Search | grep_search, (codebase_search, repo_map optional) | jido.grep, (jido.codebase_search, jido.repo_map) |
| Shell Execution | bash_execute, bash_background, bash_output, kill_shell | jido.shell, jido.shell_background, jido.shell_output, jido.shell_kill |
| Git Operations | git_command | jido.git |
| LSP Integration | get_diagnostics, get_hover_info, go_to_definition, find_references | jido.lsp_diagnostics, jido.lsp_hover, jido.lsp_definition, jido.lsp_references |
| Web Tools | web_fetch, web_search | jido.web_fetch, jido.web_search |
| Agent/Task | spawn_subagent, get_task_output, todo_write, todo_read, ask_user | jido.spawn_agent, jido.task_output, jido.todo_write, jido.todo_read, jido.ask_user |
| Elixir-Specific | iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit | jido.iex_eval, jido.mix_task, jido.process_state, jido.supervisor_tree, jido.reload_module, jido.ets, jido.docs, jido.exunit |
| **Total** | **32-34 tools** | All via Lua sandbox |

All tools will have:
- Complete test coverage (80%+)
- Comprehensive documentation
- **Defense-in-depth security** (Lua sandbox + Security module)
- Performance optimization
- Session isolation
