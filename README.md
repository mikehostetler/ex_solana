# ExSolana - Elixir Solana SDK

[![CI](https://github.com/agentjido/ex_solana/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/ex_solana/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/ex_solana.svg)](https://hex.pm/packages/ex_solana)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_solana)
[![Coverage](https://coveralls.io/repos/github/agentjido/ex_solana/badge.svg)](https://coveralls.io/github/agentjido/ex_solana)

A comprehensive Solana SDK for Elixir with modern architecture using [`req`](https://hex.pm/packages/req) for HTTP, [`zoi`](https://hex.pm/packages/zoi) for schemas, and [`splode`](https://hex.pm/packages/splode) for error handling.

## Features

- **Key Management**: Keypair generation, mnemonic support, and public key operations
- **RPC Client**: JSON-RPC API client with `req` - simple, composable HTTP
- **Transaction Building**: Create, sign, and send transactions with blockhash management
- **Program Integration**: Support for SPL Token, Jupiter, Raydium, and custom programs via IDL
- **IDL Code Generation**: Generate Elixir modules from Anchor IDL files
- **Instruction Decoding**: Parse and analyze Solana instructions and events
- **Transaction Tracking**: Monitor transaction status with confirmation polling
- **WebSocket Support**: Real-time subscriptions for account and transaction updates
- **Type-Safe**: Built with [Zoi](https://hexdocs.pm/zoi) schemas for compile-time validation
- **Structured Errors**: Integrated with [Splode](https://hexdocs.pm/splode) for clear error handling

## Package Ecosystem

ExSolana has been split into focused packages:

| Package | Description | Dependencies |
|---------|-------------|--------------|
| [`ex_solana`](https://hex.pm/packages/ex_solana) | **Core** - RPC, WebSocket, IDL, Transactions, Keys | req, zoi, splode |
| [`ex_solana_programs`](https://hex.pm/packages/ex_solana_programs) | Pre-built program implementations (Jupiter, Raydium, SPL, Native) | ex_solana |
| [`ex_solana_jito`](https://hex.pm/packages/ex_solana_jito) | MEV bundle submission via Jito | ex_solana |
| [`ex_solana_geyser`](https://hex.pm/packages/ex_solana_geyser) | Geyser/Yellowstone streaming | ex_solana |
| [`ex_solana_trading`](https://hex.pm/packages/ex_solana_trading) | Trading utilities (P&L, Risk, Portfolio) | ex_solana |

## Installation

Add `ex_solana` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_solana, "~> 0.2"}
  ]
end
```

For additional features, add more packages:

```elixir
def deps do
  [
    {:ex_solana, "~> 0.2"},
    # For DEX integration (Jupiter, Raydium)
    {:ex_solana_programs, "~> 0.2"},
    # For MEV bundle submission
    {:ex_solana_jito, "~> 0.2"}
  ]
end
```

## Quick Start

### RPC Client with Req

```elixir
# Create an RPC client
client = ExSolana.RPC.client(network: :mainnet_beta)

# Get account info
case ExSolana.RPC.send(client, ExSolana.RPC.Request.get_account_info(pubkey)) do
  {:ok, response} -> IO.inspect(response)
  {:error, %ExSolana.Errors.RPCError{} = error} -> handle_error(error)
end

# Get balance
{:ok, balance} = ExSolana.RPC.get_balance(client, pubkey)
```

### Key Management

```elixir
# Generate a new keypair
{:ok, keypair} = ExSolana.Key.pair()

# From mnemonic
{:ok, keypair} = ExSolana.Key.from_mnemonic("your twelve word mnemonic phrase here")

# Get public key as base58
pubkey = ExSolana.Key.to_base58(keypair.pubkey)

# Decode a public key
{:ok, decoded_key} = ExSolana.Key.decode("Base58EncodedPublicKey...")
```

### Building and Sending Transactions

```elixir
import ExSolana.Ix

# Create a transfer instruction
{:ok, ix} = transfer(
  from: payer_pubkey,
  to: recipient_pubkey,
  lamports: 1_000_000  # 0.001 SOL
)

# Build transaction
{:ok, tx} = ExSolana.Transaction.new([ix], payer: payer_pubkey)

# Sign transaction
{:ok, signed_tx} = ExSolana.Transaction.sign(tx, [keypair])

# Send and confirm
case ExSolana.RPC.send_and_confirm(client, signed_tx) do
  {:ok, signature} -> IO.puts("Transaction sent: #{signature}")
  {:error, %ExSolana.Errors.TransactionError{} = error} -> handle_error(error)
end
```

### WebSocket Subscriptions

```elixir
# Start WebSocket client
{:ok, ws_client} = ExSolana.WebSocket.start_link(
  url: "wss://api.mainnet-beta.solana.com"
)

# Subscribe to account updates
ExSolana.WebSocket.subscribe_account(ws_client, pubkey)

# Handle updates
def handle_info({:websocket_message, message}, state) do
  # Process account update
  {:noreply, state}
end
```

### IDL-Based Program Integration

```elixir
# Load an IDL file
{:ok, idl} = ExSolana.IDL.load_file("priv/idl/my_program.json")

# Decode instruction data
case ExSolana.IDL.decode_instruction(idl, instruction_data) do
  {:ok, {:initialize, params}} -> # Initialize instruction
    IO.inspect(params)
  {:ok, {:transfer, params}} -> # Transfer instruction
    IO.inspect(params)
end

# Decode account data
case ExSolana.IDL.decode_account(idl, "MyAccount", account_bytes) do
  {:ok, account_data} ->
    IO.inspect(account_data)
end
```

## Configuration

Configure `ex_solana` in `config/config.exs`:

```elixir
config :ex_solana,
  network: :mainnet_beta,
  # Or use custom RPC endpoint
  rpc_base_url: "https://api.mainnet-beta.solana.com"

# RPC settings
config :ex_solana, :rpc,
  max_retries: 10,
  max_delay: 4000,
  retry_enabled: true
```

## Supported Networks

```elixir
# Pre-configured networks
ExSolana.RPC.client(network: :mainnet_beta)    # Mainnet
ExSolana.RPC.client(network: :testnet)         # Testnet
ExSolana.RPC.client(network: :devnet)          # Devnet
ExSolana.RPC.client(network: :localhost)       # Local validator

# Custom endpoint
ExSolana.RPC.client(base_url: "https://your-custom-rpc.com")
```

## Error Handling

ExSolana uses structured errors via `Splode`:

```elixir
case ExSolana.Key.decode("invalid_key") do
  {:ok, key} -> key
  {:error, %ExSolana.Errors.InvalidKeyError{reason: reason}} ->
    IO.puts("Invalid key: #{reason}")
end
```

Error types:

- `ExSolana.Errors.InvalidKeyError` - Invalid public key format
- `ExSolana.Errors.RPCError` - RPC communication errors
- `ExSolana.Errors.TransactionError` - Transaction failures
- `ExSolana.Errors.ConfirmationError` - Transaction confirmation timeout

## Advanced Usage

### Custom RPC Request

```elixir
# Build a custom request
request = ExSolana.RPC.Request.new("getAccountInfo", [pubkey, encoding: "base64"])

# Send the request
{:ok, response} = ExSolana.RPC.send(client, request)
```

### Transaction with Multiple Instructions

```elixir
import ExSolana.Ix

# Create multiple instructions
{:ok, ix1} = transfer(from: payer, to: recipient1, lamports: 1_000_000)
{:ok, ix2} = transfer(from: payer, to: recipient2, lamports: 2_000_000)

# Build transaction with both instructions
{:ok, tx} = ExSolana.Transaction.new([ix1, ix2], payer: payer)

# Sign and send
{:ok, signed_tx} = ExSolana.Transaction.sign(tx, [keypair])
{:ok, signature} = ExSolana.RPC.send_and_confirm(client, signed_tx)
```

### Decode Transaction Instructions

```elixir
# Decode instruction from a transaction
case ExSolana.Decoder.decode_instruction(instruction) do
  {:ok, {:system_program, :transfer, params}} ->
    IO.puts("Transfer of #{params.lamports} lamports")

  {:ok, {:spl_token, :transfer, params}} ->
    IO.puts("Token transfer: #{params.amount}")

  {:error, :unknown_instruction} ->
    IO.puts("Unknown instruction")
end
```

## Using Additional Packages

### Jupiter Integration (ex_solana_programs)

```elixir
# Decode Jupiter swap instruction
decoded = ExSolanaPrograms.Jupiter.decode_ix(instruction_data)
```

### Jito MEV Bundles (ex_solana_jito)

```elixir
# Submit MEV-protected bundle
{:ok, bundle} = ExSolanaJito.Bundle.build([tx1, tx2])
{:ok, bundle_id} = ExSolanaJito.SearcherClient.send_bundle(client, bundle)
```

### Geyser Streaming (ex_solana_geyser)

```elixir
# Stream real-time updates
{:ok, client} = ExSolanaGeyser.YellowstoneClient.start_link(
  url: "http://localhost:10000"
)
```

See individual package documentation for more details:
- [ex_solana_programs](https://hexdocs.pm/ex_solana_programs)
- [ex_solana_jito](https://hexdocs.pm/ex_solana_jito)
- [ex_solana_geyser](https://hexdocs.pm/ex_solana_geyser)
- [ex_solana_trading](https://hexdocs.pm/ex_solana_trading)

## Migration from ex_solana_v1

If you're upgrading from the original `ex_solana` package:

1. **Module namespace unchanged** - Core modules remain as `ExSolana.*`
2. **New error handling** - Use `Splode.Error.match?/2` for pattern matching
3. **HTTP client** - `Req` replaces `Tesla`
4. **Schemas** - `Zoi` replaces `TypedStruct`

See [MIGRATION.md](MIGRATION.md) for detailed migration guide.

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/ex_solana).

## License

Apache-2.0

Copyright © 2026 Agent Jido
