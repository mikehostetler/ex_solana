# AGENTS.md - Jido Messaging Development Guide

## Project Overview

Jido Messaging is a messaging and notification system for the Jido ecosystem. It provides a foundation for inter-agent communication and notification delivery.

## Common Commands

### Development
- `mix compile` - Compile the project
- `mix test` - Run tests
- `mix format` - Format Elixir code

### Quality & Testing
- `mix quality` - Run all quality checks (format, compile, credo, dialyzer)
- `mix test` - Run tests with coverage checks
- `mix coveralls` - Generate coverage report
- `mix coveralls.html` - Generate HTML coverage report

### Documentation
- `mix docs` - Generate documentation
- `mix hex.build` - Build package for publishing

## Project Structure

```
jido_messaging/
├── .github/
│   └── workflows/           # GitHub Actions CI/CD
├── config/
│   ├── config.exs          # Base configuration
│   ├── dev.exs             # Development overrides
│   └── test.exs            # Test overrides
├── lib/
│   ├── jido_messaging.ex   # Main module
│   └── jido_messaging/
│       └── application.ex  # OTP Application supervisor
├── test/
│   ├── support/            # Test helpers and fixtures
│   └── jido_messaging_test.exs
├── .credo.exs              # Credo linting config
├── .formatter.exs          # Code formatter config
├── .gitignore
├── AGENTS.md               # This file
├── CHANGELOG.md            # Version history
├── CONTRIBUTING.md         # Contribution guidelines
├── LICENSE                 # Apache 2.0 License
├── mix.exs                 # Project manifest
├── mix.lock                # Dependency lock file
├── README.md               # Project overview
└── usage-rules.md          # LLM usage rules
```

## Code Style

- Follow standard Elixir conventions
- Use `Logger` for output instead of `IO.puts`
- Handle errors gracefully with pattern matching and pipe operator
- Write comprehensive @doc and @moduledoc documentation
- Include doctest examples in documentation

## Testing Standards

- Minimum 90% code coverage required
- Use ExCoveralls for coverage reporting
- Test support files in `test/support/`
- Use descriptive test names with `describe/` blocks

## Git Commit Guidelines

- Use conventional commit format: `type(scope): description`
- Types: feat, fix, docs, style, refactor, perf, test, chore, ci
- **Never add "ampcode" as a contributor** in commit messages
- Keep commits focused and atomic

## Dependency Management

### Runtime Dependencies
- `jason` - JSON encoding/decoding
- `zoi` - Schema validation

### Development Dependencies
- `credo` - Code linting
- `dialyxir` - Type checking with Dialyzer
- `ex_doc` - Documentation generation
- `excoveralls` - Test coverage
- `git_hooks` - Git hook management
- `git_ops` - Release automation

## Publishing

Before publishing to Hex:

1. Ensure `mix quality` passes
2. Ensure test coverage is >90%
3. Update CHANGELOG.md
4. Bump version in mix.exs following semver
5. Run `mix hex.build` to validate package
6. Use GitHub Actions release workflow to publish

## Common Issues

### Coverage Below Threshold
- Write tests for all public functions
- Use `exclude: :flaky` in test suite by default
- Run `mix coveralls.html` to identify gaps

### Dialyzer Errors
- Add proper `@spec` annotations
- Use `@type` definitions for complex types
- Check `priv/plts/` directory exists and is accessible

### Credo Warnings
- Run `mix credo` to identify issues
- Most warnings can be auto-fixed by `mix format`
- See `.credo.exs` for enabled checks
