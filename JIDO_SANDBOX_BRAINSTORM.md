# Jido Sandbox Brainstorm

**Date:** January 3, 2026  
**Subject:** `jido_sandbox` - A Pure BEAM Virtual Computer for AI Agents

---

## Executive Summary

`jido_sandbox` provides AI agents with an isolated, pure-BEAM "virtual computer" environment combining:

- **Kodo** - Virtual shell with POSIX-like commands
- **Hako** - Pluggable virtual filesystem (InMemory, ETS, Git, S3)
- **Lua** - Safe scripting runtime via tv-labs/lua

The package gives Jido agents a private filesystem and shell they can manipulate without any access to the real OS or disk. Lua scripting enables procedural logic—loops, conditionals, multi-step workflows—all confined to the sandbox.

**Tagline:** *"Give your agent its own tiny, programmable computer—entirely in BEAM memory."*

---

## 1. Package Architecture

### 1.1 Mental Model

```
┌─────────────────────────────────────────────────────────────┐
│                     JidoSandbox                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   Sandbox Instance                       ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────────┐ ││
│  │  │ Kodo Shell  │  │  Hako VFS   │  │   Lua Runtime    │ ││
│  │  │ (commands)  │  │ (adapters)  │  │   (scripting)    │ ││
│  │  └──────┬──────┘  └──────┬──────┘  └────────┬─────────┘ ││
│  │         │                │                   │           ││
│  │         └────────────────┴───────────────────┘           ││
│  │                    Unified Context                        ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  One sandbox = one virtual machine with:                     │
│  • Private filesystem (VFS workspace)                        │
│  • Shell session state (cwd, env, history)                   │
│  • Lua runtime with VFS/env APIs                             │
│  • Configurable resource limits                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 OTP Structure

```
JidoSandbox.Application
  └─ JidoSandbox.SandboxSupervisor (DynamicSupervisor)
       └─ JidoSandbox.SandboxServer (GenServer, per sandbox)
            ├─ Kodo.SessionServer (shell session)
            └─ Hako workspace (VFS mounts)
```

### 1.3 Dependencies

```elixir
defp deps do
  [
    {:kodo, "~> x.x"},     # Virtual shell
    {:hako, "~> x.x"},     # VFS adapters  
    {:lua, "~> x.x"},      # tv-labs/lua wrapper
    {:zoi, "~> x.x"}       # Schema validation
  ]
end
```

---

## 2. Core Public API

### 2.1 Sandbox Lifecycle

```elixir
# Start a new sandbox
{:ok, sandbox} = JidoSandbox.start_sandbox(
  name: :my_agent_sandbox,
  vfs: [adapter: :in_memory],
  limits: [
    wall_clock_ms: 5_000,
    lua_heap_bytes: 1_000_000,
    max_files: 1_000,
    max_bytes: 10_000_000
  ],
  env: %{"WORKSPACE" => "/project"},
  meta: %{agent_id: "agent_123", tenant_id: "tenant_abc"}
)

# Stop and cleanup
:ok = JidoSandbox.stop_sandbox(sandbox)

# Reset to fresh state (preserves config)
:ok = JidoSandbox.reset_sandbox(sandbox)
```

### 2.2 Shell Commands

```elixir
# Run shell command
{:ok, %{stdout: "file1.txt\nfile2.txt\n", stderr: "", exit: 0}} =
  JidoSandbox.shell(sandbox, "ls /project")

