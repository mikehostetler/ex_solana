# ExSolana - Agent Instructions

## Purpose

ExSolana is the core Solana blockchain library for Elixir, providing RPC communication, WebSocket subscriptions, IDL handling, transaction building, and decoding functionality.

## Technology Stack

- **HTTP Client**: `req` (modern, composable HTTP client)
- **Schema Validation**: `zoi` (unified schema and validation)
- **Error Handling**: `splode` (structured error classes)
- **Serialization**: `jason` (JSON), `protobuf` (gRPC)
- **Cryptography**: `ed25519`, `basefiftyeight`, `mnemonic`, `block_keys`
- **WebSocket**: `websockex` (fallback support)

## Code Organization

### Core Types (`lib/ex_solana/core/`)
- `key.ex` - Public key generation and encoding
- `account.ex` - Account data structures
- `tx.ex` - Transaction structures
- `tx_core.ex` - Transaction core logic
- `tx_builder.ex` - Transaction builder
- `signature.ex` - Signature handling
- `mnemonic.ex` - Mnemonic phrase generation
- `block.ex` - Block data structures

### RPC (`lib/ex_solana/rpc/`)
- `rpc.ex` - Main RPC client using Req
- `request/` - Individual RPC request modules

### Utilities (`lib/ex_solana/util/`)
- Helper functions and utilities

### Error Handling (`lib/ex_solana/error.ex`)
- Base `ExSolana.Error` class
- Specialized error types using Splode

## Common Patterns

### Creating Zoi Schemas

```elixir
use Zoi

schema :account do
  field :lamports, :integer
  field :data, :binary
  field :owner, :binary
  field :executable, :boolean, default: false
end
```

### Raising Errors with Splode

```elixir
defmodule ExSolana.Error.InvalidKeyError do
  use Splode.Error,
    fields: [:key, :reason],
    class: :invalid
end

# In your code:
splode(InvalidKeyError, key: encoded, reason: "decode_failed")
```

### Using Req for HTTP

```elixir
Req.new(base_url: base_url, auth: auth, retry: :safe_transient)
```

## Testing

- Run tests: `mix test`
- Run with coverage: `mix coveralls.html`
- Test files mirror lib structure in `test/ex_solana/`

## Quality Checks

```bash
mix quality  # Run all checks
# or
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --min-priority higher
mix dialyzer
```

## Key Points for AI Agents

1. **Always use Zoi for new schemas** - Do not use TypedStruct directly
2. **Use Splode for errors** - Provide structured error information
3. **Use Req for HTTP** - Not Tesla or other HTTP clients
4. **Maintain 90%+ test coverage** - All new code needs tests
5. **Follow Elixir conventions** - Use `mix format` before committing
6. **Write @moduledoc and @doc** - Document all public modules and functions
7. **Use type specs** - Provide @spec for all public functions
8. **Ed25519 API**: Use `Ed25519.generate_key_pair/0` (Elixir function), not `:ed25519.generate_keypair/0` (Erlang)
9. **Test module naming**: When moving tests between packages, update both module name and all alias references
10. **Network config**: Use atoms for network (`:localhost`) not strings (`"localhost"`)

## Module Naming

- Core types: `ExSolana.Core.*` (e.g., `ExSolana.Core.Key`)
- RPC: `ExSolana.RPC.*`
- Errors: `ExSolana.Error.*`
- Utilities: `ExSolana.Util.*`

## Dependencies

For AI agents considering new dependencies:
- Prefer existing Jido ecosystem packages (zoi, splode, req)
- Avoid adding new dependencies without justification
- Keep the package focused on Solana blockchain functionality
