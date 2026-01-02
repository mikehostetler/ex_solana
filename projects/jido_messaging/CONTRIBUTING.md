# Contributing to Jido Messaging

Thank you for your interest in contributing to Jido Messaging! This document provides guidelines and instructions for contributing.

## Development Setup

Clone the repository and install dependencies:

```bash
git clone https://github.com/epic-creative/jido_messaging.git
cd jido_messaging
mix setup
```

## Running Tests

```bash
# Run tests
mix test

# Run tests with coverage
mix coveralls

# Generate HTML coverage report
mix coveralls.html
```

## Quality Checks

All code must pass quality checks before submission:

```bash
# Run all quality checks
mix quality

# Individual checks
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --min-priority higher
mix dialyzer
```

## Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`

Example:

```
feat(messaging): add message queue support

This adds a persistent message queue implementation using ETS
for storing pending messages.

Closes #42
```

## Before Submitting a PR

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make your changes
4. Run `mix quality` and ensure all checks pass
5. Run `mix test` and ensure coverage stays above 90%
6. Commit with conventional format
7. Push to your fork and create a Pull Request

## Code Style

- Follow standard Elixir conventions
- Use pattern matching for control flow
- Write documentation for all public functions
- Include examples in @doc strings
