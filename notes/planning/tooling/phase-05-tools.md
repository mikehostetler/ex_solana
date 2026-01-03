# Phase 5: Elixir-Specific Tools

This phase implements BEAM runtime introspection tools unique to Elixir. These tools provide powerful capabilities for code evaluation, process inspection, hot reloading, and ETS table management. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All Elixir-specific tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "iex_eval", "arguments": {"code": "..."}}   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.iex_eval(code, opts, session_id: id)         │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.iex_eval(code, opts)"        │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_iex_eval/3 invoked from Lua                     │
│  (Elixir function registered as jido.iex_eval)              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Elixir runtime introspection                               │
│  - Code.eval_string, :sys.get_state, etc.                   │
│  - Session-scoped bindings and state                        │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Bridge Function | Purpose |
|------|-----------------|---------|
| iex_eval | `jido.iex_eval(code, opts)` | Evaluate Elixir code with bindings |
| mix_task | `jido.mix_task(task, args)` | Run Mix tasks |
| get_process_state | `jido.process_state(process)` | Inspect GenServer/process state |
| inspect_supervisor | `jido.supervisor_tree(name, opts)` | View supervisor tree |
| reload_module | `jido.reload_module(module)` | Hot reload module |
| ets_inspect | `jido.ets(operation, opts)` | Inspect ETS tables |
| fetch_elixir_docs | `jido.docs(module, opts)` | Retrieve module/function docs |
| run_exunit | `jido.exunit(opts)` | Run ExUnit tests |

---

## 5.1 IEx Eval Tool

Implement the iex_eval tool for evaluating Elixir code expressions through the Lua sandbox.

### 5.1.1 Tool Definition

Create the iex_eval tool definition for code evaluation.

- [ ] 5.1.1.1 Create `lib/jido_code/tools/definitions/iex_eval.ex`
- [ ] 5.1.1.2 Define schema:
  ```elixir
  %{
    name: "iex_eval",
    description: "Evaluate Elixir code. Bindings persist within session.",
    parameters: [
      %{name: "code", type: :string, required: true, description: "Elixir code to evaluate"},
      %{name: "bindings", type: :map, required: false, description: "Variable bindings"},
      %{name: "timeout", type: :integer, required: false, description: "Timeout in ms (default: 5000)"}
    ]
  }
  ```
- [ ] 5.1.1.3 Document safety considerations
- [ ] 5.1.1.4 Register tool in definitions module

### 5.1.2 Bridge Function Implementation

Implement the Bridge function for code evaluation.

- [ ] 5.1.2.1 Add `lua_iex_eval/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_iex_eval(args, state, _project_root) do
    case args do
      [code] -> do_iex_eval(code, %{}, state)
      [code, opts] -> do_iex_eval(code, decode_opts(opts), state)
      _ -> {[nil, "iex_eval requires code argument"], state}
    end
  end
  ```
- [ ] 5.1.2.2 Parse bindings into keyword list format
- [ ] 5.1.2.3 Merge with session-scoped bindings from state
- [ ] 5.1.2.4 Use Code.eval_string with bindings
- [ ] 5.1.2.5 Wrap evaluation in Task with timeout
- [ ] 5.1.2.6 Capture result and updated bindings
- [ ] 5.1.2.7 Update session state with new bindings
- [ ] 5.1.2.8 Handle evaluation errors gracefully
- [ ] 5.1.2.9 Format result for display (inspect with pretty)
- [ ] 5.1.2.10 Return `{[%{result: result, bindings: bindings}], updated_state}` or `{[nil, error], state}`
- [ ] 5.1.2.11 Register in `Bridge.register/2`

### 5.1.3 Manager API

- [ ] 5.1.3.1 Add `iex_eval/2` to `Tools.Manager`
- [ ] 5.1.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.1.3.3 Call bridge function through Lua: `jido.iex_eval(code, opts)`

### 5.1.4 Unit Tests for IEx Eval

- [ ] Test iex_eval through sandbox with simple expressions
- [ ] Test iex_eval with bindings
- [ ] Test iex_eval updates session bindings
- [ ] Test iex_eval captures syntax errors
- [ ] Test iex_eval captures runtime errors
- [ ] Test iex_eval respects timeout
- [ ] Test iex_eval handles complex expressions
- [ ] Test iex_eval handles module definitions

