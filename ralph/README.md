# Ralph Loop Agent Guide - Jido Workspace

## Overview

You are running inside a Ralph Wiggum loop - an automated outer loop that invokes you repeatedly until a task is complete. Your job is to make incremental progress on the task defined in `ralph/PROMPT.md`.

## Workspace Context

This is the **Jido Workspace** - a monorepo for the Jido AI agent ecosystem.

### Key Projects

| Project | Path | Purpose |
|---------|------|---------|
| jido | projects/jido | Core agent framework |
| jido_action | projects/jido_action | Composable action primitives |
| jido_signal | projects/jido_signal | Event/signal handling |
| jido_ai | projects/jido_ai | AI/LLM integration (ReAct, tools) |
| jido_htn | projects/jido_htn | Hierarchical Task Network planner |
| jido_behaviortree | projects/jido_behaviortree | Behavior tree execution |
| jido_chat | projects/jido_chat | Chat/conversation management |

### Essential Commands

```bash
# Workspace-wide
mix ws compile              # Compile all projects
mix ws test                 # Test all projects
mix ws.quality              # Run quality checks

# Single project
cd projects/jido_ai
mix test                    # Run tests
mix test path/to/test.exs   # Single test file
mix quality                 # Format, compile, dialyzer, credo

# Check before commit
mix compile --warnings-as-errors
mix format --check-formatted
```

### Code Patterns

**Zoi Schemas** (preferred for structs):
```elixir
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(),
  count: Zoi.integer() |> Zoi.default(0)
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
defstruct Zoi.Struct.struct_fields(@schema)
```

**Error Handling**:
```elixir
def do_thing(input) do
  with {:ok, validated} <- validate(input),
       {:ok, result} <- process(validated) do
    {:ok, result}
  end
end
```

**Actions** (jido_action):
```elixir
use Jido.Action,
  name: "my_action",
  description: "Does a thing",
  schema: Zoi.object(%{input: Zoi.string()})

def run(params, _context), do: {:ok, params.input}
```

## Loop Protocol

### Each Iteration You Should:

1. **Read FIX_PLAN.md** - Understand current state and what's next
2. **Make focused changes** - One logical unit of work
3. **Test your changes** - Run relevant tests
4. **Update FIX_PLAN.md** - Log what you did, update status
5. **Commit and push** - `git add -A && git commit -m "..." && git push`

### Signaling Completion

When the task is **fully complete**:
1. Update FIX_PLAN.md status to "COMPLETED"
2. Create file: `touch ralph/DONE`
3. Final commit

### If You Get Stuck

1. Document the blocker in FIX_PLAN.md
2. Try at least 2-3 different approaches
3. If still stuck after 3 attempts, document what you tried and move on to the next sub-task

## Quality Standards

- **Tests**: All new code must have tests
- **Types**: `@spec` on public functions, `@type` for custom types
- **Docs**: `@moduledoc` on modules, `@doc` on public functions
- **Format**: Run `mix format` before committing
- **No warnings**: `mix compile --warnings-as-errors` must pass

## Common Gotchas

1. **Path dependencies**: Projects use `jido_dep/4` for local deps in workspace
2. **Test tags**: Some tests are tagged `:flaky` and excluded by default
3. **Dialyzer**: First run is slow (builds PLT), subsequent runs are fast
4. **Firebase/HTTP tests**: Often mocked, check for `Req.Test` patterns

## Git Conventions

```bash
# Commit format
git commit -m "type(scope): description"

# Types: feat, fix, docs, test, refactor, chore
# Scope: project name or component

# Examples
git commit -m "feat(jido_ai): add streaming support to ReAct strategy"
git commit -m "fix(jido_htn): handle empty task queue in planner"
git commit -m "test(jido_action): add validation edge cases"
```

## Files to Keep Updated

- `ralph/FIX_PLAN.md` - Your progress and discoveries
- `ralph/AGENT.md` - Update if you learn new commands or patterns
- Project `AGENTS.md` - If you discover project-specific patterns

---
*This file guides the Claude Code agent in the Ralph loop.*
