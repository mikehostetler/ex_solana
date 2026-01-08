# Contributing to JidoFlame

## Development Setup

```bash
git clone https://github.com/agentjido/jido_flame.git
cd jido_flame
mix deps.get
mix test
```

## Running Quality Checks

```bash
mix quality  # format, compile, credo, dialyzer
```

## Testing

```bash
# Unit tests
mix test

# With Fly.io integration (requires FLY_API_TOKEN)
mix test --include flame_fly
```

## Pull Request Process

1. Fork and create a feature branch
2. Write tests for new functionality
3. Ensure `mix quality` passes
4. Submit PR with conventional commit message

## Conventional Commits

Use format: `type(scope): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`
