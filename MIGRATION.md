# Migration Guide: ex_solana_v1 to ex_solana v0.2

This guide helps you migrate from the original `ex_solana` package (now `ex_solana_v1`) to the new modular `ex_solana` ecosystem (v0.2+).

## Overview

The original `ex_solana` package has been split into multiple focused packages with modern architecture:

| Old Package | New Package(s) | Changes |
|-------------|----------------|---------|
| `ex_solana` | `ex_solana` (core) | RPC, WebSocket, IDL, Transactions, Keys |
| | `ex_solana_programs` | Jupiter, Raydium, SPL, Native programs |
| | `ex_solana_jito` | Jito MEV bundles |
| | `ex_solana_geyser` | Geyser/Yellowstone streaming |
| | `ex_solana_trading` | Trading utilities |

## Key Changes

### 1. Module Namespaces

**Core modules** remain as `ExSolana.*` (no changes):
- `ExSolana.RPC`
- `ExSolana.Key`
- `ExSolana.Transaction`
- `ExSolana.WebSocket`
- `ExSolana.IDL`
- `ExSolana.Decoder`

**Sub-packages** use new namespaces:
- `ExSolana.Jito.*` → `ExSolanaJito.*`
- `ExSolana.Geyser.*` → `ExSolanaGeyser.*`
- `ExSolana.Programs.*` → `ExSolanaPrograms.*`
- `ExSolana.Trading.*` → `ExSolanaTrading.*`

### 2. Dependencies

**Before** (ex_solana_v1):
```elixir
def deps do
  [
    {:ex_solana, "~> 0.1"}
  ]
end
```

**After** (ex_solana v0.2):
```elixir
def deps do
  [
    {:ex_solana, "~> 0.2"}
  ]
end
```

**With additional features**:
```elixir
def deps do
  [
    {:ex_solana, "~> 0.2"},
    {:ex_solana_programs, "~> 0.2"},  # For DEX programs
    {:ex_solana_jito, "~> 0.2"}        # For MEV bundles
  ]
end
```

### 3. HTTP Client: Tesla → Req

**Before**:
```elixir
# Tesla client
client = ExSolana.RPC.client(network: "mainnet-beta")
```

**After**:
```elixir
# Req client (same API)
client = ExSolana.RPC.client(network: :mainnet_beta)
```

**Note**: The API is largely unchanged. The main difference is the underlying HTTP library.

### 4. Error Handling: Tuples → Splode

**Before**:
```elixir
case ExSolana.Key.decode("invalid_key") do
  {:ok, key} -> key
  {:error, reason} -> IO.puts("Error: #{reason}")
end
```

**After**:
```elixir
case ExSolana.Key.decode("invalid_key") do
  {:ok, key} -> key
  {:error, %ExSolana.Errors.InvalidKeyError{} = error} ->
    IO.puts("Error: #{error.reason}")
end
```

**Error types**:
- `ExSolana.Errors.InvalidKeyError` - Invalid public key
- `ExSolana.Errors.RPCError` - RPC errors
- `ExSolana.Errors.TransactionError` - Transaction failures
- `ExSolana.Errors.ConfirmationError` - Confirmation timeout

### 5. Schemas: TypedStruct → Zoi

**Before**:
```elixir
defmodule ExSolana.Core.Account do
  use TypedStruct

  typedstruct do
    field :lamports, integer()
    field :data, binary()
    field :owner, ExSolana.Key.t()
    field :executable, boolean(), default: false
  end
end
```

**After**:
```elixir
defmodule ExSolana.Core.Account do
  use Zoi

  schema :account do
    field :lamports, :integer
    field :data, :binary
    field :owner, :binary
    field :executable, :boolean, default: false
  end
end
```

**Note**: This is an internal change. The public API remains the same.

## Module-by-Module Migration

### RPC Client

**Before**:
```elixir
client = ExSolana.rpc_client(network: "mainnet-beta")
request = ExSolana.RPC.Request.get_balance(pubkey)
{:ok, balance} = ExSolana.send(request, client: client)
```

**After**:
```elixir
client = ExSolana.RPC.client(network: :mainnet_beta)
{:ok, balance} = ExSolana.RPC.get_balance(client, pubkey)
```

### Key Management

**Before**:
```elixir
keypair = ExSolana.keypair()
{:ok, keypair} = ExSolana.Key.from_mnemonic("words...")
pubkey = ExSolana.pubkey!(keypair)
```

**After**:
```elixir
{:ok, keypair} = ExSolana.Key.pair()
{:ok, keypair} = ExSolana.Key.from_mnemonic("words...")
pubkey = ExSolana.Key.to_base58(keypair.pubkey)
```

### Transactions