# Stream output for long-running commands
JidoSandbox.shell_stream(sandbox, "find / -name '*.lua'", fn
  {:stdout, line} -> IO.write(line)
  {:stderr, line} -> IO.write(:stderr, line)
  {:exit, code} -> IO.puts("Exited: #{code}")
end)
```

### 2.3 VFS Operations

```elixir
# Direct file operations
:ok = JidoSandbox.write_file(sandbox, "/project/main.lua", "print('hello')")
{:ok, content} = JidoSandbox.read_file(sandbox, "/project/main.lua")
{:ok, entries} = JidoSandbox.list(sandbox, "/project")
:ok = JidoSandbox.mkdir_p(sandbox, "/project/src/lib")
:ok = JidoSandbox.delete(sandbox, "/project/temp.txt")
```

### 2.4 Lua Evaluation

```elixir
# Execute Lua with VFS access
{:ok, result} = JidoSandbox.eval_lua(sandbox, """
  local content = vfs.read('/data/input.json')
  local data = json.decode(content)
  
  local filtered = {}
  for i, item in ipairs(data) do
    if item.score > 50 then
      table.insert(filtered, item)
    end
  end
  
  vfs.write('/data/output.json', json.encode(filtered))
  return #filtered
""")

# Stream print() output
JidoSandbox.eval_lua_stream(sandbox, code, fn output ->
  IO.write(output)
end)
```

### 2.5 Introspection

```elixir
%{
  id: "sandbox_abc123",
  limits: %JidoSandbox.Limits{...},
  mounts: [{"/", :in_memory, []}],
  usage: %{files: 42, bytes: 123_456},
  meta: %{agent_id: "agent_123"}
} = JidoSandbox.info(sandbox)
```

---

## 3. Key Features

### 3.1 Unified Virtual Computer

Shell, filesystem, and scripting share a single coherent context:
- Lua scripts call `vfs.read()` → same files the shell sees
- Shell commands modify files → Lua sees changes immediately
- Agents orchestrate both seamlessly

### 3.2 Pluggable VFS Backends

| Adapter | Use Case |
|---------|----------|
| `InMemory` | Ephemeral sandboxes, tests, demos |
| `ETS` | Persistent across restarts |
| `Git` | Read/write Git repos in isolation |
| `S3` | Cloud-backed workspaces |
| `GitHub` | GitHub API integration |

All adapters mediated through Hako mount table—no direct `File.*` access.

### 3.3 Lua as Procedural Brain

Agents can write procedural logic:
- Loops and conditionals
- Multi-step data processing
- File manipulation workflows
- Configuration templating

```lua
-- Example: Batch file processing
local files = vfs.ls('/data')
for i, name in ipairs(files) do
  if string.match(name, '%.json$') then
    local content = vfs.read('/data/' .. name)
    local processed = transform(content)
    vfs.write('/output/' .. name, processed)
  end
end
```

### 3.4 Multi-Tenant Isolation

- Each sandbox is completely isolated
- Per-sandbox resource quotas
- Tenant metadata for auditing
- Easy lifecycle management (create/reset/destroy)

### 3.5 Pure BEAM, Testable, Embeddable

- No OS subprocesses to manage
- No temp directories to clean up
- Spin up hundreds of sandboxes in tests
- Same API for humans and AI agents

---

## 4. Lua APIs (via `deflua`)

### 4.1 VFS API

```lua
-- Read/write files
content = vfs.read('/path/to/file')
vfs.write('/path/to/file', content)

-- Directory operations
files = vfs.ls('/directory')
vfs.mkdir('/new/directory')
vfs.rm('/file/to/delete')

-- Navigation
cwd = vfs.pwd()

-- Future: advanced operations
stat = vfs.stat('/file')  -- {size, mtime, type}
vfs.copy('/src', '/dst')
vfs.move('/src', '/dst')
```

### 4.2 Environment API

```lua
value = env.get('MY_VAR')
all_vars = env.list()
env.set('NEW_VAR', 'value')  -- session-scoped
```

### 4.3 JSON API

```lua
data = json.decode('{"key": "value"}')
text = json.encode({key = "value"})
```

### 4.4 Shell API (Optional, Guarded)

```lua
-- Execute shell commands from Lua
output = shell.run('ls /project')
shell.cd('/project/src')
```

---

## 5. Demo Scenarios

### Demo 1: AI Coding Playground

**Scenario:** LLM builds and iterates on a project entirely within the sandbox.

```elixir
# Setup
{:ok, sandbox} = JidoSandbox.start_sandbox(vfs: [adapter: :in_memory])

