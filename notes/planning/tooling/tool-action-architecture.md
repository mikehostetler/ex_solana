# Tool Execution Architecture: Actions vs Handlers

## Overview

This document explores the architectural options for tool execution in JidoCode, specifically whether tools should be implemented as Jido Actions or continue using the current handler-based approach.

**Decision Required**: An ADR must be created under `notes/decisions/` to formally document the chosen approach.

---

## Current Architecture

### How Tools Are Executed Today

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   LLM Response  │ ──▶ │  Tools.Executor  │ ──▶ │ Handler.execute │
│  (tool_calls)   │     │  (parse & dispatch)│    │   (args, ctx)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                                                          ▼
                                                   {:ok, result}
```

### Handler Contract

Tools implement a simple 2-argument callback:

```elixir
@callback execute(params :: map(), context :: map()) ::
  {:ok, result :: term()} | {:error, reason :: term()}
```

Example:
```elixir
defmodule JidoCode.Tools.Handlers.FileSystem.ReadFile do
  def execute(%{"path" => path}, context) do
    with {:ok, project_root} <- get_project_root(context),
         {:ok, safe_path} <- Security.validate_path(path, project_root),
         {:ok, content} <- File.read(safe_path) do
      {:ok, content}
    end
  end
end
```

### Key Characteristics

1. **Decoupled from LLM**: Tool execution is external to the agent
2. **Simple contract**: Just `execute/2`, no lifecycle hooks
3. **Session-aware context**: `session_id` → `project_root` mapping
4. **Not Jido Actions**: Handlers are plain modules, not Actions/Skills

---

## The Question

Should tools be implemented as Jido Actions, allowing agents to invoke them through Jido's action system?

---

## Option A: Keep Current Handler Pattern

### Description

Continue using the current `execute(args, context)` handler pattern without Jido Actions.

### Architecture

```
LLMAgent ──▶ Executor ──▶ Handler.execute/2 ──▶ Result
   │
   └── (tool execution is external, called by TUI or other consumers)
```

### Advantages

- Simple and lightweight
- Already working well
- No additional abstraction layer
- Easy to understand and test
- Minimal boilerplate

### Disadvantages

- No schema validation via NimbleOptions
- No Action lifecycle hooks (before/after)
- Cannot compose tools into Skills
- Not integrated with Jido's orchestration patterns
- Tool execution is decoupled from agent (may be a feature or bug)

---

## Option B: Wrap Tools as Jido Actions

### Description

Each tool becomes a proper `Jido.Action` with schema validation and lifecycle support.

### Architecture

```elixir
defmodule JidoCode.Actions.Tools.ReadFile do
  use Jido.Action,
    name: "read_file",
    description: "Read the contents of a file",
    schema: [
      path: [type: :string, required: true, doc: "File path to read"]
    ]

  @impl true
  def run(params, context) do
    # Delegate to existing handler or implement directly
    JidoCode.Tools.Handlers.FileSystem.ReadFile.execute(params, context)
  end
end
```

### Advantages

- Consistent with Jido ecosystem
- Schema validation built-in (NimbleOptions)
- Lifecycle hooks (before_run, after_run, on_error)
- Can compose tools into Skills (multi-step workflows)
- Better error handling and recovery patterns
- Could use Jido's runner for orchestration

### Disadvantages

- More boilerplate per tool
- Heavier weight for simple operations
- Migration effort from current handlers
- May be overkill for simple file operations

---

## Option C: Hybrid Approach

### Description

Keep current handlers for execution, add thin Action wrappers for integration with Jido's action system.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Jido.Action Layer                     │
│  (schema validation, lifecycle, composability)          │
│                                                          │
│  JidoCode.Actions.Tools.ReadFile                        │
│    └── delegates to Handler                             │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                   Handler Layer                          │
│  (actual implementation, security, file operations)     │
│                                                          │
│  JidoCode.Tools.Handlers.FileSystem.ReadFile            │
└─────────────────────────────────────────────────────────┘
```

