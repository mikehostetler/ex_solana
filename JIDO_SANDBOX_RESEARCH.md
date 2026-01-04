# Jido Sandbox Research

## Overview

This document researches the architecture for building a **Jido Sandbox** - an isolated virtual filesystem environment where ReAct-powered Jido agents perform file operations via **Hako VFS** inside a **Kodo virtual shell**, rather than accessing the real filesystem.

## Goals

When an LLM agent using the ReAct strategy needs to edit files, it should:
1. Operate in an isolated virtual environment
2. Use Hako's filesystem abstraction layer
3. Execute commands via Kodo's virtual shell
4. Never touch the real host filesystem directly

---

## Existing Architecture Analysis

### ReAct Strategy (`Jido.AI.Strategy.ReAct`)

The ReAct strategy implements a multi-step reasoning loop:

```
User Query → LLM Call → Tool Calls (or Final Answer) → Tool Results → Continue...
```

**Key Components:**

- **Pure State Machine**: `Jido.AI.ReAct.Machine` handles all state transitions
- **Signal Routing**: Routes signals like `react.user_query`, `reqllm.result`, `ai.tool_result`
- **Directives**: Emits `ReqLLMStream` and `ToolExec` directives for side effects
- **Tool Execution**: `Directive.ToolExec` spawns async tasks that run `Jido.Exec.run(action_module, args, context)`

**Configuration:**
```elixir
use Jido.Agent,
  strategy: {
    Jido.AI.Strategy.ReAct,
    tools: [MyAction1, MyAction2],
    system_prompt: "...",
    model: "anthropic:claude-haiku-4-5",
    max_iterations: 10
  }
```

### ReAct Demo Agent (`Jido.AI.ReActAgent`)

Convenience macro wrapping `use Jido.Agent` with ReAct strategy pre-configured:

```elixir
use Jido.AI.ReActAgent,
  name: "my_agent",
  tools: [Jido.Tools.Arithmetic.Add, Jido.Tools.Weather],
  max_iterations: 10
```

### Hako Filesystem Abstraction

Hako provides a unified API over multiple storage backends:

**Adapters:**
| Adapter | Use Case |
|---------|----------|
| `Hako.Adapter.Local` | Real filesystem |
| `Hako.Adapter.InMemory` | Ephemeral/testing |
| `Hako.Adapter.ETS` | Persistent in-memory |
| `Hako.Adapter.S3` | Cloud storage |
| `Hako.Adapter.Git` | Version-controlled |
| `Hako.Adapter.GitHub` | GitHub API |

**Core Operations:**
```elixir
filesystem = Hako.Adapter.InMemory.configure(name: :sandbox_fs)
:ok = Hako.write(filesystem, "file.txt", "content")
{:ok, content} = Hako.read(filesystem, "file.txt")
{:ok, entries} = Hako.list_contents(filesystem, "/")
:ok = Hako.create_directory(filesystem, "subdir/")
```

**Versioning:** Git, ETS, and InMemory adapters support `commit/3`, `revisions/3`, `read_revision/4`, `rollback/3`.

### Kodo Virtual Shell

Kodo is an Elixir-native virtual shell with:

- **Session Management**: Multiple isolated sessions per workspace
- **VFS Mount Table**: Routes paths to Hako adapters
- **Agent API**: Simple synchronous interface for programmatic access
- **Commands**: Unix-like commands (ls, cd, cat, echo, write, mkdir, rm, cp)

**Architecture:**
```
Kodo.Agent (sync API)
    ↓ subscribe/run_command
Kodo.SessionServer (GenServer per session)
    ↓ spawn Task
Kodo.CommandRunner
    ↓ calls
Kodo.Command modules
    ↓
Kodo.VFS → MountTable → Hako adapters
```

**Agent API:**
```elixir
{:ok, session} = Kodo.Agent.new(:my_workspace)
{:ok, output} = Kodo.Agent.run(session, "ls /")
:ok = Kodo.Agent.write_file(session, "/hello.txt", "Hello!")
{:ok, content} = Kodo.Agent.read_file(session, "/hello.txt")
{:ok, entries} = Kodo.Agent.list_dir(session, "/")
:ok = Kodo.Agent.stop(session)
```

### Jido Actions

Actions are composable units of work with:

- **Schema**: NimbleOptions or Zoi validation
- **Description**: Used for LLM tool generation
- **run/2**: Pure function returning `{:ok, result}` or `{:error, reason}`

