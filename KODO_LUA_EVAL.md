# Kodo-Lua Integration Research Report

**Date:** January 3, 2026  
**Author:** Research Investigation  
**Subject:** Integrating Lua Execution with Kodo Virtual Shell and Hako VFS

---

## Executive Summary

This report examines the technical architecture required to integrate Lua code execution with Kodo (virtual shell) and Hako (virtual file system adapter) to enable Lua scripts to perform file operations within a virtual infrastructure. The investigation reveals multiple viable integration approaches, with the most promising being a custom Lua command for Kodo that exposes VFS operations through a Lua API using the `deflua` macro pattern.

**Key Finding:** The tv-labs/lua library's `deflua` macro and API system provides an elegant mechanism to expose Elixir functions (like Hako VFS operations) to Lua code, creating a seamless bridge between Lua execution and the virtual infrastructure.

---

## 1. Current Architecture Analysis

### 1.1 LuaEval Action (Jido.Tools.LuaEval)

**Current Capabilities:**
- Executes Lua code in a sandboxed VM using tv-labs/lua (wrapper around Luerl)
- Provides timeout protection (default 1000ms)
- Supports global variable injection into Lua state
- Safe by default (disables `os`, `io`, `package`, `require`, etc.)
- Returns results in `:list` or `:first` mode

**Key Implementation Details:**
```elixir
# Initialize sandboxed Lua state
lua = Lua.new()  # Defaults to sandboxed mode

# Inject globals
lua = Lua.set!(lua, [:variable_name], value)

# Execute code
{values, _state} = Lua.eval!(lua, code)
```

**Limitations for Kodo Integration:**
- Currently isolated from any file system
- No built-in mechanism to access external resources
- Designed as a standalone action, not integrated with Kodo/Hako

### 1.2 Kodo Virtual Shell Architecture

**Command Pattern:**
```elixir
defmodule Kodo.Command.Example do
  @behaviour Kodo.Command
  
  def name, do: "example"
  def summary, do: "Description"
  def schema, do: Zoi.map(%{args: Zoi.array(Zoi.string())})
  
  def run(state, args, emit) do
    # state contains: id, workspace_id, cwd, env, meta
    # emit function for streaming output
    {:ok, nil} | {:ok, {:state_update, %{cwd: "/new"}}}
  end
end
```

**Session State Structure:**
- `workspace_id` - Identifies the VFS workspace
- `cwd` - Current working directory
- `env` - Environment variables
- `meta` - Additional metadata

**Key Modules:**
- `Kodo.SessionServer` - GenServer managing session state
- `Kodo.CommandRunner` - Executes commands in Task processes
- `Kodo.Command.Registry` - Maps command names to modules
- `Kodo.VFS` - Routes file operations to Hako adapters
- `Kodo.Agent` - Synchronous API for programmatic access

### 1.3 Hako VFS Adapter System

**Core Operations Available:**
```elixir
Kodo.VFS.read_file(workspace_id, path)      # {:ok, binary} | {:error, ...}
Kodo.VFS.write_file(workspace_id, path, content)  # :ok | {:error, ...}
Kodo.VFS.delete(workspace_id, path)         # :ok | {:error, ...}
Kodo.VFS.list_contents(workspace_id, path)  # {:ok, [stats]} | {:error, ...}
Kodo.VFS.create_directory(workspace_id, path) # :ok | {:error, ...}
```

**Adapter Ecosystem:**
- `Hako.Adapter.Local` - Real file system
- `Hako.Adapter.InMemory` - Ephemeral in-memory storage (versioning support)
- `Hako.Adapter.ETS` - Persistent ETS storage (versioning support)
- `Hako.Adapter.S3` - Cloud storage (AWS S3/Minio)
- `Hako.Adapter.Git` - Git repository access (versioning support)
- `Hako.Adapter.GitHub` - GitHub API integration

**Mount Table System:**
```elixir
# VFS routes paths to appropriate adapters via mount points
Kodo.VFS.mount(:workspace, "/", Hako.Adapter.InMemory, [name: :root])
Kodo.VFS.mount(:workspace, "/data", Hako.Adapter.ETS, [table: :my_table])
```

---

