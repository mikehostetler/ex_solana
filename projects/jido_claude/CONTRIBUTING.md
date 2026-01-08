# Contributing to Jido Claude

Thank you for your interest in contributing to Jido Claude! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install dependencies: `mix deps.get`
4. Run tests: `mix test`
5. Run quality checks: `mix quality`

## Development Workflow

1. Create a feature branch from `main`
2. Make your changes
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Run quality checks: `mix quality`
6. Submit a pull request

## Code Style

- Follow the existing code style and patterns
- Use `mix format` to format your code
- Ensure Dialyzer passes: `mix dialyzer`
- Follow Credo guidelines: `mix credo`

## Testing

- Add tests for all new functionality
- Maintain existing test coverage
- Use property-based testing where appropriate
- Include integration tests for complex features

### Test Coverage Policy

This project maintains a minimum test coverage threshold of **80%**. All contributions must:

- Maintain or improve the overall coverage percentage
- Include comprehensive tests for new code paths
- Not introduce uncovered code without justification

Check coverage locally:
```bash
# Generate coverage report
mix coveralls.html

# Check if coverage meets threshold
mix coveralls
```

## Documentation

- Update documentation for any API changes
- Add examples for new features
- Ensure `mix docs` builds without errors

### Documentation Standards

All public APIs must be properly documented:

- **@moduledoc**: All public modules must have module documentation
- **@doc**: All public functions must have function documentation
- **@spec**: All public functions must have type specifications
- **@typedoc**: Custom types must have type documentation

## Git Hooks and Conventional Commits

We use [`git_hooks`](https://hex.pm/packages/git_hooks) to enforce commit message conventions:

```bash
mix git_hooks.install
```

### Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only changes |
| `style` | Changes that don't affect code meaning |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `chore` | Changes to build process or auxiliary tools |
| `ci` | CI configuration changes |

### Examples

```bash
# Feature
git commit -m "feat(session): add custom timeout option"

# Bug fix
git commit -m "fix(stream): resolve memory leak on disconnect"

# Breaking change
git commit -m "feat(api)!: change StartSession schema"
```

## Pull Request Guidelines

- Provide a clear description of the changes
- Use commit messages following conventional commits
- Reference any related issues
- Include tests and documentation updates
- Ensure CI passes

## Questions?

Feel free to open an issue for questions or discussion about potential contributions.