**Example:**
```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    description: "Does something useful",
    schema: [
      input: [type: :string, required: true]
    ]

  def run(%{input: input}, _context) do
    {:ok, %{result: String.upcase(input)}}
  end
end
```

**Existing File Tools** (`Jido.Tools.Files`):
- `ReadFile`, `WriteFile`, `CopyFile`, `MoveFile`, `DeleteFile`, `MakeDirectory`, `ListDirectory`
- **Problem**: These use `File.*` directly on the real filesystem

### Jido Skills

Skills bundle actions, state, and signal routing:

```elixir
defmodule MySkill do
  use Jido.Skill,
    name: "my_skill",
    state_key: :my_skill,
    actions: [Action1, Action2],
    schema: Zoi.object(%{...}),
    signal_patterns: ["my_skill.*"]

  def mount(agent, config), do: {:ok, %{initialized: true}}
  def router(config), do: [{"my_skill.action", Action1}]
end
```

---

## Proposed Architecture

### 1. New Sandbox Actions

Create `Jido.Sandbox.Actions` that wrap Kodo/Hako operations instead of `File.*`:

```elixir
# Namespace: Jido.Sandbox.Actions (or Jido.KodoTools)

defmodule Jido.Sandbox.Actions.ReadFile do
  use Jido.Action,
    name: "sandbox.read_file",
    description: "Read a file from the virtual sandbox filesystem",
    schema: [
      path: [type: :string, required: true, doc: "Path to the file"]
    ]

  @impl true
  def run(%{path: path}, %{sandbox_session: session}) do
    case Kodo.Agent.read_file(session, path) do
      {:ok, content} -> {:ok, %{path: path, content: content}}
      {:error, error} -> {:error, format_error(error)}
    end
  end

  def run(_params, _context) do
    {:error, "sandbox_session not provided in context"}
  end
end
```

**Core Actions (Minimal Viable Set):**

| Action | Name | Schema | Description |
|--------|------|--------|-------------|
| `ReadFile` | `sandbox.read_file` | `path: string` | Read file contents |
| `WriteFile` | `sandbox.write_file` | `path: string, content: string` | Write/create file |
| `ListDirectory` | `sandbox.list_dir` | `path: string, recursive?: boolean` | List directory |
| `MakeDirectory` | `sandbox.mkdir` | `path: string` | Create directory |
| `Delete` | `sandbox.delete` | `path: string` | Delete file/dir |
| `Stat` | `sandbox.stat` | `path: string` | Get file metadata |
| `RunCommand` | `sandbox.run_command` | `command: string` | Execute shell command |

**Key Design Decisions:**
- All actions **require** `context.sandbox_session` and fail fast if missing
- Paths are logical VFS paths (e.g., `/workspace/foo.ex`)
- Results are JSON-friendly maps for LLM consumption
- Error messages are human-readable strings

### 2. Sandbox Skill

Bundle sandbox actions and state:

```elixir
defmodule Jido.Skills.KodoSandbox do
  use Jido.Skill,
    name: "sandbox",
    state_key: :sandbox,
    actions: [
      Jido.Sandbox.Actions.ReadFile,
      Jido.Sandbox.Actions.WriteFile,
      Jido.Sandbox.Actions.ListDirectory,
      Jido.Sandbox.Actions.MakeDirectory,
      Jido.Sandbox.Actions.Delete,
      Jido.Sandbox.Actions.Stat,
      Jido.Sandbox.Actions.RunCommand
    ],
    schema: Zoi.object(%{
      workspace_id: Zoi.atom() |> Zoi.default(:sandbox_workspace),
      session_id: Zoi.string() |> Zoi.optional(),
      status: Zoi.atom() |> Zoi.default(:uninitialized),
      mounts: Zoi.list(Zoi.any()) |> Zoi.default([])
    }),
    signal_patterns: ["sandbox.*"],
    tags: ["filesystem", "sandbox"]

  @impl true
  def mount(_agent, config) do
    {:ok, %{
      workspace_id: config[:workspace_id] || :sandbox_workspace,
      status: :uninitialized
    }}
  end
end
```

### 3. ReAct Integration

**Option A: Extend ReAct config with `tool_context` (Recommended)**

Modify `Jido.AI.Strategy.ReAct` to pass context to tool executions:

```elixir
# In build_config/2, add tool_context:
%{
  tools: tools_modules,
  reqllm_tools: reqllm_tools,
  actions_by_name: actions_by_name,
  system_prompt: ...,
  model: ...,
  max_iterations: ...,
  tool_context: Keyword.get(opts, :tool_context, %{})  # NEW
}

# In lift_directives/2, include context in ToolExec:
{:exec_tool, id, tool_name, arguments} ->
  case Map.fetch(actions_by_name, tool_name) do
    {:ok, action_module} ->
      [
        Directive.ToolExec.new!(%{
          id: id,
          tool_name: tool_name,
          action_module: action_module,
          arguments: arguments,
          context: config[:tool_context] || %{}  # NEW
        })
      ]
    :error -> []
  end
```

**Usage:**

```elixir
defmodule MySandboxedAgent do
  use Jido.Agent,
    name: "sandboxed_agent",
    skills: [Jido.Skills.KodoSandbox],
    strategy: {
      Jido.AI.Strategy.ReAct,
      tools: [
        Jido.Sandbox.Actions.ReadFile,
        Jido.Sandbox.Actions.WriteFile,
        Jido.Sandbox.Actions.ListDirectory,
        Jido.Sandbox.Actions.MakeDirectory,
        Jido.Sandbox.Actions.Delete,
        Jido.Sandbox.Actions.RunCommand
      ],
      tool_context: %{
        sandbox_session: "sess-xxx",  # Injected at runtime
        workspace_id: :sandbox_workspace
      },
      system_prompt: """
      You interact with a virtual filesystem sandbox.
      Use the provided sandbox tools to inspect and edit files.
      All paths are relative to the sandbox root (/).
      You cannot access the host filesystem.
      """,
      max_iterations: 12
    }
end
```

### 4. Signal Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SIGNAL FLOW                                    │
└─────────────────────────────────────────────────────────────────────────┘

1. User Query
   External caller → "react.user_query" signal
                     ↓
2. ReAct Strategy Routes
   signal_routes/1 maps:
   - "react.user_query" → :react_start
   - "reqllm.result" → :react_llm_result  
   - "ai.tool_result" → :react_tool_result
   - "reqllm.partial" → :react_llm_partial
                     ↓
3. LLM Call
   Machine emits {:call_llm_stream, id, conversation}
   → Directive.ReqLLMStream
   → DirectiveExec spawns async ReqLLM stream
   → Emits Signal.ReqLLMPartial chunks
   → Emits Signal.ReqLLMResult final
                     ↓
4. Tool Calls (Sandbox Actions)
   LLM returns tool_calls for "sandbox.read_file", etc.
   Machine emits {:exec_tool, id, tool_name, args}
   → Directive.ToolExec (with sandbox context!)
   → DirectiveExec spawns async task
   → Jido.Exec.run(Sandbox.Actions.ReadFile, args, %{sandbox_session: ...})
   → Kodo.Agent.read_file(session, path)
   → Emits Signal.ToolResult
                     ↓
5. Back to ReAct
   "ai.tool_result" → :react_tool_result
   Machine updates, may call LLM again or finish
```

### 5. Lifecycle Management

**Simple Approach (v1):**

Manage sandbox lifecycle in host code, not via directives:

```elixir
# Start agent with sandbox
def start_sandboxed_agent(workspace_id) do
  # 1. Create Kodo sandbox session
  {:ok, session} = Kodo.Agent.new(workspace_id)
  
  # 2. Create agent with sandbox context
  agent = MySandboxedAgent.new()
  
  # 3. Start AgentServer with sandbox info in strategy_opts
  {:ok, pid} = Jido.AgentServer.start(
    agent: agent,
    strategy_opts: [
      tool_context: %{
        sandbox_session: session,
        workspace_id: workspace_id
      }
    ]
  )
  
  {:ok, %{pid: pid, session: session}}
end

# Stop agent and cleanup sandbox
def stop_sandboxed_agent(%{pid: pid, session: session}) do
  :ok = Jido.AgentServer.stop(pid)
  :ok = Kodo.Agent.stop(session)
end
```

**Advanced Approach (Future):**

If explicit lifecycle control is needed, add directives:

```elixir
defmodule Jido.Sandbox.Directive.Start do
  @schema Zoi.struct(__MODULE__, %{
    workspace_id: Zoi.atom(),
    mounts: Zoi.list(Zoi.any()) |> Zoi.default([])
  }, coerce: true)
  
  # ... struct definition
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Sandbox.Directive.Start do
  def exec(directive, _signal, state) do
    {:ok, session} = Kodo.Agent.new(directive.workspace_id)
    signal = Signal.new!("sandbox.started", %{session_id: session, workspace_id: directive.workspace_id})
    # Update agent state with session info
    {:async, signal, state}
  end