## 2. Integration Design Approaches

### 2.1 Approach A: Lua Command with VFS API (Recommended)

**Overview:** Create a new Kodo command `lua` that executes Lua code with access to a custom file system API.

**Implementation Strategy:**

1. **Define Lua API Module using `deflua`:**

```elixir
defmodule Kodo.Lua.VFSAPI do
  use Lua.API, scope: "vfs"
  
  # Read file contents
  deflua read(path), state do
    workspace_id = Lua.get_private!(state, :workspace_id)
    cwd = Lua.get_private!(state, :cwd)
    full_path = resolve_path(cwd, path)
    
    case Kodo.VFS.read_file(workspace_id, full_path) do
      {:ok, content} -> {[content], state}
      {:error, reason} -> raise_lua_error(reason)
    end
  end
  
  # Write file contents
  deflua write(path, content), state do
    workspace_id = Lua.get_private!(state, :workspace_id)
    cwd = Lua.get_private!(state, :cwd)
    full_path = resolve_path(cwd, path)
    
    case Kodo.VFS.write_file(workspace_id, full_path, content) do
      :ok -> {["ok"], state}
      {:error, reason} -> raise_lua_error(reason)
    end
  end
  
  # List directory contents
  deflua ls(path \\ "."), state do
    workspace_id = Lua.get_private!(state, :workspace_id)
    cwd = Lua.get_private!(state, :cwd)
    full_path = resolve_path(cwd, path)
    
    case Kodo.VFS.list_contents(workspace_id, full_path) do
      {:ok, entries} -> 
        names = Enum.map(entries, & &1.name)
        {encoded, state} = Lua.encode!(state, names)
        {[encoded], state}
      {:error, reason} -> raise_lua_error(reason)
    end
  end
  
  # Create directory
  deflua mkdir(path), state do
    workspace_id = Lua.get_private!(state, :workspace_id)
    cwd = Lua.get_private!(state, :cwd)
    full_path = resolve_path(cwd, path)
    
    case Kodo.VFS.create_directory(workspace_id, full_path) do
      :ok -> {["ok"], state}
      {:error, reason} -> raise_lua_error(reason)
    end
  end
  
  # Delete file or directory
  deflua rm(path), state do
    workspace_id = Lua.get_private!(state, :workspace_id)
    cwd = Lua.get_private!(state, :cwd)
    full_path = resolve_path(cwd, path)
    
    case Kodo.VFS.delete(workspace_id, full_path) do
      :ok -> {["ok"], state}
      {:error, reason} -> raise_lua_error(reason)
    end
  end
  
  # Get current working directory
  deflua pwd(), state do
    cwd = Lua.get_private!(state, :cwd)
    {[cwd], state}
  end
  
  defp resolve_path(_cwd, "/" <> _ = path), do: Path.expand(path)
  defp resolve_path(cwd, path), do: Path.join(cwd, path) |> Path.expand()
  
  defp raise_lua_error(reason) do
    raise Lua.RuntimeException, message: "VFS error: #{inspect(reason)}"
  end
end
```

2. **Create Kodo Command:**

