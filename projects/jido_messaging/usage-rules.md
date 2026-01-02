# LLM Usage Rules for Jido Messaging

This document provides guidelines for AI assistants (Claude, Cursor, etc.) when working with this codebase.

## Project Context

Jido Messaging is part of the Jido ecosystem - a framework for building intelligent agent systems. It provides messaging and notification infrastructure.

## Code Generation Rules

1. **Always use conventional commits** - Follow `type(scope): description` format
2. **Never add "ampcode" as contributor** - Do not include ampcode in commit messages or author trailers
3. **Follow existing patterns** - Match the code style in existing modules
4. **Write documentation first** - Add `@moduledoc` and `@doc` before implementation
5. **Include examples** - Use iex code blocks in documentation

## Quality Standards

- **All public functions need `@doc` with examples**
- **All modules need `@moduledoc`**
- **All functions with multiple clauses should have `@spec`**
- **Test coverage must be >= 90%**
- **Code must pass `mix quality`**

## Common Patterns

### Module Documentation Template

```elixir
defmodule JidoMessaging.MyModule do
  @moduledoc """
  Brief description of this module.

  ## Overview
  
  Detailed explanation of what this module does and why.
  
  ## Examples
  
      iex> JidoMessaging.MyModule.some_function(:input)
      {:ok, :result}
  """
  
  @doc """
  Brief description of the function.
  
  ## Examples
  
      iex> some_function(:input)
      {:ok, :result}
  """
  @spec some_function(atom()) :: {:ok, atom()} | {:error, term()}
  def some_function(input) do
    # implementation
  end
end
```

### Test Organization

- Place unit tests in `test/jido_messaging/` with `_test.exs` suffix
- Use `describe/` blocks to organize related tests
- Use `setup/` blocks for fixtures
- Use `assert` and pattern matching for assertions

### Error Handling

Use result tuples and pattern matching:

```elixir
defmodule JidoMessaging.Handler do
  def process(message) do
    with {:ok, validated} <- validate(message),
         {:ok, result} <- execute(validated) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## File Organization

- **lib/jido_messaging.ex** - Main public API
- **lib/jido_messaging/application.ex** - OTP supervisor
- **lib/jido_messaging/** - Feature modules (one per file)
- **test/jido_messaging/** - Test files mirroring lib structure

## Before Committing

1. Run `mix format` to format code
2. Run `mix quality` to check all standards
3. Run `mix test` to ensure tests pass
4. Run `mix coveralls.html` and verify coverage >= 90%
5. Review git diff for quality

## Documentation

- Write in Markdown
- Include `## Examples` sections with actual iex code
- Use `## Parameters` for function arguments
- Use `## Returns` for return value descriptions
- Link to related modules with backticks: \`JidoMessaging.Other\`

## Dialyzer Tips

- Add `@spec` annotations to functions
- Use proper `@type` definitions
- Handle nil cases explicitly
- Use `| nil` in type specs when appropriate

## Debugging

- Use `Logger.debug/1` for debug output
- Never use `IO.inspect/1` in production code
- Use `dbg/1` only in development/tests (Credo will warn)
- Include context in log messages

## Dependencies

Do not add dependencies without discussion. Current dependencies:

- **jason** - JSON support
- **zoi** - Schema validation
- **credo, dialyxir, ex_doc, excoveralls** - Dev tools

## Testing Checklist

- [ ] Test both success and error cases
- [ ] Test edge cases (empty input, nil, etc.)
- [ ] Use descriptive test names
- [ ] Coverage report shows >= 90%
- [ ] No flaky tests (mark with `@tag :flaky` if unavoidable)