# Agent creates project structure
JidoSandbox.shell(sandbox, "mkdir /project")
JidoSandbox.shell(sandbox, "mkdir /project/src")
JidoSandbox.shell(sandbox, "mkdir /project/test")

# Agent writes code
JidoSandbox.write_file(sandbox, "/project/src/math.lua", """
  function add(a, b) return a + b end
  function multiply(a, b) return a * b end
  return {add = add, multiply = multiply}
""")

# Agent writes and runs tests
JidoSandbox.write_file(sandbox, "/project/test/test_math.lua", """
  local math = dofile('/project/src/math.lua')
  assert(math.add(2, 3) == 5, 'add failed')
  assert(math.multiply(4, 5) == 20, 'multiply failed')
  print('All tests passed!')
""")

{:ok, _} = JidoSandbox.eval_lua(sandbox, "dofile('/project/test/test_math.lua')")
# => "All tests passed!"
```

**Pitch:** *"The LLM has its own virtual computer to experiment, build, and test—all in BEAM memory."*

---

### Demo 2: Multi-Tenant Agent Workspaces

**Scenario:** Demonstrate isolation between multiple agent sandboxes.

```elixir
# Start sandboxes for different tenants
{:ok, alice} = JidoSandbox.start_sandbox(meta: %{tenant: "alice"})
{:ok, bob} = JidoSandbox.start_sandbox(meta: %{tenant: "bob"})
{:ok, carol} = JidoSandbox.start_sandbox(meta: %{tenant: "carol"})

# Each tenant writes their own data
JidoSandbox.write_file(alice, "/notes.txt", "Alice's secret notes")
JidoSandbox.write_file(bob, "/notes.txt", "Bob's private data")
JidoSandbox.write_file(carol, "/notes.txt", "Carol's workspace")

# Verify isolation
{:ok, "Alice's secret notes"} = JidoSandbox.read_file(alice, "/notes.txt")
{:ok, "Bob's private data"} = JidoSandbox.read_file(bob, "/notes.txt")

# Reset one tenant without affecting others
:ok = JidoSandbox.reset_sandbox(bob)
{:error, :not_found} = JidoSandbox.read_file(bob, "/notes.txt")
{:ok, "Alice's secret notes"} = JidoSandbox.read_file(alice, "/notes.txt")  # Still there!
```

**Pitch:** *"Host thousands of isolated agent sandboxes in one BEAM node."*

---

### Demo 3: Lua-Powered Data Pipeline

**Scenario:** Agent processes data using Lua scripting within the sandbox.

```elixir
# Seed input data
input_data = Jason.encode!([
  %{name: "Alice", score: 85},
  %{name: "Bob", score: 45},
  %{name: "Carol", score: 92},
  %{name: "Dave", score: 38}
])

{:ok, sandbox} = JidoSandbox.start_sandbox()
JidoSandbox.mkdir_p(sandbox, "/data")
JidoSandbox.write_file(sandbox, "/data/input.json", input_data)

# Process with Lua
{:ok, count} = JidoSandbox.eval_lua(sandbox, """
  local raw = vfs.read('/data/input.json')
  local data = json.decode(raw)
  
  local passed = {}
  for i, student in ipairs(data) do
    if student.score >= 50 then
      table.insert(passed, {
        name = student.name,
        grade = student.score >= 90 and 'A' or 'B'
      })
    end
  end
  
  vfs.write('/data/passed.json', json.encode(passed))
  return #passed
""")

# Verify output
{:ok, output} = JidoSandbox.read_file(sandbox, "/data/passed.json")
# => [{"name":"Alice","grade":"B"},{"name":"Carol","grade":"A"}]
```

**Pitch:** *"Ship custom ETL jobs for agents without leaving the BEAM."*

---

### Demo 4: Git Repository Workspace

**Scenario:** Agent explores and modifies a Git repository in isolation.

```elixir
# Mount a Git repo (readonly by default)
{:ok, sandbox} = JidoSandbox.start_sandbox(
  vfs: [
    mounts: [
      {"/", :in_memory, []},
      {"/repo", :git, [repo: "path/to/repo.git", branch: "feature-branch"]}
    ]
  ]
)

