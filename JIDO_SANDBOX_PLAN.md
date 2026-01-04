# Jido Sandbox MVP Implementation Plan

**Date:** January 3, 2026  
**Project:** `jido_sandbox` - Lightweight sandbox for LLM tool calls  
**Location:** `projects/jido_sandbox/`

---

## Overview

This plan implements a minimal, pure-BEAM sandbox for LLMs in a ReAct tool calling loop. Each step is atomic, must pass `mix quality`, and maintains 90%+ test coverage.

**MVP Surface Area:**
- `JidoSandbox.new/1` - Create sandbox
- `JidoSandbox.write/3` - Write file
- `JidoSandbox.read/2` - Read file
- `JidoSandbox.list/2` - List directory
- `JidoSandbox.delete/2` - Delete file
- `JidoSandbox.mkdir/2` - Create directory
- `JidoSandbox.snapshot/1` - Save VFS state
- `JidoSandbox.restore/2` - Restore VFS state
- `JidoSandbox.eval_lua/2` - Execute Lua code (optional)

**Key Constraints (Features, not bugs):**
- No real filesystem access
- No networking
- No real shell/process execution
- Lua-only scripting (sandboxed)
- All paths virtual and absolute

---

## Step 1: Project & QA Scaffolding

**Goal:** Bring `jido_sandbox` up to GENERIC_PACKAGE_QA standards.

### Tasks

1. **Update `mix.exs`** to match template:
   ```elixir
   @version "0.1.0"
   @source_url "https://github.com/agentjido/jido_sandbox"
   @description "In-memory sandbox (VFS + Lua) for LLM tool calls"
   ```
   - Add `elixirc_paths/1` for test support
   - Add `aliases/0` with `quality` and `q`
   - Add `docs/0`, `package/0`, `cli/0`
   - Add `test_coverage` with ExCoveralls, 90% threshold
   - Add `dialyzer` config

2. **Add dependencies:**
   ```elixir
   # Runtime
   {:zoi, "~> 0.14"},
   {:lua, "~> 0.0.14"},  # tv-labs/lua
   
   # Dev/Test
   {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
   {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
   {:ex_doc, "~> 0.31", only: :dev, runtime: false},
   {:excoveralls, "~> 0.18", only: [:dev, :test]},
   {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
   {:git_ops, "~> 2.9", only: :dev, runtime: false}
   ```

3. **Create config files:**
   - `.formatter.exs` - Standard formatter config
   - `.credo.exs` - Standard credo config
   - `config/config.exs` - Default sandbox options
   - `config/test.exs` - Test overrides

4. **Create documentation files:**
   - `README.md` - Overview, installation, quick start
   - `CHANGELOG.md` - Initial entry
   - `CONTRIBUTING.md` - Contribution guidelines
   - `AGENTS.md` - AI agent instructions
   - `usage-rules.md` - LLM usage rules
   - `LICENSE` - Apache-2.0

5. **Update `.gitignore`:**
   - `_build/`, `deps/`, `cover/`, `cov/`, `priv/plts/`, `*.plt`

6. **Replace hello world with stub:**
   ```elixir
   defmodule JidoSandbox do
     @moduledoc "Public entrypoint for sandbox operations."
     @spec ping() :: :pong
     def ping, do: :pong
   end
   ```

7. **Add test for stub:**
   ```elixir
   # test/jido_sandbox_test.exs
   test "ping returns pong" do
     assert JidoSandbox.ping() == :pong
   end
   ```

### Acceptance Criteria
- [ ] `mix deps.get` succeeds
- [ ] `mix quality` passes
- [ ] `mix coveralls` shows ≥90% coverage
- [ ] All QA files present per GENERIC_PACKAGE_QA.md

---

## Step 2: Core Domain Design

**Goal:** Define sandbox struct, VFS behavior, and public API signatures.

### Tasks

1. **Create `lib/jido_sandbox/sandbox.ex`:**
   ```elixir
   defmodule JidoSandbox.Sandbox do
     @type t :: %__MODULE__{
       vfs: VFS.t(),
       snapshots: %{String.t() => VFS.t()},
       next_snapshot_id: non_neg_integer()
     }
     
     defstruct vfs: nil, snapshots: %{}, next_snapshot_id: 0
     
     @spec new(keyword()) :: t()
     def new(opts \\ [])
     
     # Stub implementations for all operations
     @spec write(t(), String.t(), iodata()) :: {:ok, t()} | {:error, term()}
     @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
     @spec list(t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
     @spec delete(t(), String.t()) :: {:ok, t()} | {:error, term()}
     @spec mkdir(t(), String.t()) :: {:ok, t()} | {:error, term()}
     @spec eval_lua(t(), String.t()) :: {:ok, term(), t()} | {:error, term(), t()}
     @spec snapshot(t()) :: {:ok, String.t(), t()}
     @spec restore(t(), String.t()) :: {:ok, t()} | {:error, term()}
   end
   ```