```elixir
defmodule Kodo.Command.Lua do
  @moduledoc """
  Execute Lua code with VFS access.
  
  ## Usage
  
      lua "return vfs.read('/hello.txt')"
      lua "vfs.write('/test.txt', 'Hello from Lua!')"
      lua "local files = vfs.ls('/'); for i, f in ipairs(files) do print(f) end"
  """
  
  @behaviour Kodo.Command
  
  @impl true
  def name, do: "lua"
  
  @impl true
  def summary, do: "Execute Lua code with VFS access"
  
  @impl true
  def schema do
    Zoi.map(%{
      args: Zoi.array(Zoi.string()) |> Zoi.min_length(1)
    })
  end
  
  @impl true
  def run(state, args, emit) do
    code = Enum.join(args.args, " ")
    
    # Initialize Lua with VFS API
    lua =
      Lua.new()
      |> Lua.put_private(:workspace_id, state.workspace_id)
      |> Lua.put_private(:cwd, state.cwd)
      |> Lua.load_api(Kodo.Lua.VFSAPI)
      |> maybe_load_custom_apis()
    
    # Redirect Lua print to Kodo emit
    lua = Lua.set!(lua, [:print], fn args ->
      output = args |> Enum.map(&to_string/1) |> Enum.join("\t")
      emit.({:output, output <> "\n"})
      []
    end)
    
    try do
      {results, _lua_state} = Lua.eval!(lua, code)
      
      # Emit results if any
      unless results == [] or results == [nil] do
        formatted = format_results(results)
        emit.({:output, formatted <> "\n"})
      end
      
      {:ok, nil}
    rescue
      e in Lua.CompilerException ->
        {:error, Kodo.Error.shell(:lua_compile_error, %{message: Exception.message(e)})}
      
      e in Lua.RuntimeException ->
        {:error, Kodo.Error.shell(:lua_runtime_error, %{message: Exception.message(e)})}
    end
  end
  
  defp format_results(results) do
    results
    |> Enum.map(&inspect/1)
    |> Enum.join("\t")
  end
  
  defp maybe_load_custom_apis(lua) do
    # Can be extended to load additional APIs
    lua
  end
end
```

**Usage Examples:**

```bash
# In Kodo shell
kodo> lua "return vfs.read('/config.txt')"
{"host": "localhost"}

kodo> lua "vfs.write('/output.log', 'Processing started\\n')"

kodo> lua "local dirs = vfs.ls('/'); for i, name in ipairs(dirs) do print(name) end"
config.txt
output.log
data

kodo> lua "local content = vfs.read('/data.json'); vfs.write('/backup.json', content)"
```

**Advantages:**
- ✅ Natural integration with Kodo's command system
- ✅ Lua code has access to session context (cwd, workspace_id)
- ✅ Can leverage existing VFS mount table and adapter system
- ✅ Uses proven `deflua` pattern from tv-labs/lua
- ✅ Private state (workspace_id, cwd) hidden from Lua code
- ✅ Streaming output via `emit` function
- ✅ Easy to extend with additional APIs

**Disadvantages:**
- ⚠️ Requires registering new command in Kodo.Command.Registry
- ⚠️ Error handling needs careful consideration

### 2.2 Approach B: Extended LuaEval Action with VFS Injection

**Overview:** Extend the existing `Jido.Tools.LuaEval` action to optionally accept a VFS context.

**Implementation:**

```elixir
defmodule Jido.Tools.LuaEval do
  # ... existing code ...
  
  schema: [
    # ... existing schema ...
    vfs_context: [
      type: :map,
      default: nil,
      doc: "Optional VFS context with workspace_id and cwd for file operations"
    ]
  ]
  
  defp do_run(params) do
    # ... existing setup ...
    
    lua = 
      if vfs_context = Map.get(params, :vfs_context) do
        Lua.new()
        |> Lua.put_private(:workspace_id, vfs_context.workspace_id)
        |> Lua.put_private(:cwd, vfs_context.cwd)
        |> Lua.load_api(Jido.Lua.VFSAPI)
      else
        Lua.new()
      end
    
    # ... rest of execution ...
  end
end
```

**Advantages:**
- ✅ Reuses existing LuaEval infrastructure
- ✅ Optional VFS integration (backward compatible)

**Disadvantages:**
- ⚠️ Doesn't integrate with Kodo's shell UX
- ⚠️ No access to Kodo's emit function for streaming
- ⚠️ Requires passing context through action parameters
- ⚠️ Not suitable for interactive shell use

### 2.3 Approach C: Lua Script Files in Kodo

**Overview:** Add a command to execute Lua scripts from VFS files.

```elixir
defmodule Kodo.Command.LuaScript do
  def run(state, args, emit) do
    script_path = resolve_path(state.cwd, args.file)
    
    # Read script from VFS
    {:ok, code} = Kodo.VFS.read_file(state.workspace_id, script_path)
    
    # Execute with VFS API
    # ... similar to Approach A ...
  end
end
```

**Usage:**
```bash
kodo> write process.lua "local data = vfs.read('/input.txt'); vfs.write('/output.txt', data)"
kodo> lua-script process.lua
```

**Advantages:**
- ✅ Enables script reuse and version control
- ✅ Complements Approach A well