---

## 5.2 Mix Task Tool

Implement the mix_task tool for running Mix tasks through the Lua sandbox.

### 5.2.1 Tool Definition

Create the mix_task tool definition for task execution.

- [ ] 5.2.1.1 Create `lib/jido_code/tools/definitions/mix_task.ex`
- [ ] 5.2.1.2 Define schema:
  ```elixir
  %{
    name: "mix_task",
    description: "Run Mix task. Some tasks blocked for safety.",
    parameters: [
      %{name: "task", type: :string, required: true, description: "Mix task name (e.g., 'compile', 'test')"},
      %{name: "args", type: :array, required: false, description: "Task arguments"},
      %{name: "env", type: :string, required: false, enum: ["dev", "test", "prod"], description: "Mix environment"}
    ]
  }
  ```
- [ ] 5.2.1.3 Document allowed and blocked tasks
- [ ] 5.2.1.4 Register tool in definitions module

### 5.2.2 Bridge Function Implementation

Implement the Bridge function for Mix task execution.

- [ ] 5.2.2.1 Add `lua_mix_task/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_mix_task(args, state, project_root) do
    case args do
      [task] -> do_mix_task(task, [], %{}, state, project_root)
      [task, task_args] -> do_mix_task(task, task_args, %{}, state, project_root)
      [task, task_args, opts] -> do_mix_task(task, task_args, decode_opts(opts), state, project_root)
      _ -> {[nil, "mix_task requires task argument"], state}
    end
  end
  ```
- [ ] 5.2.2.2 Define allowed tasks:
  - compile, compile.all
  - test, test.all
  - format
  - deps.get, deps.compile, deps.tree
  - help
  - credo
  - dialyzer
- [ ] 5.2.2.3 Define blocked tasks:
  - release (production concern)
  - ecto.drop, ecto.reset (destructive)
  - phx.gen.secret (security)
- [ ] 5.2.2.4 Validate task against allowlist
- [ ] 5.2.2.5 Build mix command with arguments
- [ ] 5.2.2.6 Set MIX_ENV if specified
- [ ] 5.2.2.7 Execute mix task in project directory with output capture
- [ ] 5.2.2.8 Parse output for structured results
- [ ] 5.2.2.9 Return `{[%{output: output, exit_code: code}], state}` or `{[nil, error], state}`
- [ ] 5.2.2.10 Register in `Bridge.register/2`

### 5.2.3 Manager API

- [ ] 5.2.3.1 Add `mix_task/3` to `Tools.Manager`
- [ ] 5.2.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.2.3.3 Call bridge function through Lua: `jido.mix_task(task, args, opts)`

### 5.2.4 Unit Tests for Mix Task

- [ ] Test mix_task through sandbox runs compile
- [ ] Test mix_task runs test
- [ ] Test mix_task runs test with filter
- [ ] Test mix_task runs format
- [ ] Test mix_task runs deps.get
- [ ] Test mix_task blocks dangerous tasks
- [ ] Test mix_task sets MIX_ENV
- [ ] Test mix_task handles task errors

---

## 5.3 Get Process State Tool

Implement the get_process_state tool for inspecting GenServer and process state through the Lua sandbox.

### 5.3.1 Tool Definition

Create the get_process_state tool definition for process inspection.

- [ ] 5.3.1.1 Create `lib/jido_code/tools/definitions/get_process_state.ex`
- [ ] 5.3.1.2 Define schema:
  ```elixir
  %{
    name: "get_process_state",
    description: "Get state of a GenServer or process.",
    parameters: [
      %{name: "process", type: :string, required: true, description: "PID string, registered name, or module name"},
      %{name: "timeout", type: :integer, required: false, description: "Timeout in ms (default: 5000)"}
    ]
  }
  ```
- [ ] 5.3.1.3 Register tool in definitions module

### 5.3.2 Bridge Function Implementation

Implement the Bridge function for process state retrieval.

- [ ] 5.3.2.1 Add `lua_process_state/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_process_state(args, state, _project_root) do
    case args do
      [process] -> do_process_state(process, %{}, state)
      [process, opts] -> do_process_state(process, decode_opts(opts), state)
      _ -> {[nil, "process_state requires process argument"], state}
    end
  end
  ```