2. **Create `lib/jido_sandbox/vfs.ex`:**
   ```elixir
   defmodule JidoSandbox.VFS do
     @moduledoc "VFS behavior for sandbox storage backends."
     
     @type path :: String.t()
     @type t :: struct()
     
     @callback new() :: t()
     @callback write(t(), path(), iodata()) :: {:ok, t()} | {:error, term()}
     @callback read(t(), path()) :: {:ok, binary()} | {:error, term()}
     @callback list(t(), path()) :: {:ok, [String.t()]} | {:error, term()}
     @callback delete(t(), path()) :: {:ok, t()} | {:error, term()}
     @callback mkdir(t(), path()) :: {:ok, t()} | {:error, term()}
   end
   ```

3. **Update `lib/jido_sandbox.ex`** with full public API:
   - Replace `ping/0` with real API functions
   - All functions delegate to `JidoSandbox.Sandbox`
   - `eval_lua/2` returns `{:error, :lua_not_enabled, sandbox}` for now

4. **Add tests:**
   - `test/jido_sandbox_test.exs` - Test `new/0` returns valid struct
   - Test all stubs return expected error tuples

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] All public API functions defined with specs

---

## Step 3: In-Memory VFS Implementation

**Goal:** Implement pure in-memory filesystem adapter.

### Tasks

1. **Create `lib/jido_sandbox/vfs/in_memory.ex`:**
   ```elixir
   defmodule JidoSandbox.VFS.InMemory do
     @behaviour JidoSandbox.VFS
     
     @type t :: %__MODULE__{files: %{String.t() => binary()}}
     defstruct files: %{}
     
     @impl true
     def new, do: %__MODULE__{}
     
     @impl true
     def write(%__MODULE__{} = vfs, path, content) do
       with {:ok, normalized} <- normalize_path(path) do
         {:ok, %{vfs | files: Map.put(vfs.files, normalized, IO.iodata_to_binary(content))}}
       end
     end
     
     # Implement read/list/delete/mkdir
     # Path normalization: reject "..", require leading "/"
   end
   ```

2. **Create `lib/jido_sandbox/vfs/path.ex`:**
   - `normalize/1` - Normalize and validate paths
   - Reject `..` traversal
   - Require absolute paths (start with `/`)
   - Collapse multiple slashes

3. **Update `lib/jido_sandbox/vfs.ex`:**
   - Add dispatch functions that delegate to InMemory

4. **Add comprehensive tests:**
   - `test/jido_sandbox/vfs/in_memory_test.exs`
   - Write/read roundtrip
   - List directory contents
   - Delete files
   - mkdir behavior
   - Path normalization (accept valid, reject invalid)
   - Error cases (read non-existent, invalid paths)

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] All VFS operations work correctly
- [ ] Path traversal attacks blocked

---

## Step 4: Wire VFS into Sandbox

**Goal:** Connect VFS to Sandbox struct, make public API functional.

### Tasks

1. **Implement `JidoSandbox.Sandbox` operations:**
   ```elixir
   def write(%__MODULE__{} = s, path, content) do
     case VFS.write(s.vfs, path, content) do
       {:ok, vfs} -> {:ok, %{s | vfs: vfs}}
       {:error, reason} -> {:error, reason}
     end
   end
   
   def read(%__MODULE__{} = s, path), do: VFS.read(s.vfs, path)
   def list(%__MODULE__{} = s, dir), do: VFS.list(s.vfs, dir)
   # ... delete, mkdir
   ```

2. **Update `JidoSandbox.Sandbox.new/1`:**
   - Initialize with `VFS.new()`

3. **Add high-level API tests:**
   - `test/jido_sandbox/api_test.exs`
   - Full roundtrip: new → write → read → verify content
   - mkdir → write inside → list → verify
   - delete → verify gone
   - Error paths (read non-existent, etc.)

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] All public API VFS operations work end-to-end

---

## Step 5: Snapshot/Restore Implementation

**Goal:** Enable artifact persistence via in-memory snapshots.

### Tasks

1. **Implement in `JidoSandbox.Sandbox`:**
   ```elixir
   def snapshot(%__MODULE__{} = s) do
     id = "snap-#{s.next_snapshot_id}"
     snapshots = Map.put(s.snapshots, id, s.vfs)
     {:ok, id, %{s | snapshots: snapshots, next_snapshot_id: s.next_snapshot_id + 1}}
   end
   
   def restore(%__MODULE__{} = s, id) do
     case Map.fetch(s.snapshots, id) do
       {:ok, vfs} -> {:ok, %{s | vfs: vfs}}
       :error -> {:error, :unknown_snapshot}
     end
   end
   ```