# Agent explores the codebase
{:ok, %{stdout: files}} = JidoSandbox.shell(sandbox, "ls /repo/lib")
{:ok, content} = JidoSandbox.read_file(sandbox, "/repo/lib/main.ex")

# Agent analyzes with Lua
{:ok, count} = JidoSandbox.eval_lua(sandbox, """
  local files = vfs.ls('/repo/lib')
  local ex_files = 0
  for i, name in ipairs(files) do
    if string.match(name, '%.ex$') then
      ex_files = ex_files + 1
    end
  end
  return ex_files
""")

# For writable mounts, agent can stage changes
JidoSandbox.write_file(sandbox, "/repo/lib/new_module.ex", "defmodule NewModule do\nend")
```

**Pitch:** *"Agents refactor Git repos without touching your working tree."*

---

### Demo 5: Interactive Virtual REPL

**Scenario:** Human and AI share the same sandbox for collaborative debugging.

```elixir
# Start interactive sandbox
{:ok, sandbox} = JidoSandbox.start_sandbox(
  name: :debug_session,
  vfs: [adapter: :ets, table: :debug_workspace]  # Persists across IEx restarts
)

# Human sets up test data
JidoSandbox.shell(sandbox, "mkdir /debug")
JidoSandbox.write_file(sandbox, "/debug/config.json", ~s({"debug": true}))

# AI agent investigates
{:ok, config} = JidoSandbox.read_file(sandbox, "/debug/config.json")

# AI runs diagnostic Lua script
{:ok, _} = JidoSandbox.eval_lua(sandbox, """
  local config = json.decode(vfs.read('/debug/config.json'))
  print('Debug mode:', config.debug and 'enabled' or 'disabled')
  
  -- Write diagnostic report
  vfs.write('/debug/report.txt', 'Analysis complete at ' .. os.date())
""")

# Human checks the report
{:ok, report} = JidoSandbox.read_file(sandbox, "/debug/report.txt")
```

**Pitch:** *"Your agents' playground doubles as a human-friendly virtual shell."*

---

## 6. Jido Integration

### 6.1 Sandbox Tools for Agents

```elixir
defmodule Jido.Tools.SandboxShell do
  @behaviour Jido.Tool

  def spec do
    %{
      name: "sandbox_shell",
      description: "Run shell commands in an isolated virtual environment",
      parameters: %{
        type: "object",
        properties: %{
          command: %{type: "string", description: "Shell command to execute"}
        },
        required: ["command"]
      }
    }
  end

  def call(%{"command" => cmd}, %{sandbox: sandbox}) do
    JidoSandbox.shell(sandbox, cmd)
  end
end

defmodule Jido.Tools.SandboxLua do
  @behaviour Jido.Tool

  def spec do
    %{
      name: "sandbox_lua",
      description: "Execute Lua code with VFS access in the sandbox",
      parameters: %{
        type: "object",
        properties: %{
          code: %{type: "string", description: "Lua code to execute"}
        },
        required: ["code"]
      }
    }
  end

  def call(%{"code" => code}, %{sandbox: sandbox}) do
    JidoSandbox.eval_lua(sandbox, code)
  end
end
```

### 6.2 Sandbox Skill

```elixir
defmodule Jido.Skills.Sandbox do
  use Jido.Skill

  @impl true
  def tools do
    [
      Jido.Tools.SandboxShell,
      Jido.Tools.SandboxLua,
      Jido.Tools.SandboxReadFile,
      Jido.Tools.SandboxWriteFile,
      Jido.Tools.SandboxListDir
    ]
  end

  @impl true
  def setup(ctx, opts) do
    {:ok, sandbox} = JidoSandbox.start_sandbox(opts[:sandbox_config] || [])
    {:ok, Map.put(ctx, :sandbox, sandbox)}
  end

  @impl true
  def teardown(ctx) do
    if sandbox = ctx[:sandbox] do
      JidoSandbox.stop_sandbox(sandbox)
    end
    :ok
  end