- [ ] 5.3.2.2 Parse process identifier:
  - PID string: "#PID<0.123.0>" -> :erlang.list_to_pid
  - Registered name: "MyApp.Worker" -> Process.whereis
  - Module with __via__: lookup through registry
- [ ] 5.3.2.3 Use :sys.get_state/2 for GenServer/gen_statem
- [ ] 5.3.2.4 Handle process_info for raw processes
- [ ] 5.3.2.5 Format state for display (inspect with pretty)
- [ ] 5.3.2.6 Return `{[%{state: state, process_info: info}], state}` or `{[nil, error], state}`
- [ ] 5.3.2.7 Register in `Bridge.register/2`

### 5.3.3 Manager API

- [ ] 5.3.3.1 Add `process_state/2` to `Tools.Manager`
- [ ] 5.3.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.3.3.3 Call bridge function through Lua: `jido.process_state(process, opts)`

### 5.3.4 Unit Tests for Get Process State

- [ ] Test get_process_state through sandbox with PID string
- [ ] Test get_process_state with registered name
- [ ] Test get_process_state with GenServer
- [ ] Test get_process_state with Agent
- [ ] Test get_process_state handles dead process
- [ ] Test get_process_state respects timeout

---

## 5.4 Inspect Supervisor Tool

Implement the inspect_supervisor tool for viewing supervisor trees through the Lua sandbox.

### 5.4.1 Tool Definition

Create the inspect_supervisor tool definition.

- [ ] 5.4.1.1 Create `lib/jido_code/tools/definitions/inspect_supervisor.ex`
- [ ] 5.4.1.2 Define schema:
  ```elixir
  %{
    name: "inspect_supervisor",
    description: "View supervisor tree structure.",
    parameters: [
      %{name: "supervisor", type: :string, required: true, description: "Supervisor module or PID"},
      %{name: "depth", type: :integer, required: false, description: "Max tree depth (default: 3)"}
    ]
  }
  ```
- [ ] 5.4.1.3 Register tool in definitions module

### 5.4.2 Bridge Function Implementation

Implement the Bridge function for supervisor tree inspection.

- [ ] 5.4.2.1 Add `lua_supervisor_tree/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_supervisor_tree(args, state, _project_root) do
    case args do
      [supervisor] -> do_supervisor_tree(supervisor, %{depth: 3}, state)
      [supervisor, opts] -> do_supervisor_tree(supervisor, decode_opts(opts), state)
      _ -> {[nil, "supervisor_tree requires supervisor argument"], state}
    end
  end
  ```
- [ ] 5.4.2.2 Parse supervisor identifier
- [ ] 5.4.2.3 Use Supervisor.which_children/1
- [ ] 5.4.2.4 Recursively inspect child supervisors up to depth
- [ ] 5.4.2.5 Format tree structure for display
- [ ] 5.4.2.6 Return `{[%{tree: tree_string, children: list}], state}` or `{[nil, error], state}`
- [ ] 5.4.2.7 Register in `Bridge.register/2`

### 5.4.3 Manager API

- [ ] 5.4.3.1 Add `supervisor_tree/2` to `Tools.Manager`
- [ ] 5.4.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.4.3.3 Call bridge function through Lua: `jido.supervisor_tree(supervisor, opts)`

### 5.4.4 Unit Tests for Inspect Supervisor

- [ ] Test inspect_supervisor through sandbox with Application supervisor
- [ ] Test inspect_supervisor shows children
- [ ] Test inspect_supervisor respects depth limit
- [ ] Test inspect_supervisor handles DynamicSupervisor
- [ ] Test inspect_supervisor handles dead supervisor

---

## 5.5 Reload Module Tool

Implement the reload_module tool for hot code reloading through the Lua sandbox.

### 5.5.1 Tool Definition

Create the reload_module tool definition.

- [ ] 5.5.1.1 Create `lib/jido_code/tools/definitions/reload_module.ex`
- [ ] 5.5.1.2 Define schema:
  ```elixir
  %{
    name: "reload_module",
    description: "Hot reload a module after source changes.",
    parameters: [
      %{name: "module", type: :string, required: true, description: "Module name to reload"},
      %{name: "recompile", type: :boolean, required: false, description: "Recompile before reload (default: true)"}
    ]
  }
  ```