2. **Add tests:**
   - `test/jido_sandbox/snapshot_test.exs`
   - Write file → snapshot → modify → restore → verify original
   - Multiple snapshots with different content
   - Restore non-existent snapshot → error

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] Snapshot/restore works correctly

---

## Step 6: Zoi Input Validation

**Goal:** Add schema validation for LLM tool inputs.

### Tasks

1. **Create `lib/jido_sandbox/schemas.ex`:**
   ```elixir
   defmodule JidoSandbox.Schemas do
     alias Zoi.Schema
     
     def path_schema do
       Schema.string()
       |> Schema.min_length(1)
       |> Schema.pattern(~r/\A\/(?!.*\.\.)/)
     end
     
     def write_schema do
       Schema.map(%{
         "path" => path_schema(),
         "content" => Schema.string()
       })
     end
     
     # read_schema, list_schema, delete_schema, mkdir_schema, eval_lua_schema
   end
   ```

2. **Add validation helpers:**
   - `validate_path/1`
   - `validate_write_params/1`
   - etc.

3. **Add tests:**
   - `test/jido_sandbox/schemas_test.exs`
   - Valid paths pass
   - Invalid paths fail (relative, `..`, empty)
   - Schema validation for each operation

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] All schemas reject invalid input

---

## Step 7: Lua Integration

**Goal:** Implement sandboxed Lua evaluation with VFS access.

### Tasks

1. **Create `lib/jido_sandbox/lua/runtime.ex`:**
   ```elixir
   defmodule JidoSandbox.Lua.Runtime do
     @moduledoc "Sandboxed Lua runtime with VFS bindings."
     
     def eval(code, vfs) do
       # Initialize Lua state
       # Register vfs.read, vfs.write, vfs.list, vfs.mkdir, vfs.delete
       # Strip dangerous globals (os, io, package, require, debug)
       # Execute code
       # Return {result, updated_vfs} or error
     end
   end
   ```

2. **Create `lib/jido_sandbox/lua/vfs_api.ex`:**
   - `deflua` bindings for VFS operations
   - Each function validates path and delegates to VFS

3. **Update `JidoSandbox.Sandbox.eval_lua/2`:**
   ```elixir
   def eval_lua(%__MODULE__{} = s, code) do
     case Lua.Runtime.eval(code, s.vfs) do
       {:ok, result, vfs} -> {:ok, result, %{s | vfs: vfs}}
       {:error, reason} -> {:error, reason, s}
     end
   end
   ```

4. **Add tests:**
   - `test/jido_sandbox/lua_test.exs`
   - Simple Lua expressions (return values)
   - VFS read/write from Lua
   - Verify Lua changes visible via `JidoSandbox.read/2`
   - Syntax errors return error tuple
   - Blocked globals (os, io) not accessible

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] Lua can read/write VFS
- [ ] Dangerous Lua features blocked

---

## Step 8: Polish, Docs, and CI

**Goal:** Finalize package for release.

### Tasks

1. **Create `.github/workflows/ci.yml`:**
   ```yaml
   name: CI
   on: [push, pull_request]
   jobs:
     test:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: erlef/setup-beam@v1
         - run: mix deps.get
         - run: mix quality
         - run: mix coveralls.github
   ```

2. **Create `.github/workflows/release.yml`:**
   - Hex publish workflow

3. **Expand documentation:**
   - `README.md` - Full API documentation with examples
   - `AGENTS.md` - Clear constraints for LLM usage
   - `usage-rules.md` - Tool building guidelines

4. **Update `CHANGELOG.md`:**
   - Document all MVP features

5. **Run `mix docs`:**
   - Fix any warnings

### Acceptance Criteria
- [ ] `mix quality` passes
- [ ] `mix coveralls` ≥90%
- [ ] `mix docs` builds without warnings
- [ ] CI workflow runs successfully

---

## Summary

| Step | Description | Complexity |
|------|-------------|------------|
| 1 | Project & QA Scaffolding | Small |
| 2 | Core Domain Design | Small/Medium |
| 3 | In-Memory VFS Implementation | Small/Medium |
| 4 | Wire VFS into Sandbox | Medium |
| 5 | Snapshot/Restore | Small/Medium |
| 6 | Zoi Input Validation | Small |
| 7 | Lua Integration | Medium |
| 8 | Polish, Docs, CI | Small/Medium |

**Total estimated effort:** 2-3 days

---

## Future Enhancements (Post-MVP)

- [ ] GenServer-based sandbox lifecycle (multi-tenant)
- [ ] Hako VFS adapters (ETS, S3, Git)
- [ ] Persistent Lua sessions
- [ ] Streaming output
- [ ] Telemetry events
- [ ] Resource limits enforcement
- [ ] Jido tool/skill integration