end
```

---

## Implementation Plan

### Phase 1: Core Actions (1 day)

1. Create `lib/jido_sandbox/actions/` directory structure
2. Implement core actions:
   - `ReadFile` - wrap `Kodo.Agent.read_file/2`
   - `WriteFile` - wrap `Kodo.Agent.write_file/3`
   - `ListDirectory` - wrap `Kodo.Agent.list_dir/2`
   - `MakeDirectory` - wrap `Kodo.VFS.mkdir/2`
   - `Delete` - wrap `Kodo.VFS.delete/2`
   - `RunCommand` - wrap `Kodo.Agent.run/3`
3. Add tests for each action

### Phase 2: ReAct Integration (0.5 day)

1. Add `tool_context` option to `Jido.AI.Strategy.ReAct`
2. Pass context through `lift_directives/2` to `ToolExec`
3. Add integration tests

### Phase 3: Skill Bundle (0.5 day)

1. Create `Jido.Skills.KodoSandbox` skill
2. Add mount/router callbacks
3. Document usage patterns

### Phase 4: Documentation & Examples (0.5 day)

1. Create example sandboxed agent
2. Write usage guide
3. Add to README

---

## Trade-offs and Decisions

### Where Isolation Lives

**Chosen:** Isolation in Kodo/Hako (VFS) with in-memory or controlled mounts.

| Pros | Cons |
|------|------|
| Strong safety boundary | Tools must use Kodo instead of File |
| Can mount read-only host repo | Slight extra complexity |
| Ephemeral scratch or S3 mounts | |

### ReAct Strategy Extension

**Chosen:** Minimal extension via `tool_context` config option.

| Pros | Cons |
|------|------|
| Simple, reusable | Per-tool dynamic contexts need richer config |
| ReAct works with non-sandbox tools too | |
| Contained change | |

### Lifecycle Management

**Chosen:** Host code manages lifecycle (v1), not new directives.

| Pros | Cons |
|------|------|
| Avoids touching DirectiveExec | Less visible in signal graph |
| Better separation of concerns | More responsibility on host |
| Simpler v1 | |

### API Surface

**Chosen:** Minimal - read, write, list, mkdir, delete, run_command.

| Pros | Cons |
|------|------|
| Smaller surface easier for LLM | May need to add operations later |
| Reduces risk | (copy, move, glob, snapshot) |

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Context not wired → tools hit no sandbox | Actions require `sandbox_session`, fail loudly |
| Accidental host FS access via other tools | Don't expose `Jido.Tools.Files` to sandboxed agents |
| LLM explores huge trees / dumps large files | Limit recursion, truncate content, add quotas |
| Kodo session leaks | Pair agent lifetime with sandbox lifetime |

---

## Future Enhancements

When to revisit the design:

- **Multi-workspace agents**: Multiple sandboxes or mixed real/sandbox FS
- **Streaming shell output**: Through Jido signals, not just returned strings
- **Snapshots/rollback**: Apply patch, run tests, revert on failure
- **Dynamic mounts**: Git, S3 mounts controlled by LLM

Advanced features to consider:

1. `Jido.Sandbox.Manager` process per agent
2. Snapshot/rollback actions via Hako versioning
3. Richer Hako adapter usage (read-only Git mounts, S3 overlays)
4. Diff summaries after writes
5. Quotas (max files, total bytes)

---

## File Structure Proposal

```
lib/
├── jido_sandbox/
│   ├── actions/
│   │   ├── read_file.ex
│   │   ├── write_file.ex
│   │   ├── list_directory.ex
│   │   ├── make_directory.ex
│   │   ├── delete.ex
│   │   ├── stat.ex
│   │   └── run_command.ex
│   ├── skill.ex              # Jido.Skills.KodoSandbox
│   └── error.ex              # Error formatting helpers
└── jido_ai/
    └── strategy/
        └── react.ex          # Add tool_context support
```

---

## References

- [Jido.AI.Strategy.ReAct](projects/jido_ai/lib/jido_ai/strategy/react.ex)
- [Jido.AI.Directive](projects/jido_ai/lib/jido_ai/directive.ex)
- [Kodo.Agent](projects/kodo/lib/kodo/agent.ex)
- [Kodo.VFS](projects/kodo/lib/kodo/vfs.ex)
- [Hako README](projects/hako/README.md)
- [Jido.Action](projects/jido_action/lib/jido_action.ex)
- [Jido.Skill](projects/jido/lib/jido/skill.ex)
- [Jido.Tools.Files](projects/jido_action/lib/jido_tools/files.ex)