- [ ] 5.5.1.3 Register tool in definitions module

### 5.5.2 Bridge Function Implementation

Implement the Bridge function for module hot reloading.

- [ ] 5.5.2.1 Add `lua_reload_module/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_reload_module(args, state, project_root) do
    case args do
      [module] -> do_reload_module(module, %{recompile: true}, state, project_root)
      [module, opts] -> do_reload_module(module, decode_opts(opts), state, project_root)
      _ -> {[nil, "reload_module requires module argument"], state}
    end
  end
  ```
- [ ] 5.5.2.2 Parse module name to atom
- [ ] 5.5.2.3 If recompile=true, run Mix.Task.rerun("compile") in project directory
- [ ] 5.5.2.4 Use Code.purge/1 to remove old code
- [ ] 5.5.2.5 Use IEx.Helpers.r or Code.load_file for reload
- [ ] 5.5.2.6 Verify module loaded successfully
- [ ] 5.5.2.7 Return `{[%{module: module, functions: exports}], state}` or `{[nil, error], state}`
- [ ] 5.5.2.8 Register in `Bridge.register/2`

### 5.5.3 Manager API

- [ ] 5.5.3.1 Add `reload_module/2` to `Tools.Manager`
- [ ] 5.5.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.5.3.3 Call bridge function through Lua: `jido.reload_module(module, opts)`

### 5.5.4 Unit Tests for Reload Module

- [ ] Test reload_module through sandbox reloads existing module
- [ ] Test reload_module with recompile
- [ ] Test reload_module handles non-existent module
- [ ] Test reload_module handles compilation errors

---

## 5.6 ETS Inspect Tool

Implement the ets_inspect tool for ETS table inspection through the Lua sandbox.

### 5.6.1 Tool Definition

Create the ets_inspect tool definition.

- [ ] 5.6.1.1 Create `lib/jido_code/tools/definitions/ets_inspect.ex`
- [ ] 5.6.1.2 Define schema:
  ```elixir
  %{
    name: "ets_inspect",
    description: "Inspect ETS tables.",
    parameters: [
      %{name: "operation", type: :string, required: true,
        enum: ["list", "info", "lookup", "match"], description: "Operation to perform"},
      %{name: "table", type: :string, required: false, description: "Table name (required for info/lookup/match)"},
      %{name: "key", type: :any, required: false, description: "Key for lookup"},
      %{name: "pattern", type: :any, required: false, description: "Match pattern"},
      %{name: "limit", type: :integer, required: false, description: "Max entries to return"}
    ]
  }
  ```
- [ ] 5.6.1.3 Register tool in definitions module

### 5.6.2 Bridge Function Implementation

Implement the Bridge function for ETS operations.

- [ ] 5.6.2.1 Add `lua_ets/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_ets(args, state, _project_root) do
    case args do
      [operation] -> do_ets(operation, %{}, state)
      [operation, opts] -> do_ets(operation, decode_opts(opts), state)
      _ -> {[nil, "ets requires operation argument"], state}
    end
  end
  ```
- [ ] 5.6.2.2 Implement `list` operation: :ets.all() with table info
- [ ] 5.6.2.3 Implement `info` operation: :ets.info(table)
- [ ] 5.6.2.4 Implement `lookup` operation: :ets.lookup(table, key)
- [ ] 5.6.2.5 Implement `match` operation: :ets.match(table, pattern, limit)
- [ ] 5.6.2.6 Format results for display
- [ ] 5.6.2.7 Return `{[result], state}` or `{[nil, error], state}`
- [ ] 5.6.2.8 Register in `Bridge.register/2`

### 5.6.3 Manager API

- [ ] 5.6.3.1 Add `ets/2` to `Tools.Manager`
- [ ] 5.6.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.6.3.3 Call bridge function through Lua: `jido.ets(operation, opts)`

### 5.6.4 Unit Tests for ETS Inspect

- [ ] Test ets_inspect through sandbox list operation
- [ ] Test ets_inspect info operation
- [ ] Test ets_inspect lookup operation
- [ ] Test ets_inspect match operation
- [ ] Test ets_inspect handles non-existent table
- [ ] Test ets_inspect respects limit

---

## 5.7 Fetch Elixir Docs Tool