---

## 3. Recommended Implementation Plan

### Phase 1: Core Lua Command (Approach A)

**Priority:** HIGH

1. Create `Kodo.Lua.VFSAPI` module with `deflua` functions:
   - `vfs.read(path)` - Read file contents
   - `vfs.write(path, content)` - Write file
   - `vfs.ls(path)` - List directory
   - `vfs.mkdir(path)` - Create directory
   - `vfs.rm(path)` - Delete file/directory
   - `vfs.pwd()` - Get current directory

2. Implement `Kodo.Command.Lua` with:
   - Schema validation for Lua code string
   - Private state injection (workspace_id, cwd)
   - API loading and print redirection
   - Comprehensive error handling

3. Register command in `Kodo.Command.Registry`

4. Add tests for:
   - Basic Lua execution
   - VFS read/write operations
   - Directory operations
   - Error conditions
   - Path resolution (absolute/relative)

### Phase 2: Extended APIs

**Priority:** MEDIUM

5. Add utility APIs:
   - `env.get(name)` / `env.set(name, value)` - Environment variables
   - `json.encode(table)` / `json.decode(str)` - JSON operations
   - `string.*` enhancements for text processing

6. Add Kodo shell integration:
   - `shell.run(command)` - Execute other Kodo commands from Lua
   - `shell.cd(path)` - Change directory

### Phase 3: Script Execution (Approach C)

**Priority:** LOW

7. Implement `lua-script` or `luafile` command
8. Support for multi-file Lua projects
9. Module system for Lua libraries in VFS

---

## 4. Technical Considerations

### 4.1 Sandboxing and Security

**Current Safety Measures:**
- Lua.new() defaults to sandboxed mode (disables `os`, `io`, `package`)
- Timeout protection (configurable)
- No direct access to BEAM internals

**Additional Recommendations:**
- Limit VFS operations to workspace mount points
- Validate all paths to prevent directory traversal
- Consider quota limits for file writes
- Add memory limits for Lua execution

### 4.2 State Management

**Private State Pattern:**
```elixir
lua = 
  Lua.new()
  |> Lua.put_private(:workspace_id, state.workspace_id)
  |> Lua.put_private(:cwd, state.cwd)
  |> Lua.put_private(:user_meta, state.meta)
```

**Benefits:**
- Context available to `deflua` functions
- Not accessible from Lua code
- Secure credential/session management

### 4.3 Error Handling Strategy

**Lua Errors → Kodo Errors:**
```elixir
rescue
  e in Lua.CompilerException ->
    {:error, Kodo.Error.shell(:lua_compile_error, %{
      message: Exception.message(e),
      code: code
    })}
  
  e in Lua.RuntimeException ->
    {:error, Kodo.Error.shell(:lua_runtime_error, %{
      message: Exception.message(e),
      code: code
    })}
```

**VFS Errors in Lua:**
```elixir
deflua read(path), state do
  case Kodo.VFS.read_file(workspace_id, path) do
    {:ok, content} -> {[content], state}
    {:error, %Kodo.Error{} = err} ->
      # Convert to Lua error
      raise Lua.RuntimeException, message: "#{err.type}: #{err.message}"
  end
end
```

### 4.4 Performance Considerations

**Execution Model:**
- Lua commands run in Kodo's Task.Supervisor
- Each execution creates fresh Lua state
- No persistent Lua state between commands (by default)

**Optimization Opportunities:**
- Cache compiled Lua chunks (using ~LUA sigil)
- Pre-load common APIs
- Stream large file reads/writes

---

## 5. Example Use Cases

### 5.1 Data Processing Pipeline

```lua
-- Read JSON data
local raw = vfs.read('/data/input.json')
local data = json.decode(raw)

-- Process
local results = {}
for i, item in ipairs(data) do
  if item.score > 50 then
    table.insert(results, item.name)
  end
end

-- Write output
local output = json.encode(results)
vfs.write('/data/output.json', output)
```

### 5.2 File Tree Processing

