# ExSolana Usage Rules for LLMs

## Overview

This document provides usage rules for LLMs (Large Language Models) and AI coding assistants when working with the ExSolana package.

## Technology Stack Constraints

### MUST USE:
- **req** for HTTP requests (NOT Tesla, Mint, or HTTPoison)
- **zoi** for schema validation (NOT TypedStruct or NimbleOptions directly)
- **splode** for error handling (NOT plain tuples like `{:error, reason}`)

### FORBIDDEN:
- Do NOT use TypedStruct - use Zoi instead
- Do NOT use Tesla for HTTP - use Req instead
- Do NOT use tuple error returns - use Splode error classes

## Code Patterns

### Schema Definition with Zoi

```elixir
# CORRECT
use Zoi

schema "account" do
  field :lamports, :integer
  field :data, :binary
  field :owner, :binary
end

# INCORRECT
use TypedStruct

typedstruct do
  field :lamports, integer()
  field :data, binary()
end
```

### Error Handling with Splode

```elixir
# CORRECT
defmodule ExSolana.Error.InvalidKeyError do
  use Splode.Error,
    fields: [:key, :reason],
    class: :invalid
end

# In your code:
splode(InvalidKeyError, key: encoded, reason: "decode_failed")

# INCORRECT
{:error, "invalid key"}
```

### HTTP Requests with Req

```elixir
# CORRECT
client = Req.new(base_url: url, retry: :safe_transient)
Req.post(client, url: "/endpoint", json: params)

# INCORRECT
client = Tesla.client(middleware, Tesla.Adapter.Mint)
Tesla.post(client, "/endpoint", params)
```

## Module Organization

- Core types go in `lib/ex_solana/core/`
- RPC modules go in `lib/ex_solana/rpc/`
- Errors go in `lib/ex_solana/error.ex`
- Utilities go in `lib/ex_solana/util/`

## Testing Requirements

- All public functions MUST have tests
- Maintain 90%+ code coverage
- Use ExUnit for testing
- Use Mimic for mocking in tests

## Quality Standards

Before suggesting code changes, ensure:
1. `mix format` would pass
2. `mix credo --min-priority higher` would pass
3. `mix dialyzer` would pass
4. Code follows existing patterns in the codebase

## When Adding Features

1. Check if similar functionality already exists
2. Use existing patterns from the codebase
3. Add tests for new functionality
4. Update documentation (@moduledoc, @doc)
5. Update CHANGELOG.md

## Common Mistakes to Avoid

1. **Using old dependencies**: Don't suggest TypedStruct, use Zoi
2. **Wrong HTTP client**: Don't suggest Tesla, use Req
3. **Tuple errors**: Don't use `{:error, "message"}`, use Splode
4. **Missing tests**: Always include test files
5. **Missing docs**: Always document public functions with @doc

## Getting Help

- Read `AGENTS.md` for detailed agent instructions
- Check existing modules for patterns
- Refer to `GENERIC_PACKAGE_QA.md` in the workspace root