Implement the fetch_elixir_docs tool for retrieving module and function documentation through the Lua sandbox.

### 5.7.1 Tool Definition

Create the fetch_elixir_docs tool definition.

- [ ] 5.7.1.1 Create `lib/jido_code/tools/definitions/fetch_elixir_docs.ex`
- [ ] 5.7.1.2 Define schema:
  ```elixir
  %{
    name: "fetch_elixir_docs",
    description: "Retrieve documentation for Elixir module or function.",
    parameters: [
      %{name: "module", type: :string, required: true, description: "Module name"},
      %{name: "function", type: :string, required: false, description: "Function name"},
      %{name: "arity", type: :integer, required: false, description: "Function arity"}
    ]
  }
  ```
- [ ] 5.7.1.3 Register tool in definitions module

### 5.7.2 Bridge Function Implementation

Implement the Bridge function for documentation retrieval.

- [ ] 5.7.2.1 Add `lua_docs/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_docs(args, state, _project_root) do
    case args do
      [module] -> do_docs(module, %{}, state)
      [module, opts] -> do_docs(module, decode_opts(opts), state)
      _ -> {[nil, "docs requires module argument"], state}
    end
  end
  ```
- [ ] 5.7.2.2 Parse module name to atom
- [ ] 5.7.2.3 Use Code.fetch_docs/1 for module docs
- [ ] 5.7.2.4 Filter to specific function/arity if specified
- [ ] 5.7.2.5 Format documentation (markdown conversion)
- [ ] 5.7.2.6 Include specs if available
- [ ] 5.7.2.7 Return `{[%{moduledoc: doc, docs: function_docs}], state}` or `{[nil, error], state}`
- [ ] 5.7.2.8 Register in `Bridge.register/2`

### 5.7.3 Manager API

- [ ] 5.7.3.1 Add `docs/2` to `Tools.Manager`
- [ ] 5.7.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.7.3.3 Call bridge function through Lua: `jido.docs(module, opts)`

### 5.7.4 Unit Tests for Fetch Elixir Docs

- [ ] Test fetch_elixir_docs through sandbox for module
- [ ] Test fetch_elixir_docs for specific function
- [ ] Test fetch_elixir_docs for function with arity
- [ ] Test fetch_elixir_docs includes specs
- [ ] Test fetch_elixir_docs handles undocumented module

---

## 5.8 Run ExUnit Tool

Implement the run_exunit tool for running ExUnit tests through the Lua sandbox.

### 5.8.1 Tool Definition

Create the run_exunit tool definition.

- [ ] 5.8.1.1 Create `lib/jido_code/tools/definitions/run_exunit.ex`
- [ ] 5.8.1.2 Define schema:
  ```elixir
  %{
    name: "run_exunit",
    description: "Run ExUnit tests with filtering.",
    parameters: [
      %{name: "path", type: :string, required: false, description: "Test file or directory"},
      %{name: "line", type: :integer, required: false, description: "Run test at specific line"},
      %{name: "tag", type: :string, required: false, description: "Run tests with specific tag"},
      %{name: "exclude_tag", type: :string, required: false, description: "Exclude tests with tag"},
      %{name: "seed", type: :integer, required: false, description: "Random seed"},
      %{name: "max_failures", type: :integer, required: false, description: "Stop after N failures"}
    ]
  }
  ```
- [ ] 5.8.1.3 Register tool in definitions module

### 5.8.2 Bridge Function Implementation

Implement the Bridge function for test execution.

- [ ] 5.8.2.1 Add `lua_exunit/3` function to `lib/jido_code/tools/bridge.ex`
  ```elixir
  def lua_exunit(args, state, project_root) do
    case args do
      [] -> do_exunit(%{}, state, project_root)
      [opts] -> do_exunit(decode_opts(opts), state, project_root)
      _ -> {[nil, "exunit: invalid arguments"], state}
    end
  end
  ```
- [ ] 5.8.2.2 Build mix test command with options
- [ ] 5.8.2.3 Add --trace for verbose output
- [ ] 5.8.2.4 Execute tests in project directory and capture output
- [ ] 5.8.2.5 Parse test results:
  - Total tests, passed, failed, skipped
  - Failure details with file/line
  - Timing information