end
```

### 6.3 Agent Usage

```elixir
# Run agent with sandbox skill
{:ok, result} = Jido.Agent.run(agent,
  message: "Create a project structure and write a hello world script",
  skills: [Jido.Skills.Sandbox],
  skill_config: [
    sandbox_config: [
      vfs: [adapter: :in_memory],
      limits: [max_files: 100]
    ]
  ]
)
```

---

## 7. Security & Resource Limits

### 7.1 Security Defaults

| Layer | Protection |
|-------|------------|
| **Filesystem** | InMemory by default, no real disk access |
| **Paths** | Strict normalization, no `..` escapes |
| **Lua** | Sandboxed mode: no `os`, `io`, `package`, `require` |
| **Shell** | Only virtual Kodo commands, no real OS calls |
| **Mounts** | Per-sandbox mount table, no cross-tenant access |

### 7.2 Resource Limits

```elixir
%JidoSandbox.Limits{
  wall_clock_ms: 5_000,        # Max execution time per command
  lua_heap_bytes: 1_000_000,   # Lua memory limit
  max_files: 1_000,            # Max files in VFS
  max_bytes: 10_000_000,       # Max total storage
  max_depth: 20,               # Max directory depth
  max_concurrent: 5            # Max concurrent operations
}
```

### 7.3 Multi-Tenant Considerations

- **Tenant metadata**: Track `tenant_id` for auditing
- **Aggregate limits**: Max sandboxes per tenant
- **Isolation**: No shared workspace IDs across tenants
- **Lifecycle**: Easy bulk cleanup by tenant

---

## 8. Configuration

```elixir
# config/config.exs
config :jido_sandbox,
  default_vfs: [adapter: :in_memory],
  default_limits: [
    wall_clock_ms: 5_000,
    lua_heap_bytes: 1_000_000,
    max_bytes: 10_000_000,
    max_files: 1_000
  ],
  allowed_adapters: [:in_memory, :ets, :git],
  allowed_commands: ~w[ls cat cd mkdir rm echo pwd lua]a,
  lua_apis: [
    JidoSandbox.Lua.VFSAPI,
    JidoSandbox.Lua.EnvAPI,
    JidoSandbox.Lua.JsonAPI
  ]
```

---

## 9. Implementation Roadmap

### Phase 1: Core MVP (2-3 days)

- [ ] `JidoSandbox` module with lifecycle API
- [ ] `JidoSandbox.SandboxServer` GenServer
- [ ] Basic VFS operations (read/write/list/delete)
- [ ] Shell command execution via Kodo
- [ ] Lua evaluation with VFS API
- [ ] Resource limits (timeout, file count)
- [ ] Unit tests

### Phase 2: Integration (1-2 days)

- [ ] Jido tool modules
- [ ] Jido skill wrapper
- [ ] Integration tests with Jido agents
- [ ] Documentation and examples

### Phase 3: Polish (1-2 days)

- [ ] Additional Lua APIs (json, env)
- [ ] Telemetry events
- [ ] Error handling refinement
- [ ] Demo scenarios as tests
- [ ] Hex package prep

### Future Enhancements

- [ ] Persistent Lua sessions
- [ ] Streaming VFS for large files
- [ ] `vfs.stat`, `vfs.copy`, `vfs.move`
- [ ] Git versioning APIs (`commit`, `versions`, `restore`)
- [ ] Cross-sandbox communication
- [ ] Visual sandbox inspector (LiveView?)

---

## 10. Summary

`jido_sandbox` delivers:

1. **Isolated execution** - Pure BEAM, no real OS access
2. **Unified environment** - Shell + VFS + Lua in one context
3. **Flexible storage** - InMemory, ETS, Git, S3 backends
4. **Programmable** - Lua scripting for complex agent logic
5. **Multi-tenant** - Strong isolation with resource limits
6. **Jido-native** - First-class tools and skills integration

**Core value prop:** *Give your AI agents a safe, programmable virtual computer they can freely explore, modify, and script—without touching your real system.*
