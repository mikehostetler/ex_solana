# Ralph Loop Task

## Your Mission

Review projects/jido_htn/JIDO_HTN_STRATEGY.md, implement this and migrate jido_htn to use Zoi schemas instead of raw structs.

Example tasks:
- "Implement the missing tests for jido_ai/lib/jido_ai/strategy/react.ex"
- "Port jido_htn to use Zoi schemas instead of raw structs"
- "Add comprehensive documentation to all public modules in jido_behaviortree"

## Context

This is the Jido Workspace - a monorepo containing the Jido ecosystem:
- `projects/jido` - Core agent framework
- `projects/jido_ai` - AI/LLM integration layer
- `projects/jido_htn` - Hierarchical Task Network planner
- `projects/jido_behaviortree` - Behavior tree execution
- `projects/jido_action` - Composable action framework
- (See `config/workspace.exs` for full list)

## Instructions

1. Read @ralph/FIX_PLAN.md for current status and known issues

2. Work on the task incrementally:
   - Make small, focused changes
   - Run tests after each change: `mix test path/to/test.exs`
   - Fix any issues before moving on

3. Quality gates before committing:
   - `mix compile --warnings-as-errors`
   - `mix test` (for the affected project)
   - `mix format`

4. When you make progress:
   - Update @ralph/FIX_PLAN.md with what you did and what's next
   - `git add -A && git commit -m "type(scope): description"`
   - `git push`

5. When you discover issues or blockers:
   - Document them in @ralph/FIX_PLAN.md immediately
   - Try to resolve them before moving on
   - If stuck, document what you tried

6. When the task is fully complete:
   - Update FIX_PLAN.md status to COMPLETED
   - Create `ralph/DONE` file to signal completion
   - Final commit with summary

## Constraints

- Stay focused on the task - don't expand scope
- No placeholder implementations - full working code only
- Maintain existing code style and conventions (check AGENTS.md in each project)
- Don't modify unrelated code unless fixing a discovered bug

## Quality Standards

- All new code must have tests
- TypeSpecs on public functions
- @moduledoc on all modules
- Handle errors with `{:ok, result}` / `{:error, reason}` tuples
