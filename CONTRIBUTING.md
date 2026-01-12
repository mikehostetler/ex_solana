# Contributing to ExSolana

Thank you for your interest in contributing to ExSolana!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/agentjido/ex_solana.git
   cd ex_solana
   ```

2. Install dependencies:
   ```bash
   mix setup
   ```

3. Run the quality checks:
   ```bash
   mix quality
   ```

## Running Tests

```bash
# Run all tests
mix test

# Run tests with coverage
mix coveralls.html

# Run specific test file
mix test test/ex_solana/core/key_test.exs
```

## Code Quality

This project uses several tools to maintain code quality:

- **Formatter**: `mix format` - Code formatting
- **Credo**: `mix credo` - Linting and code analysis
- **Dialyzer**: `mix dialyzer` - Static type checking
- **ExCoveralls**: Test coverage

Before submitting a PR, run:
```bash
mix quality
```

## Conventional Commits

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code change, no fix or feature
- `perf`: Performance improvement
- `test`: Adding/fixing tests
- `chore`: Maintenance, deps, tooling
- `ci`: CI/CD changes

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes
4. Run `mix quality` to ensure code quality
5. Commit with conventional commit format
6. Push to your fork
7. Open a pull request

## Coding Standards

- Use **Zoi** for all schema definitions
- Use **Splode** for error handling
- Use **Req** for HTTP requests
- Write **@moduledoc** and **@doc** for all public modules/functions
- Maintain **90%+ test coverage**
- Follow Elixir style guide

## License

By contributing, you agree that your contributions will be licensed under the Apache-2.0 License.