### Implementation

```elixir
# Action wrapper (thin layer)
defmodule JidoCode.Actions.Tools.ReadFile do
  use Jido.Action,
    name: "tool_read_file",
    schema: [path: [type: :string, required: true]]

  def run(params, context) do
    # Delegate to existing handler
    JidoCode.Tools.Handlers.FileSystem.ReadFile.execute(params, context)
  end
end

# Handler (unchanged)
defmodule JidoCode.Tools.Handlers.FileSystem.ReadFile do
  def execute(%{"path" => path}, context) do
    # Existing implementation
  end
end
```

### Advantages

- Best of both worlds
- Gradual migration path
- Actions available when needed (composition, validation)
- Handlers remain simple for direct execution
- No breaking changes to existing code

### Disadvantages

- Two layers to maintain
- Potential confusion about which to use when
- Some duplication of concerns

---

## Option D: Agent Auto-Execution (Agentic Loop)

### Description

Regardless of Action vs Handler, add capability for LLMAgent to automatically execute tools from LLM responses.

### Current Behavior

```elixir
# LLM returns tool_calls, but agent doesn't execute them
{:ok, response} = LLMAgent.chat_stream(agent, "read main.ex")
# response.tool_calls = [%{name: "read_file", ...}]

# External caller must execute tools
{:ok, result} = LLMAgent.execute_tool(agent, tool_call)
```

### Proposed Behavior

```elixir
# Agent automatically executes tools and continues conversation
{:ok, response} = LLMAgent.chat_stream(agent, "read main.ex",
  auto_execute_tools: true,
  max_tool_rounds: 10
)
# response includes tool results, agent may have made follow-up calls
```

### Considerations

- This is orthogonal to Action vs Handler decision
- Enables true agentic behavior (tool use → reasoning → more tools)
- Requires careful loop detection and limits
- May need approval workflow for certain tools

---

## Comparison Matrix

| Aspect | Current Handlers | Jido Actions | Hybrid | Auto-Execution |
|--------|-----------------|--------------|--------|----------------|
| Complexity | Low | Medium | Medium | High |
| Schema validation | Manual | Built-in | Both | N/A |
| Lifecycle hooks | None | Yes | Yes | N/A |
| Composability | None | Skills | Skills | N/A |
| Migration effort | None | High | Low | Medium |
| Breaking changes | None | Yes | No | No |
| Agentic behavior | External | External | External | Built-in |

---

## Questions to Answer in ADR

1. **Do we need schema validation via Jido Actions?**
   - Current `Tool.validate_args/2` may be sufficient

2. **Do we need to compose tools into Skills?**
   - Example: "refactor" skill = read → analyze → edit → test

3. **Should agents auto-execute tools?**
   - Or keep tool execution external (TUI-controlled)?

4. **What's the migration path?**
   - Can we adopt incrementally or is it all-or-nothing?

5. **Performance implications?**
   - Action overhead vs handler simplicity

---

## Recommendation

**Start with Option C (Hybrid)** as it:
- Preserves existing working code
- Allows gradual adoption of Actions where beneficial
- Enables future composition via Skills
- Has no breaking changes

**Consider Option D (Auto-Execution)** as a separate feature:
- Orthogonal to Action vs Handler decision
- Enables true agentic behavior
- Should have its own ADR

---

## Next Steps

1. **Create ADR**: `notes/decisions/ADR-XXXX-tool-action-architecture.md`
   - Document the chosen approach
   - Record rationale and trade-offs
   - Define migration strategy if applicable

2. **Prototype**: If adopting Actions, create one tool as Action to validate the pattern

3. **Document**: Update CLAUDE.md with architectural guidance for new tools

---

## Related Documents

- `notes/planning/tooling/phase-01-tools.md` - Tool implementation plan
- `lib/jido_code/tools/executor.ex` - Current tool execution
- `lib/jido_code/tools/handlers/` - Current handler implementations
- Jido documentation on Actions and Skills
