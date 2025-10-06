# ExSolana - Elixir Solana SDK

_This package is provided AS-IS - It's not a priority to improve it right now - so don't expect any updates. I welcome PRs if you'd like to contribute!_

Solana SDK for Elixir with support for blockchain interaction, transaction processing, and program integration.

## Features

- **Key Management**: Keypair generation, mnemonic support, and public key operations
- **RPC Client**: JSON-RPC API client with middleware, caching, and retry logic
- **Transaction Building**: Create, sign, and send transactions with blockhash management
- **Program Integration**: Support for SPL Token, Jupiter, Raydium, and custom programs
- **IDL Code Generation**: Generate Elixir modules from Anchor IDL files
- **Geyser Support**: Real-time blockchain data streaming via Yellowstone gRPC
- **Jito Integration**: MEV-protected transactions via Jito bundles
- **Instruction Decoding**: Parse and analyze Solana instructions and events
- **Transaction Tracking**: Monitor transaction status with confirmation polling
- **Token Operations**: SPL token transfers and account management

## Installation

```elixir
def deps do
  [
    {:ex_solana, github: "mikehostetler/ex_solana"}
  ]
end
```

## Prerequisites

Install the [Solana CLI](https://solana.com/docs/intro/installation) for development:

```bash
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
```

## Quick Start

```elixir
# Create an RPC client
client = ExSolana.rpc_client(network: "mainnet-beta")

# Generate a keypair
keypair = ExSolana.keypair()

# Get account info
request = ExSolana.RPC.Request.get_account_info("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
{:ok, account} = ExSolana.send(request, client: client)

# Build and send a transaction
alias ExSolana.Core.{TxBuilder, Instructions}

tx = TxBuilder.new()
|> TxBuilder.add_instruction(
  Instructions.transfer(from: keypair, to: recipient, lamports: 1_000_000)
)
|> TxBuilder.sign([keypair])

{:ok, signature} = ExSolana.send_and_confirm(tx, client: client)
```

## Core Modules

### RPC Operations

```elixir
# Basic RPC calls
client = ExSolana.rpc_client(network: "mainnet-beta")
request = ExSolana.RPC.Request.get_balance(pubkey)
{:ok, balance} = ExSolana.send(request, client: client)

# Transaction tracking with a GenServer process
tracker = ExSolana.tracker()
{:ok, signature} = ExSolana.send_and_confirm(transaction, client: client, tracker: tracker)
```

### Key Management

```elixir
# Generate keypair
keypair = ExSolana.keypair()
{secret_key, public_key} = keypair

# From mnemonic
{:ok, keypair} = ExSolana.Key.from_mnemonic("your twelve word phrase...")

# Decode public key
{:ok, pubkey} = ExSolana.pubkey("Base58EncodedPublicKey")
pubkey = ExSolana.pubkey!(keypair)
```

### IDL-Based Program Integration

```elixir
# Generate program module from IDL
mix ex_solana.generate_program priv/idls/my_program.json

# Use generated program
alias ExSolana.Program.MyProgram

# Decode instructions
{:ok, {:initialize, params}} = MyProgram.decode_ix(instruction_data)

# Decode accounts
{:ok, {:user_account, account_data}} = MyProgram.decode_account(account_bytes)

# Decode events
events = MyProgram.decode_events(transaction_logs)
```

### Geyser (Real-time Data Streaming)

```elixir
# Subscribe to account updates
alias ExSolana.Geyser.YellowstoneClient

{:ok, client} = YellowstoneClient.connect(endpoint: "grpc://your-geyser-endpoint")

YellowstoneClient.subscribe_accounts(client, %{
  accounts: ["TokenMintAddress"],
  owner: ["TokenProgramId"]
})
```

### Jito Integration

```elixir
# Send bundle with MEV protection
alias ExSolana.Jito.Bundle

bundle = Bundle.new()
|> Bundle.add_transaction(tx1)
|> Bundle.add_transaction(tx2)

{:ok, bundle_id} = ExSolana.Jito.send_bundle(bundle)
```

## Supported Programs

Built-in decoders and helpers for:

- **SPL Token**: Token operations, mint/burn, transfers
- **Jupiter**: DEX aggregator swaps
- **Raydium**: AMM pools (V4, CAMM, CPMM)
- **System Program**: Account creation, transfers
- **Compute Budget**: Priority fees, compute limits
- **Pump.fun**: Token creation and trading (see below)

---

# Pump.fun Integration

Support for interacting with [pump.fun](https://pump.fun), a token launch platform on Solana. This section covers pump.fun functionality in the `ex_solana` library.

## Table of Contents

1. [What is Pump.fun?](#what-is-pumpfun)
2. [Architecture Overview](#architecture-overview)
3. [Getting Started](#getting-started)
4. [Core Concepts](#core-concepts)
5. [API Reference](#api-reference)
6. [Usage Examples](#usage-examples)
7. [Testing Framework](#testing-framework)
8. [Advanced Usage](#advanced-usage)
9. [Troubleshooting](#troubleshooting)

---

## What is Pump.fun?

**Pump.fun** is a decentralized token launch platform on Solana that allows anyone to create and trade tokens using an automated bonding curve mechanism. It's become the go-to platform for meme coin creation and early-stage token trading.

### Key Features:
- 🎯 **Fair Launch**: No presales or team allocations
- 📊 **Bonding Curve**: Automated market making with predictable pricing
- ⚡ **Instant Trading**: Buy/sell tokens immediately upon creation
- 🔄 **Automatic Migration**: Successful tokens automatically migrate to Raydium
- 💰 **Low Fees**: Minimal costs for token creation and trading

### How It Works:
1. **Token Creation**: Anyone can create a token with metadata (name, symbol, image)
2. **Initial Trading**: Tokens trade on a bonding curve with virtual liquidity
3. **Price Discovery**: As more tokens are bought, the price increases along the curve
4. **Migration**: When certain conditions are met, tokens migrate to Raydium for full DEX trading

---

## Architecture Overview

The pump.fun integration in `ex_solana` is built around Solana's program architecture:

### Core Components:

```
┌─────────────────────────────────────────────────────────────┐
│                    Pump.fun Program                          │
│                6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P  │
├─────────────────────────────────────────────────────────────┤
│ Instructions:                                               │
│ • create        - Launch new token                          │
│ • buy          - Purchase tokens                           │
│ • sell         - Sell tokens                               │
│ • initialize   - Set up program state                       │
│ • set_params   - Configure global parameters                │
│ • migrate      - Move to Raydium                           │
│ • set_creator  - Update creator authority                   │
│ • collect_creator_fee - Claim creator fees                  │
├─────────────────────────────────────────────────────────────┤
│ Accounts:                                                   │
│ • BondingCurve - Individual token bonding curve state       │
│ • Global       - Program-wide configuration                 │
│ • UserVolumeAccumulator - User trading volume tracking      │
│ • GlobalVolumeAccumulator - System-wide volume metrics     │
│ • FeeConfig    - Fee structure configuration                │
├─────────────────────────────────────────────────────────────┤
│ Events:                                                     │
│ • CreateEvent  - Token creation notifications               │
│ • TradeEvent   - Buy/sell trade notifications               │
└─────────────────────────────────────────────────────────────┘
```

### Integration Layer:

```elixir
ExSolana.Program.PumpFun    # Auto-generated from IDL
├── decode_ix/1             # Decode instructions
├── decode_account/1        # Decode account data
├── decode_events/1         # Decode transaction events
└── analyze_ix/2            # Analyze instruction context
```

---

## Getting Started

### 1. Basic Setup

The pump.fun integration is automatically available when you add `ex_solana` to your project:

```elixir
# In your project
alias ExSolana.Program.PumpFun
alias ExSolana.RPC

# Create RPC client
client = RPC.client(network: "mainnet-beta")
```

### 2. Verify Program Availability

```elixir
program_id = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"

case RPC.send(client, RPC.Request.get_account_info(program_id)) do
  {:ok, %{"executable" => true}} ->
    IO.puts("✓ Pump.fun program is available")

  _ ->
    IO.puts("✗ Pump.fun program not found")
end
```

---

## Core Concepts

### Bonding Curve Mathematics

Pump.fun uses a **constant product bonding curve** similar to Uniswap's AMM:

```
Virtual SOL Reserve × Virtual Token Reserve = K (constant)
```

**Key Parameters:**
- `initial_virtual_token_reserves`: 1,000,000,000,000 (1T tokens)
- `initial_virtual_sol_reserves`: 30,000,000,000 (30 SOL)
- `initial_real_token_reserves`: 1,000,000,000 (1B tokens)

**Price Calculation:**
```elixir
# Buy calculation
def calculate_buy_price(tokens_to_buy, current_token_reserve, current_sol_reserve) do
  k = current_token_reserve * current_sol_reserve
  new_token_reserve = current_token_reserve - tokens_to_buy
  new_sol_reserve = div(k, new_token_reserve)
  sol_cost = new_sol_reserve - current_sol_reserve
  sol_cost
end

# Example usage
sol_cost = calculate_buy_price(1_000_000, 1_000_000_000_000, 30_000_000_000)
# Returns SOL amount needed to buy 1M tokens
```

### Account Structure

#### BondingCurve Account
```elixir
%{
  virtual_token_reserves: integer(),    # Virtual tokens for pricing
  virtual_sol_reserves: integer(),      # Virtual SOL for pricing
  real_token_reserves: integer(),       # Actual token supply
  real_sol_reserves: integer(),         # Actual SOL collected
  token_total_supply: integer(),        # Total token supply
  complete: boolean(),                  # Migration status
  creator: string()                     # Creator pubkey
}
```

#### Global Account
```elixir
%{
  initialized: boolean(),               # Program initialization status
  authority: string(),                  # Program authority
  fee_recipient: string(),             # Fee collection account
  initial_virtual_token_reserves: integer(),
  initial_virtual_sol_reserves: integer(),
  initial_real_token_reserves: integer(),
  token_total_supply: integer(),
  fee_basis_points: integer(),         # Trading fee (100 = 1%)
  # ... additional configuration fields
}
```

---

## API Reference

### Instruction Decoding

```elixir
# Decode any pump.fun instruction
{:ok, instruction_data} = get_transaction_instruction_data()

case PumpFun.decode_ix(instruction_data) do
  {:buy, %{amount: amount, max_sol_cost: max_cost}} ->
    IO.puts("Buy #{amount} tokens for max #{max_cost} lamports")

  {:sell, %{amount: amount, min_sol_output: min_output}} ->
    IO.puts("Sell #{amount} tokens for min #{min_output} lamports")

  {:create, %{name: name, symbol: symbol, uri: uri, creator: creator}} ->
    IO.puts("Created token: #{name} (#{symbol})")

  {:unknown_ix, %{data: data}} ->
    IO.puts("Unknown instruction: #{inspect(data)}")
end
```

### Account Decoding

```elixir
# Fetch and decode bonding curve account
bonding_curve_pubkey = "..." # Derive from mint

case RPC.send(client, RPC.Request.get_account_info(bonding_curve_pubkey)) do
  {:ok, account_info} ->
    data = Base.decode64!(account_info["data"])

    case PumpFun.decode_account(data) do
      {:ok, {:bonding_curve, curve_data}} ->
        IO.puts("Token reserves: #{curve_data.virtual_token_reserves}")
        IO.puts("SOL reserves: #{curve_data.virtual_sol_reserves}")
        IO.puts("Migration complete: #{curve_data.complete}")

      {:error, reason} ->
        IO.puts("Failed to decode: #{inspect(reason)}")
    end

  {:error, reason} ->
    IO.puts("Account not found: #{inspect(reason)}")
end
```

### Event Parsing

```elixir
# Parse transaction logs for pump.fun events
def parse_pump_events(transaction_logs) do
  transaction_logs
  |> Enum.flat_map(fn log ->
    case decode_program_log(log) do
      {:ok, event_data} ->
        case PumpFun.decode_events(event_data) do
          {:create_event, event} -> [{:create, event}]
          {:trade_event, event} -> [{:trade, event}]
          _ -> []
        end
      _ -> []
    end
  end)
end

# Usage
events = parse_pump_events(transaction["meta"]["logMessages"])

Enum.each(events, fn
  {:create, %{name: name, mint: mint}} ->
    IO.puts("Token created: #{name} at #{mint}")

  {:trade, %{is_buy: true, token_amount: tokens, sol_amount: sol}} ->
    IO.puts("Buy: #{tokens} tokens for #{sol} lamports")

  {:trade, %{is_buy: false, token_amount: tokens, sol_amount: sol}} ->
    IO.puts("Sell: #{tokens} tokens for #{sol} lamports")
end)
```

---

## Usage Examples

### Example 1: Monitor Token Creation

```elixir
defmodule PumpMonitor do
  alias ExSolana.{RPC, Program.PumpFun}

  def monitor_new_tokens(client) do
    # Subscribe to pump.fun program logs
    subscription = %{
      "method" => "logsSubscribe",
      "params" => [
        %{
          "mentions" => ["6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"]
        },
        %{
          "commitment" => "confirmed"
        }
      ]
    }

    # Handle incoming logs
    handle_logs = fn logs ->
      case extract_create_events(logs) do
        [] -> :ok
        events ->
          Enum.each(events, &process_token_creation/1)
      end
    end

    RPC.subscribe(client, subscription, handle_logs)
  end

  defp extract_create_events(logs) do
    # Parse logs and extract CreateEvent data
    # Implementation depends on your log parsing strategy
  end

  defp process_token_creation(create_event) do
    IO.puts("🎉 New token created!")
    IO.puts("Name: #{create_event.name}")
    IO.puts("Symbol: #{create_event.symbol}")
    IO.puts("Mint: #{create_event.mint}")
    IO.puts("Creator: #{create_event.creator}")

    # Add your custom logic here:
    # - Store in database
    # - Send notifications
    # - Trigger analysis
    # - etc.
  end
end

# Start monitoring
client = RPC.client(network: "mainnet-beta")
PumpMonitor.monitor_new_tokens(client)
```

### Example 2: Analyze Token Performance

```elixir
defmodule PumpAnalyzer do
  alias ExSolana.{RPC, Program.PumpFun}

  def analyze_token(client, mint_pubkey) do
    with {:ok, bonding_curve_pda} <- derive_bonding_curve_pda(mint_pubkey),
         {:ok, curve_data} <- fetch_bonding_curve(client, bonding_curve_pda),
         {:ok, trades} <- fetch_recent_trades(client, mint_pubkey) do

      analysis = %{
        current_price: calculate_current_price(curve_data),
        market_cap: calculate_market_cap(curve_data),
        liquidity: curve_data.real_sol_reserves,
        volume_24h: calculate_volume(trades),
        holder_count: count_unique_holders(trades),
        migration_progress: calculate_migration_progress(curve_data)
      }

      {:ok, analysis}
    end
  end

  defp derive_bonding_curve_pda(mint_pubkey) do
    # Derive PDA: [b"bonding-curve", mint_pubkey], pump_program_id
    seeds = ["bonding-curve", mint_pubkey]
    program_id = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"

    case ExSolana.PDA.find_program_address(seeds, program_id) do
      {:ok, {pda, _bump}} -> {:ok, pda}
      error -> error
    end
  end

  defp fetch_bonding_curve(client, pda) do
    case RPC.send(client, RPC.Request.get_account_info(pda)) do
      {:ok, account_info} ->
        data = Base.decode64!(account_info["data"])
        case PumpFun.decode_account(data) do
          {:ok, {:bonding_curve, curve_data}} -> {:ok, curve_data}
          error -> error
        end
      error -> error
    end
  end

  defp calculate_current_price(curve_data) do
    # Price = SOL_reserve / Token_reserve (simplified)
    curve_data.virtual_sol_reserves / curve_data.virtual_token_reserves
  end

  defp calculate_market_cap(curve_data) do
    current_price = calculate_current_price(curve_data)
    current_price * curve_data.token_total_supply
  end

  defp calculate_migration_progress(curve_data) do
    # Migration typically happens when real SOL reserves reach ~85 SOL
    migration_threshold = 85_000_000_000  # 85 SOL in lamports
    progress = curve_data.real_sol_reserves / migration_threshold
    min(progress, 1.0) * 100  # Cap at 100%
  end

  # Additional helper functions...
end

# Usage
client = RPC.client(network: "mainnet-beta")
mint = "TokenMintAddressHere"

case PumpAnalyzer.analyze_token(client, mint) do
  {:ok, analysis} ->
    IO.puts("Token Analysis:")
    IO.puts("Current Price: $#{Float.round(analysis.current_price, 8)}")
    IO.puts("Market Cap: $#{Float.round(analysis.market_cap, 2)}")
    IO.puts("Migration Progress: #{Float.round(analysis.migration_progress, 1)}%")

  {:error, reason} ->
    IO.puts("Analysis failed: #{inspect(reason)}")
end
```

### Example 3: Build a Trading Bot

```elixir
defmodule PumpTradingBot do
  alias ExSolana.{RPC, Transaction, Program.PumpFun}

  def create_buy_transaction(client, payer_keypair, mint, token_amount, max_sol_cost) do
    payer_pubkey = ExSolana.pubkey!(payer_keypair)

    with {:ok, blockhash} <- get_latest_blockhash(client),
         {:ok, buy_instruction} <- build_buy_instruction(mint, payer_pubkey, token_amount, max_sol_cost) do

      transaction = %Transaction{
        instructions: [buy_instruction],
        signers: [payer_keypair],
        blockhash: blockhash,
        payer: payer_pubkey
      }

      {:ok, transaction}
    end
  end

  defp build_buy_instruction(mint, user, token_amount, max_sol_cost) do
    # This is a simplified example - real implementation requires:
    # 1. Deriving all necessary PDAs (bonding curve, associated token accounts, etc.)
    # 2. Building complete account list with proper permissions
    # 3. Encoding instruction data correctly

    program_id = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"

    # Buy instruction discriminator: [102, 6, 61, 18, 1, 218, 235, 234]
    instruction_data =
      <<102, 6, 61, 18, 1, 218, 235, 234>> <>  # Discriminator
      <<token_amount::little-unsigned-64>> <>  # Amount to buy
      <<max_sol_cost::little-unsigned-64>>     # Max SOL to spend

    accounts = [
      # Simplified account list - real implementation needs all accounts
      %{pubkey: mint, is_signer: false, is_writable: false},
      %{pubkey: user, is_signer: true, is_writable: true},
      # ... additional accounts (bonding curve, token program, etc.)
    ]

    {:ok, %{
      program_id: program_id,
      accounts: accounts,
      data: instruction_data
    }}
  end

  def execute_trade(client, transaction) do
    case RPC.send_and_confirm(client, transaction) do
      {:ok, signature} ->
        IO.puts("✅ Trade executed: #{signature}")
        {:ok, signature}

      {:error, reason} ->
        IO.puts("❌ Trade failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

# Usage example
client = RPC.client(network: "mainnet-beta")
payer = ExSolana.keypair()  # Your funded keypair
mint = "TokenMintAddress"
token_amount = 1_000_000    # 1M tokens
max_sol_cost = 100_000_000  # 0.1 SOL maximum

with {:ok, transaction} <- PumpTradingBot.create_buy_transaction(client, payer, mint, token_amount, max_sol_cost),
     {:ok, signature} <- PumpTradingBot.execute_trade(client, transaction) do
  IO.puts("Successfully bought tokens! Signature: #{signature}")
end
```

---

## Testing Framework

The `ex_solana` library includes a comprehensive testing framework specifically designed for pump.fun integration. This ensures your pump.fun related code works correctly and provides confidence in your implementation.

### Automatic Testing Setup

**Zero Configuration Required** - The testing framework automatically downloads and configures the pump.fun program for testing:

```bash
# Just run tests - everything happens automatically!
mix test

# Output:
# ⬇ Downloading pump.fun program binary for testing...
# ✓ Successfully downloaded pump.fun program binary
# ✅ 136/136 tests passing
```

### Test Categories

#### 1. Unit Tests (Always Available)

Complete IDL validation without requiring network access:

```bash
# Run all pump.fun unit tests
mix test test/ex_solana/programs/pump_fun_test.exs

# Tests cover:
# ✅ All 8 instructions (buy, sell, create, initialize, etc.)
# ✅ All 5 account types (BondingCurve, Global, etc.)
# ✅ All 2 event types (CreateEvent, TradeEvent)
# ✅ Error handling scenarios
```

#### 2. Integration Tests (Network Dependent)

Full end-to-end testing against real or simulated pump.fun program:

```bash
# Local test validator (default)
mix test --include integration

# Test against live networks
PUMP_TEST_NETWORK=testnet mix test --include integration
PUMP_TEST_NETWORK=devnet mix test --include integration
PUMP_TEST_NETWORK=mainnet mix test --include integration --only network_check
```

### Testing Your Own Code

#### Example Test Setup

```elixir
defmodule MyApp.PumpIntegrationTest do
  use ExUnit.Case, async: true
  import ExSolana.TestHelpers
  import ExSolana.PumpFunTestHelpers

  alias ExSolana.{RPC, Program.PumpFun}

  setup do
    client = rpc_client(:local)  # Use local test validator
    tracker = ExSolana.tracker(client: client, t: 100)

    # Create funded test accounts
    {:ok, payer} = create_payer(tracker, client, amount: 10_000)  # 10 SOL
    {:ok, creator} = create_payer(tracker, client, amount: 5_000)  # 5 SOL
    {:ok, trader} = create_payer(tracker, client, amount: 2_000)   # 2 SOL

    [client: client, payer: payer, creator: creator, trader: trader]
  end

  test "can decode buy instruction", %{client: client} do
    # Test instruction decoding
    buy_data = encode_buy_instruction_data(1_000_000, 100_000_000)

    result = PumpFun.decode_ix(buy_data)

    assert {:buy, %{amount: 1_000_000, max_sol_cost: 100_000_000}} = result
  end

  test "can fetch and decode bonding curve", %{client: client} do
    mint = "SomeTokenMintAddress"
    bonding_curve_pda = bonding_curve_pda(mint)

    case RPC.send(client, RPC.Request.get_account_info(bonding_curve_pda)) do
      {:ok, account_info} ->
        data = Base.decode64!(account_info["data"])

        case PumpFun.decode_account(data) do
          {:ok, {:bonding_curve, curve_data}} ->
            assert is_integer(curve_data.virtual_token_reserves)
            assert is_integer(curve_data.virtual_sol_reserves)
            assert is_boolean(curve_data.complete)

          other ->
            flunk("Unexpected decode result: #{inspect(other)}")
        end

      {:ok, nil} ->
        # Account doesn't exist - this is fine for tests
        assert true

      {:error, reason} ->
        flunk("Failed to fetch account: #{inspect(reason)}")
    end
  end
end
```

#### Testing Against Live Networks

```elixir
# Test configuration for different networks
defmodule MyApp.LivePumpTest do
  use ExUnit.Case

  @moduletag :live_network
  @moduletag timeout: 60_000

  test "mainnet pump.fun program is accessible" do
    client = ExSolana.PumpFunTestHelpers.rpc_client(:mainnet)

    assert ExSolana.PumpFunTestHelpers.program_available?(client)
  end

  test "can fetch real bonding curve data", %{} do
    client = ExSolana.PumpFunTestHelpers.rpc_client(:mainnet)

    # Use a known token mint (replace with real address)
    mint = "RealTokenMintAddress"
    bonding_curve_pda = ExSolana.PumpFunTestHelpers.bonding_curve_pda(mint)

    case RPC.send(client, RPC.Request.get_account_info(bonding_curve_pda)) do
      {:ok, account_info} when is_map(account_info) ->
        # Successfully fetched real data
        assert account_info["lamports"] > 0

      {:ok, nil} ->
        # Token might not exist or might be migrated
        IO.puts("Token account not found - may be migrated")
        assert true

      {:error, reason} ->
        flunk("Network error: #{inspect(reason)}")
    end
  end
end

# Run live network tests
# mix test --only live_network
```

### Test Configuration Options

#### Environment Variables

```bash
# Auto-download program binary
PUMP_AUTO_DOWNLOAD=true mix test

# Disable auto-download
PUMP_NO_AUTO_DOWNLOAD=true mix test

# Test against specific network
PUMP_TEST_NETWORK=testnet mix test --include integration

# CI environment (auto-enables download)
CI=true mix test
```

#### Test Tags

```bash
# Run only network connectivity tests
mix test --only network_check

# Run only local validator tests
mix test --only local_only

# Run error handling tests
mix test --only error_handling

# Include integration tests (normally excluded)
mix test --include integration

# Run tests requiring program binary
mix test --include requires_program_binary
```

### Performance Testing

#### Benchmark Your Implementation

```elixir
defmodule PumpPerformanceTest do
  use ExUnit.Case

  test "instruction decoding performance" do
    # Generate test data
    buy_data = encode_buy_instruction_data(1_000_000, 100_000_000)

    # Benchmark decoding
    {time_micro, result} = :timer.tc(fn ->
      for _ <- 1..1000 do
        ExSolana.Program.PumpFun.decode_ix(buy_data)
      end
    end)

    avg_time_micro = time_micro / 1000
    assert avg_time_micro < 1000, "Decoding should be under 1ms on average"

    IO.puts("Average decode time: #{Float.round(avg_time_micro, 2)} microseconds")
  end

  test "account parsing performance" do
    # Test account decoding performance
    dummy_curve_data = create_dummy_bonding_curve_data()

    {time_micro, _result} = :timer.tc(fn ->
      for _ <- 1..1000 do
        ExSolana.Program.PumpFun.decode_account(dummy_curve_data)
      end
    end)

    avg_time_micro = time_micro / 1000
    assert avg_time_micro < 5000, "Account parsing should be under 5ms"

    IO.puts("Average parse time: #{Float.round(avg_time_micro, 2)} microseconds")
  end
end
```

---

## Advanced Usage

### Custom Program Analysis

```elixir
defmodule AdvancedPumpAnalysis do
  alias ExSolana.{RPC, Program.PumpFun}

  def analyze_program_state(client) do
    program_id = "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P"

    # Get all accounts owned by pump.fun program
    filters = [
      %{
        "dataSize" => 64  # BondingCurve account size
      }
    ]

    case RPC.send(client, RPC.Request.get_program_accounts(program_id, filters)) do
      {:ok, accounts} ->
        analyze_all_bonding_curves(accounts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp analyze_all_bonding_curves(accounts) do
    curves =
      accounts
      |> Enum.map(&decode_bonding_curve_account/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, data} -> data end)

    analysis = %{
      total_tokens: length(curves),
      total_sol_locked: Enum.sum(Enum.map(curves, & &1.real_sol_reserves)),
      migrated_count: Enum.count(curves, & &1.complete),
      average_progress: calculate_average_migration_progress(curves)
    }

    {:ok, analysis}
  end

  # Additional analysis functions...
end
```

### Event Stream Processing

```elixir
defmodule PumpEventProcessor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    # Subscribe to all pump.fun program logs
    subscription_id = subscribe_to_pump_logs(client)

    state = %{
      client: client,
      subscription_id: subscription_id,
      event_handlers: %{
        create: &handle_token_creation/1,
        trade: &handle_trade_event/1
      }
    }

    {:ok, state}
  end

  def handle_info({:websocket_message, message}, state) do
    case decode_pump_event(message) do
      {:create_event, event} ->
        state.event_handlers.create.(event)

      {:trade_event, event} ->
        state.event_handlers.trade.(event)

      _ ->
        :ignore
    end

    {:noreply, state}
  end

  defp handle_token_creation(event) do
    IO.puts("🚀 New token: #{event.name} (#{event.symbol})")

    # Custom logic:
    # - Store in database
    # - Trigger notifications
    # - Start monitoring
    # - etc.
  end

  defp handle_trade_event(event) do
    action = if event.is_buy, do: "Buy", else: "Sell"
    IO.puts("💰 #{action}: #{event.token_amount} tokens for #{event.sol_amount} SOL")

    # Custom logic:
    # - Update price tracking
    # - Trigger alerts
    # - Calculate metrics
    # - etc.
  end
end

# Start the event processor
client = RPC.client(network: "mainnet-beta")
{:ok, _pid} = PumpEventProcessor.start_link(client: client)
```

### Integration with Phoenix LiveView

```elixir
defmodule MyAppWeb.PumpLive do
  use MyAppWeb, :live_view

  alias ExSolana.{RPC, Program.PumpFun}

  def mount(_params, _session, socket) do
    client = RPC.client(network: "mainnet-beta")

    # Subscribe to pump.fun events
    if connected?(socket) do
      subscribe_to_pump_events()
    end

    socket =
      socket
      |> assign(:client, client)
      |> assign(:tokens, [])
      |> assign(:recent_trades, [])

    {:ok, socket}
  end

  def handle_info({:token_created, token}, socket) do
    tokens = [token | socket.assigns.tokens] |> Enum.take(10)
    {:noreply, assign(socket, :tokens, tokens)}
  end

  def handle_info({:trade_executed, trade}, socket) do
    trades = [trade | socket.assigns.recent_trades] |> Enum.take(20)
    {:noreply, assign(socket, :recent_trades, trades)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1>Pump.fun Live Monitor</h1>

      <div class="recent-tokens">
        <h2>Recent Token Launches</h2>
        <%= for token <- @tokens do %>
          <div class="token-card">
            <h3><%= token.name %> (<%= token.symbol %>)</h3>
            <p>Creator: <%= token.creator %></p>
            <p>Mint: <%= token.mint %></p>
          </div>
        <% end %>
      </div>

      <div class="recent-trades">
        <h2>Recent Trades</h2>
        <%= for trade <- @recent_trades do %>
          <div class="trade-item">
            <%= if trade.is_buy do %>
              🟢 Buy: <%= trade.token_amount %> tokens for <%= trade.sol_amount %> SOL
            <% else %>
              🔴 Sell: <%= trade.token_amount %> tokens for <%= trade.sol_amount %> SOL
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
```

---

## Troubleshooting

### Common Issues

#### 1. Program Not Found
```
Error: pump.fun program not found on target network
```

**Solution:**
- Verify network connectivity
- Check if you're using the correct network (mainnet vs testnet)
- For local testing, ensure the program binary is downloaded

#### 2. Account Decoding Failures
```
Error: invalid_account_data
```

**Possible causes:**
- Account doesn't exist (token might be migrated)
- Wrong account type (not a pump.fun account)
- Network desynchronization

**Debugging:**
```elixir
# Check if account exists
case RPC.send(client, RPC.Request.get_account_info(address)) do
  {:ok, nil} ->
    IO.puts("Account doesn't exist")

  {:ok, account} ->
    IO.puts("Owner: #{account["owner"]}")
    IO.puts("Data size: #{byte_size(Base.decode64!(account["data"]))}")

  {:error, reason} ->
    IO.puts("RPC error: #{inspect(reason)}")
end
```

#### 3. Transaction Failures

**Common transaction errors:**

```elixir
# Insufficient SOL balance
{:error, %{"code" => -32002, "message" => "Transaction simulation failed"}}

# Slippage protection triggered
{:error, %{"InstructionError" => [0, %{"Custom" => 6001}]}}

# Program account not found
{:error, %{"InstructionError" => [0, %{"Custom" => 3012}]}}
```

**Debugging approach:**
```elixir
def debug_transaction_failure(client, transaction) do
  # Simulate transaction to get detailed error
  case RPC.send(client, RPC.Request.simulate_transaction(transaction)) do
    {:ok, %{"value" => %{"err" => error}}} ->
      IO.puts("Simulation error: #{inspect(error)}")
      analyze_error(error)

    {:ok, %{"value" => result}} ->
      IO.puts("Simulation successful: #{inspect(result)}")

    {:error, reason} ->
      IO.puts("RPC error: #{inspect(reason)}")
  end
end
```

#### 4. Network Issues

**Timeouts and connectivity:**

```elixir
# Configure RPC client with retries
client = RPC.client(
  network: "mainnet-beta",
  retry_options: [
    max_retries: 3,
    initial_delay: 1000,
    max_delay: 5000
  ]
)
```

**Alternative RPC endpoints:**
```elixir
# Use different RPC providers
client = RPC.client(base_url: "https://api.mainnet-beta.solana.com")
client = RPC.client(base_url: "https://solana-api.projectserum.com")
client = RPC.client(base_url: "https://rpc.ankr.com/solana")
```

### Testing Issues

#### 1. Test Validator Won't Start
```bash
# Clear test ledger
rm -rf /tmp/test-ledger

# Check if solana-test-validator is installed
which solana-test-validator

# Reinstall if needed
solana-install init
```

#### 2. Program Binary Download Fails
```bash
# Manual download
mkdir -p priv/programs
solana program dump 6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P priv/programs/pump.so --url mainnet-beta

# Verify download
ls -la priv/programs/pump.so
```

#### 3. Tests Fail on CI
```yaml
# GitHub Actions example
- name: Setup Solana
  run: |
    sh -c "$(curl -sSfL https://release.solana.com/stable/install)"
    echo "$HOME/.local/share/solana/install/active_release/bin" >> $GITHUB_PATH

- name: Run Tests with Auto Download
  env:
    PUMP_AUTO_DOWNLOAD: "true"
    CI: "true"
  run: mix test
```

### Performance Issues

#### 1. Slow Test Execution

**Optimization strategies:**
```elixir
# Use async tests where possible
use ExUnit.Case, async: true

# Cache expensive operations
@cached_program_binary Application.compile_env(:ex_solana, :cached_binary)

# Mock network calls in unit tests
def mock_rpc_client do
  %MockClient{responses: precomputed_responses()}
end
```

#### 2. High Memory Usage

**Memory optimization:**
```elixir
# Limit concurrent test processes
# in test/test_helper.exs
ExUnit.configure(max_cases: 4)  # Default is System.schedulers_online() * 2

# Clean up resources
ExUnit.after_suite(fn _ ->
  # Clean up test validator
  # Clear temporary files
  # Close database connections
end)
```

### Getting Help

#### 1. Enable Debug Logging
```elixir
# In config/test.exs
config :logger, level: :debug

# Enable RPC debugging
client = RPC.client(network: "mainnet-beta", verbose: true)
```

#### 2. Community Resources
- [Solana Stack Exchange](https://solana.stackexchange.com/)
- [Solana Discord](https://discord.gg/solana)
- [Pump.fun Documentation](https://docs.pump.fun/)

#### 3. Reporting Issues

When reporting issues, include:
- Elixir/OTP versions
- Network being used (mainnet/testnet/local)
- Full error messages
- Minimal reproduction code
- Transaction signatures (if applicable)

---

This comprehensive pump.fun integration provides everything you need to build powerful applications on top of the pump.fun ecosystem. From basic token monitoring to advanced trading bots, the `ex_solana` library gives you the tools to interact with pump.fun programmatically and reliably.