- [ ] 5.8.2.6 Return `{[%{summary: summary, failures: failures, output: output}], state}` or `{[nil, error], state}`
- [ ] 5.8.2.7 Register in `Bridge.register/2`

### 5.8.3 Manager API

- [ ] 5.8.3.1 Add `exunit/2` to `Tools.Manager`
- [ ] 5.8.3.2 Support `session_id` option to route to session-scoped manager
- [ ] 5.8.3.3 Call bridge function through Lua: `jido.exunit(opts)`

### 5.8.4 Unit Tests for Run ExUnit

- [ ] Test run_exunit through sandbox runs all tests
- [ ] Test run_exunit runs specific file
- [ ] Test run_exunit runs specific line
- [ ] Test run_exunit filters by tag
- [ ] Test run_exunit excludes by tag
- [ ] Test run_exunit parses failures
- [ ] Test run_exunit respects max_failures

---

## 5.9 Phase 5 Integration Tests

Integration tests for Elixir-specific tools working through the Lua sandbox.

### 5.9.1 Sandbox Integration

Verify tools execute through the sandbox correctly.

- [ ] 5.9.1.1 Create `test/jido_code/integration/tools_phase5_test.exs`
- [ ] 5.9.1.2 Test: All tools execute through `Tools.Manager` → Lua → Bridge chain
- [ ] 5.9.1.3 Test: Session-scoped bindings persist across iex_eval calls

### 5.9.2 Runtime Introspection Integration

Test runtime introspection tools together through sandbox.

- [ ] 5.9.2.1 Test: iex_eval creates GenServer -> get_process_state inspects it
- [ ] 5.9.2.2 Test: Mix task execution and output parsing
- [ ] 5.9.2.3 Test: Hot reload after file edit

### 5.9.3 BEAM-Specific Integration

Test BEAM-specific introspection tools through sandbox.

- [ ] 5.9.3.1 Test: ETS table creation -> ets_inspect list/info/lookup
- [ ] 5.9.3.2 Test: Supervisor tree traversal
- [ ] 5.9.3.3 Test: GenServer state inspection

### 5.9.4 Documentation Integration

Test documentation tools through sandbox.

- [ ] 5.9.4.1 Test: fetch_elixir_docs for standard library modules
- [ ] 5.9.4.2 Test: fetch_elixir_docs for project modules

### 5.9.5 Testing Integration

Test ExUnit integration through sandbox.

- [ ] 5.9.5.1 Test: run_exunit executes tests
- [ ] 5.9.5.2 Test: run_exunit parses failures correctly

---

## Phase 5 Success Criteria

1. **iex_eval**: Code evaluation via `jido.iex_eval` bridge with session bindings
2. **mix_task**: Safe Mix execution via `jido.mix_task` bridge
3. **get_process_state**: Process inspection via `jido.process_state` bridge
4. **inspect_supervisor**: Supervisor tree via `jido.supervisor_tree` bridge
5. **reload_module**: Hot reload via `jido.reload_module` bridge
6. **ets_inspect**: ETS operations via `jido.ets` bridge
7. **fetch_elixir_docs**: Documentation via `jido.docs` bridge
8. **run_exunit**: Test execution via `jido.exunit` bridge
9. **All tools execute through Lua sandbox** (defense-in-depth)
10. **Test Coverage**: Minimum 80% for Phase 5 tools

---

## Phase 5 Critical Files

**Modified Files:**
- `lib/jido_code/tools/bridge.ex` - Add Elixir runtime bridge functions
- `lib/jido_code/tools/manager.ex` - Expose Elixir runtime APIs

**New Files:**
- `lib/jido_code/tools/definitions/iex_eval.ex`
- `lib/jido_code/tools/definitions/mix_task.ex`
- `lib/jido_code/tools/definitions/get_process_state.ex`
- `lib/jido_code/tools/definitions/inspect_supervisor.ex`
- `lib/jido_code/tools/definitions/reload_module.ex`
- `lib/jido_code/tools/definitions/ets_inspect.ex`
- `lib/jido_code/tools/definitions/fetch_elixir_docs.ex`
- `lib/jido_code/tools/definitions/run_exunit.ex`
- `test/jido_code/tools/bridge_elixir_runtime_test.exs`
- `test/jido_code/integration/tools_phase5_test.exs`
