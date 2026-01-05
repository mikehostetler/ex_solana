# Ralph Wiggum Loop - Agent Guide

> "Me fail English? That's unpossible!" - Ralph Wiggum

The Ralph loop is an automated outer loop that runs Claude Code repeatedly until a task is complete. Useful for large, multi-step tasks that benefit from incremental progress.

## Quick Start

```bash
# 1. Create a feature branch (required - won't run on main)
git checkout -b ralph/my-feature

# 2. Edit the prompt with your task
vim ralph/PROMPT.md

# 3. Start the loop
./ralph.sh
```

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Outer loop bash script (in repo root) |
| `ralph/PROMPT.md` | Your task description (edit this) |
| `ralph/FIX_PLAN.md` | Progress tracking, issues, learnings |
| `ralph/AGENT.md` | Jido-specific context for the agent |
| `ralph/DONE` | Signal file - create to stop loop |
| `ralph/logs/` | Iteration logs (auto-created) |

## Options

```bash
./ralph.sh [prompt_file] [--max-iterations N] [--cooldown SECONDS]

# Examples
./ralph.sh                                    # Uses ralph/PROMPT.md
./ralph.sh ralph/PROMPT.md --max-iterations 50
./ralph.sh my-task.md --cooldown 10
```

## How It Works

1. **Pre-flight checks**: Validates branch (blocks main/master), prompt file, CLI
2. **Loop**: Runs Claude Code with the prompt
3. **Agent**: Makes changes, updates FIX_PLAN.md, commits & pushes
4. **Check**: Looks for `ralph/DONE` or "COMPLETED" in FIX_PLAN.md
5. **Repeat**: Until done or max iterations reached

## Agent Protocol

Each iteration, the agent should:

1. **Read FIX_PLAN.md** - Understand current state
2. **Make focused changes** - One logical unit of work
3. **Test changes** - Run relevant tests
4. **Update FIX_PLAN.md** - Log progress, issues, learnings
5. **Commit & push** - `git add -A && git commit -m "..." && git push`

### Signaling Completion

When task is **fully complete**:
1. Update FIX_PLAN.md status to "COMPLETED"
2. Create file: `touch ralph/DONE`
3. Final commit

## Best Practices

- **Keep prompts simple** - 100 words often beats 1500
- **Be specific** about what success looks like
- **Stay on a feature branch** - easy to review/revert
- **Monitor early iterations** - catch issues before they compound
- **Check FIX_PLAN.md** - see what the agent learned

## Prompt Template

```markdown
# Your Task

[One clear sentence describing what needs to be done]

## Context

[2-3 sentences of relevant background]

## Success Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Tests pass
- [ ] No new warnings

## Constraints

- Don't modify X
- Use pattern Y
- Stay within scope
```

## Troubleshooting

### "Cannot run on main/master branch"
Create a feature branch: `git checkout -b ralph/my-feature`

### "Prompt file not found"
Create `ralph/PROMPT.md` with your task description

### "Claude Code CLI not found"
Install: `npm install -g @anthropic-ai/claude-code`

### Agent keeps doing the same thing
Check FIX_PLAN.md - agent may be stuck. Edit PROMPT.md with more specific guidance.

### Loop won't stop
Create `ralph/DONE` file or Ctrl+C to interrupt.

## Cost Estimates

Based on RepoMirror's experience:
- ~$10.50/hour for Sonnet model
- Most tasks complete in 10-50 iterations
- Simple features: $5-20
- Large migrations: $50-100+

---
*Reference: [ghuntley.com/ralph](https://ghuntley.com/ralph/)*