```lua
-- Recursively list directory
function list_recursive(path)
  local items = vfs.ls(path)
  local result = {}
  
  for i, name in ipairs(items) do
    local full_path = path .. "/" .. name
    table.insert(result, full_path)
    
    -- If directory, recurse (would need stat() API)
    -- local more = list_recursive(full_path)
    -- for j, sub in ipairs(more) do
    --   table.insert(result, sub)
    -- end
  end
  
  return result
end

local all_files = list_recursive('/projects')
for i, f in ipairs(all_files) do
  print(f)
end
```

### 5.3 Configuration Management

```lua
-- Read config template
local template = vfs.read('/templates/app.conf')

-- Get environment variables
local host = env.get('DB_HOST') or 'localhost'
local port = env.get('DB_PORT') or '5432'

-- Simple substitution
local config = string.gsub(template, "{{HOST}}", host)
config = string.gsub(config, "{{PORT}}", port)

-- Write configured file
vfs.write('/config/app.conf', config)
print('Configuration written')
```

---

## 6. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Infinite loops blocking shell | HIGH | Timeout protection in CommandRunner |
| Path traversal attacks | HIGH | Strict path validation and workspace boundaries |
| Memory exhaustion | MEDIUM | Lua max_heap_bytes limit |
| Breaking VFS mount table | MEDIUM | Validate operations against mount permissions |
| Complex error messages confusing users | LOW | Wrap Lua errors in user-friendly format |

---

## 7. Testing Strategy

### Unit Tests
- VFS API functions in isolation
- Path resolution (absolute, relative, edge cases)
- Error handling for each VFS operation
- Lua compilation and runtime errors

### Integration Tests
- Full Kodo command execution flow
- Multi-file operations
- Session state preservation
- Concurrent command execution

### E2E Tests (using Kodo.TestShell)
```elixir
shell = Kodo.TestShell.start!()

# Setup
Kodo.TestShell.run(shell, "write /test.txt 'Hello'")

# Test Lua read
{:ok, output} = Kodo.TestShell.run(shell, "lua \"return vfs.read('/test.txt')\"")
assert output =~ "Hello"

# Test Lua write
Kodo.TestShell.run(shell, "lua \"vfs.write('/output.txt', 'World')\"")
{:ok, content} = Kodo.TestShell.run(shell, "cat /output.txt")
assert content == "World"
```

---

## 8. Future Enhancements

### 8.1 Persistent Lua Sessions
- Maintain Lua state across commands
- `lua-session start/stop` commands
- Shared state between scripts

### 8.2 Advanced VFS Operations
```lua
-- File metadata
local stat = vfs.stat('/file.txt')
print(stat.size, stat.mtime)

-- Streaming for large files
vfs.read_stream('/large.csv', function(chunk)
  process(chunk)
end)

-- Versioning (for Git/ETS adapters)
vfs.commit('/project', 'Updated configuration')
local versions = vfs.versions('/config.json')
vfs.restore('/config.json', versions[1].id)
```

### 8.3 Kodo Command Composition
```lua
-- Execute shell commands from Lua
local output = shell.run('ls /data')
print('Found files:', output)

shell.cd('/projects/app')
local tests = shell.run('cat test_results.txt')
```

### 8.4 Multi-workspace Access
```lua
-- Access multiple workspaces
local ws1 = workspace.open('project_a')
local ws2 = workspace.open('project_b')

local data = ws1.read('/data.json')
ws2.write('/backup.json', data)
```

---

## 9. Conclusion

**Recommendation:** Implement **Approach A** (Lua Command with VFS API) as the primary integration strategy.

**Rationale:**
1. Natural fit with Kodo's command-based architecture
2. Leverages tv-labs/lua's proven `deflua` pattern for API exposure
3. Provides secure, isolated execution with private state
4. Enables powerful scripting while maintaining sandboxing
5. Straightforward path to future enhancements

**Next Steps:**
1. Create `Kodo.Lua.VFSAPI` module with core file operations
2. Implement `Kodo.Command.Lua` with comprehensive error handling
3. Write unit and integration tests
4. Document usage patterns and examples
5. Consider user feedback for additional APIs

**Estimated Effort:** 2-3 days for Phase 1 implementation

This integration will enable powerful automation and scripting capabilities within Kodo's virtual shell environment while maintaining security and isolation guarantees.
