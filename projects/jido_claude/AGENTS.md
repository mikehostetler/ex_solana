# AGENT.md - Jido Claude Development Guide

## Build/Test/Lint Commands

- `mix test` - Run tests (excludes flaky tests)
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture

This is an Elixir library for **Claude Code integration** with the Jido Agent framework:

- **JidoClaude** - Main entry module
- **JidoClaude.ClaudeSessionAgent** - Agent managing single Claude Code sessions
- **JidoClaude.StreamRunner** - Handles SDK streaming and message dispatch
- **JidoClaude.Signals** - Signal definitions for Claude events
- **JidoClaude.Error** - Splode-based error handling

### Actions

- **JidoClaude.Actions.StartSession** - Start a Claude session with prompt
- **JidoClaude.Actions.HandleMessage** - Handle messages during session
- **JidoClaude.Actions.CancelSession** - Cancel an active session

### Parent Integration

- **JidoClaude.Parent.SessionRegistry** - Track multiple sessions
- **JidoClaude.Parent.SpawnSession** - Spawn child ClaudeSessionAgent
- **JidoClaude.Parent.HandleSessionEvent** - Process signals from children
- **JidoClaude.Parent.CancelSession** - Cancel child sessions

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Actions use `use Jido.Action` with compile-time config (name, description, schema)
- Parameter validation via NimbleOptions schemas in action definitions
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Actions in `lib/jido_claude/actions/`, parent modules in `lib/jido_claude/parent/`
- Testing: Use ExUnit, test parameter validation and execution separately
- Naming: Snake_case for functions/variables, PascalCase for modules

## Git Commit Guidelines

Use **Conventional Commits** format for all commit messages:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Formatting, no code change
- `refactor` - Code change that neither fixes a bug nor adds a feature
- `test` - Adding or updating tests
- `chore` - Maintenance tasks, dependency updates

**Examples:**
```
feat(session): add timeout configuration for sessions
fix(stream): handle SDK disconnect gracefully
docs: update README with multi-session example
test(parent): add SessionRegistry unit tests
chore(deps): bump claude_agent_sdk to 0.8.0
```
