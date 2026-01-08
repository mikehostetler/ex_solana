# AGENTS.md - JidoFlame Development Guide

## Build/Test/Lint Commands

- `mix test` - Run tests (excludes flaky)
- `mix test --include flaky` - Run all tests
- `mix test --include flame_fly` - Run Fly.io integration tests
- `mix quality` or `mix q` - Full quality check
- `mix format` - Format code
- `mix dialyzer` - Type checking
- `mix jido.flame.doctor` - Diagnostic check

## Architecture

JidoFlame integrates FLAME with Jido agents:

- **Directives** - Pure data structs describing FLAME operations
- **DirectiveExec** - Executes directives against FLAME
- **Owner** - GenServer managing FLAME links, decoupling from agent restarts
- **Registries** - Track agent PIDs and child owners
- **Actions** - Jido.Action wrappers for directives
- **Skill** - Bundles actions for easy agent composition

## Key Patterns

### Owner Pattern
The Owner process calls `FLAME.place_child/3` and owns the link. This protects remote work from parent agent restarts.

### Signal Flow
Remote child → Owner → AgentRegistry lookup → Parent Agent

## Code Style

- Use Zoi for directive schemas
- Use Splode for error handling
- Follow `Jido.Action` patterns for actions
- All directives are pure data structs
- Execution happens only in DirectiveExec

## Git Commit Guidelines

Use conventional commits: `feat(directive): add timeout option`
