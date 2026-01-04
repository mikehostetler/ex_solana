# Contributing to Jido Sandbox

Thank you for your interest in contributing to Jido Sandbox!

## Development Setup

1. Clone the repository
2. Run `mix setup` to install dependencies and git hooks
3. Run `mix test` to verify everything works

## Quality Standards

Before submitting a PR, ensure:

- `mix quality` passes (format, compile warnings, credo, dialyzer)
- `mix coveralls` shows ≥90% coverage
- All tests pass

## Commit Messages

We use conventional commits:

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `test:` - Test changes
- `chore:` - Maintenance tasks

## Code Style

- Follow standard Elixir conventions
- Keep functions small and focused
- Add typespecs to public functions
- Document public modules and functions