**Before**:
```elixir
alias ExSolana.Core.{TxBuilder, Instructions}

tx = TxBuilder.new()
|> TxBuilder.add_instruction(
  Instructions.transfer(from: keypair, to: recipient, lamports: 1_000_000)
)
|> TxBuilder.sign([keypair])

{:ok, signature} = ExSolana.send_and_confirm(tx, client: client)
```

**After**:
```elixir
import ExSolana.Ix

{:ok, ix} = transfer(from: payer, to: recipient, lamports: 1_000_000)
{:ok, tx} = ExSolana.Transaction.new([ix], payer: payer)
{:ok, signed_tx} = ExSolana.Transaction.sign(tx, [keypair])
{:ok, signature} = ExSolana.RPC.send_and_confirm(client, signed_tx)
```

### Jito Integration

**Before**:
```elixir
alias ExSolana.Jito.Bundle

bundle = Bundle.new()
|> Bundle.add_transaction(tx1)
|> Bundle.add_transaction(tx2)

{:ok, bundle_id} = ExSolana.Jito.send_bundle(bundle)
```

**After**:
```elixir
# Add ex_solana_jito to deps first
{:ok, bundle} = ExSolanaJito.Bundle.build([tx1, tx2])
{:ok, bundle_id} = ExSolanaJito.SearcherClient.send_bundle(client, bundle)
```

### Geyser Streaming

**Before**:
```elixir
alias ExSolana.Geyser.YellowstoneClient

{:ok, client} = YellowstoneClient.connect(endpoint: "grpc://...")
YellowstoneClient.subscribe_accounts(client, accounts: [...])
```

**After**:
```elixir
# Add ex_solana_geyser to deps first
{:ok, client} = ExSolanaGeyser.YellowstoneClient.start_link(url: "http://...")
:ok = ExSolanaGeyser.YellowstoneClient.subscribe(client, accounts: [...])
```

### Program Decoders

**Before**:
```elixir
alias ExSolana.Program.Jupiter
decoded = Jupiter.decode_ix(instruction_data)
```

**After**:
```elixir
# Add ex_solana_programs to deps first
decoded = ExSolanaPrograms.Jupiter.decode_ix(instruction_data)
```

## Configuration Changes

**Before**:
```elixir
config :ex_solana,
  network: "mainnet-beta"
```

**After**:
```elixir
config :ex_solana,
  network: :mainnet_beta  # Use atom instead of string
```

## Step-by-Step Migration

### Step 1: Update Dependencies

Replace `ex_solana` with `ex_solana ~> 0.2` in your `mix.exs`:

```elixir
def deps do
  [
    {:ex_solana, "~> 0.2"}
  ]
end
```

### Step 2: Update Module Aliases

Find and replace module aliases:

```elixir
# Old
alias ExSolana.Jito.Bundle
alias ExSolana.Geyser.YellowstoneClient
alias ExSolana.Programs.Jupiter

# New
alias ExSolanaJito.Bundle
alias ExSolanaGeyser.YellowstoneClient
alias ExSolanaPrograms.Jupiter
```

### Step 3: Update Error Handling

Update error pattern matching:

```elixir
# Old
case result do
  {:error, reason} -> handle_error(reason)
end

# New
case result do
  {:error, %ExSolana.Errors.SomeError{} = error} -> handle_error(error)
end
```

### Step 4: Update Network Configuration

Change network strings to atoms:

```elixir
# Old
network: "mainnet-beta"
network: "testnet"
network: "devnet"

# New
network: :mainnet_beta
network: :testnet
network: :devnet
```

### Step 5: Update RPC Calls

Simplify RPC API calls:

```elixir
# Old
request = ExSolana.RPC.Request.get_balance(pubkey)
{:ok, balance} = ExSolana.send(request, client: client)

# New
{:ok, balance} = ExSolana.RPC.get_balance(client, pubkey)
```

### Step 6: Add Optional Dependencies

If you were using:
- Jito bundles → Add `ex_solana_jito`
- Geyser streaming → Add `ex_solana_geyser`
- Program decoders → Add `ex_solana_programs`
- Trading utilities → Add `ex_solana_trading`

### Step 7: Test Your Changes

Run your test suite and fix any issues:

```bash
mix test
```

## Breaking Changes Summary

| Change | Impact | Effort |
|--------|--------|--------|
| Module name changes (Jito, Geyser, Programs) | High | Medium |
| Error handling (Splode) | Medium | Low |
| Network config (string → atom) | Low | Low |
| RPC API simplification | Low | Low |

## Need Help?

- Check [HexDocs](https://hexdocs.pm/ex_solana)
- Review [ex_solana README](README.md)
- Open an issue on [GitHub](https://github.com/agentjido/ex_solana/issues)

## Rollback

If you encounter issues, you can temporarily rollback to `ex_solana_v1`:

```elixir
def deps do
  [
    {:ex_solana, github: "mikehostetler/ex_solana"}
  ]
end
```

However, `ex_solana_v1` is deprecated and will not receive updates.
