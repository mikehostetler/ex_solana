# Jupiter Swap Integration

The `ex_solana` library provides comprehensive support for [Jupiter](https://jup.ag), the leading DEX aggregator on Solana.

## Overview

Jupiter is a DEX aggregator that finds the best routes for token swaps across multiple DEXes including Orca, Raydium, Meteora, and more. This library provides a full-featured Elixir client for interacting with Jupiter's API.

## Features

- ✅ Best route finding across multiple DEXes
- ✅ ExactIn and ExactOut swap modes
- ✅ DEX filtering and selection
- ✅ Price impact and fee calculation
- ✅ Swap status tracking
- ✅ Priority fee estimation
- ✅ Platform fee support
- ✅ Token price queries
- ✅ Token list queries

## Configuration

### Required Configuration

Add your Jupiter API key to your application configuration:

```elixir
# config/config.exs
config :ex_solana,
  jupiter: [
    api_key: System.get_env("JUPITER_API_KEY")
  ]
```

Get your API key from [https://portal.jup.ag](https://portal.jup.ag).

### Optional Configuration

```elixir
config :ex_solana,
  jupiter: [
    api_key: "your-api-key",
    base_url: "https://api.jup.ag",  # Default
    swap_base_url: "https://api.jup.ag/swap/v1",  # Default
    price_base_url: "https://api.jup.ag/price"  # Default
  ]
```

## Basic Usage

### Getting a Quote

```elixir
alias ExSolana.Jup

# Create a client
client = Jup.client()

# Get a quote for swapping 1 SOL to USDC with 0.5% slippage
{:ok, quote} = Jup.quote_v1(
  client,
  "So11111111111111111111111111111111111111112",  # SOL
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
  1_000_000_000,  # 1 SOL in lamports
  50  # 0.5% slippage (50 basis points)
)

# Quote response contains:
# - inputMint: Input token mint
# - inAmount: Input amount
# - outputMint: Output token mint
# - outAmount: Expected output amount
# - priceImpactPct: Price impact percentage
# - routePlan: List of swap routes with DEX information
```

### Building and Executing a Swap Transaction

```elixir
alias ExSolana.Transaction.Builder
alias ExSolana.Ix.JupiterSwap

# Create a transaction builder
builder = Builder.new()
|> Builder.payer(your_public_key)
|> Builder.add_signers([your_keypair])
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",  # From SOL
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # To USDC
  1_000_000_000,  # 1 SOL
  50,  # 0.5% slippage
  []  # Options
)
|> Builder.blockhash()

# Build the transaction
{:ok, transaction} = Builder.build(builder)

# Send the transaction
{:ok, signature} = ExSolana.send(transaction, client: rpc_client)

# Or use send_and_confirm for automatic confirmation
{:ok, signature} = ExSolana.send_and_confirm(transaction, client: rpc_client)
```

## Advanced Options

### Swap Modes

#### ExactIn (Default)

Fixed input amount, output varies based on market conditions:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,  # Exactly 1 SOL input
  50,
  swap_mode: :ExactIn
)
```

#### ExactOut

Fixed output amount, input varies:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000,  # Exactly 1 USDC output
  50,
  swap_mode: :ExactOut
)
```

**Note**: ExactOut is only supported by certain DEXes (Orca Whirlpool, Raydium CLMM, Raydium CPMM). Not all routes support this mode.

### DEX Filtering

Restrict swaps to specific DEXes:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  dexes: "Orca,Raydium,Meteora DLMM"  # Only use these DEXes
)
```

Exclude specific DEXes:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  exclude_dexes: "Serum"  # Exclude Serum
)
```

### Route Options

Use only direct routes (single hop):

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  only_direct_routes: true
)
```

Disable intermediate token restrictions:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  restrict_intermediate_tokens: false
)
```

### Platform Fees

Add a platform fee to the swap (useful for revenue sharing):

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  platform_fee_bps: 100  # 1% platform fee
)
```

### Compute Budget Options

Limit the number of accounts used:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  max_accounts: 32  # Limit to 32 accounts
)
```

Choose instruction version:

```elixir
builder
|> JupiterSwap.jupiter_swap(
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  1_000_000_000,
  50,
  instruction_version: :V2  # Use V2 instructions
)
```

## Price Impact and Fees

### Calculate Price Impact

```elixir
{:ok, quote} = Jup.quote_v1(client, from_mint, to_mint, amount, slippage)
price_impact = Jup.calculate_price_impact(quote)

IO.puts("Price impact: #{Float.round(price_impact * 100, 4)}%")
# Output: Price impact: 0.0523%
```

### Calculate Fees

```elixir
{:ok, quote} = Jup.quote_v1(client, from_mint, to_mint, amount, slippage)
fees = Jup.calculate_fees(quote)

IO.puts("Total fees: #{fees.total} lamports")

# Print fee breakdown
Enum.each(fees.breakdown, fn fee ->
  IO.puts("  - #{fee.label}: #{fee.fee_amount} #{fee.fee_mint}")
end)
```

## Tracking Swap Status

### Start the Status Tracker

```elixir
alias ExSolana.Jupiter.SwapStatus

# Start the SwapStatus GenServer
{:ok, _pid} = SwapStatus.start_link()

# Or with custom options
{:ok, _pid} = SwapStatus.start_link(
  name: :my_swap_tracker,
  check_interval: 3_000,  # Check every 3 seconds
  cleanup_after: 300_000  # Remove after 5 minutes
)
```

### Track a Swap

```elixir
# After sending a transaction
{:ok, signature} = ExSolana.send(transaction, client: rpc_client)

# Start tracking
:ok = SwapStatus.track(signature)
```

### Check Status

```elixir
case SwapStatus.get_status(signature) do
  {:ok, :completed} ->
    IO.puts("Swap completed successfully!")

  {:ok, {:failed, reason}} ->
    IO.puts("Swap failed: #{reason}")

  {:ok, :pending} ->
    IO.puts("Swap still pending...")

  {:error, :not_found} ->
    IO.puts("Swap not being tracked")
end
```

### List All Tracked Swaps

```elixir
tracked = SwapStatus.list_tracked()

Enum.each(tracked, fn {signature, status} ->
  IO.puts("#{signature}: #{inspect(status)}")
end)
```

### Stop Tracking

```elixir
:ok = SwapStatus.untrack(signature)
```

## Getting Token Prices

```elixir
# Get price for single token
{:ok, price} = Jup.price_v2("So11111111111111111111111111111111111111112")
# Returns: %{"data" => %{"So11111111111111111111111111111111111111112" => %{"id" => ..., "price" => "100.00"}}}

# Get prices for multiple tokens
{:ok, prices} = Jup.price_v2([
  "So11111111111111111111111111111111111111112",
  "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
])

# Get price with extra info
{:ok, price} = Jup.price_v2("So11111111111111111111111111111111111111112",
  show_extra_info: true
)
```

## Getting Token Information

```elixir
# Get token by mint address
{:ok, token} = Jup.get_token_by_mint("So11111111111111111111111111111111111111112")

# Returns: %{
#   "address" => "So11111111111111111111111111111111111111112",
#   "symbol" => "SOL",
#   "decimals" => 9,
#   "name" => "Wrapped SOL",
#   "tags" => ["verified", "native"]
# }

# Get tokens by tag
{:ok, tokens} = Jup.get_tokens_by_tag([:verified, :stablecoin])

# Available tags:
# - :verified - Verified tokens
# - :community - Community tokens
# - :lst - Liquid staking tokens
# - :stablecoin - Stablecoin tokens
# - :birdeye-trending - Trending on Birdeye
# - :clone - Clone tokens
# - :pump - Pump.fun tokens
```

## Priority Fees

### Extract Fees from Swap Response

```elixir
alias ExSolana.Jupiter.PriorityFee

{:ok, quote} = Jup.quote_v1(client, from_mint, to_mint, amount, slippage)
{:ok, swap_response} = Jup.swap_instructions(client, quote, user_public_key)

{:ok, fees} = PriorityFee.from_swap_response(swap_response)

IO.puts("Compute Budget: #{fees.compute_budget} CU")
IO.puts("Compute Unit Price: #{fees.compute_unit_price} micro-lamports")
IO.puts("Total Fee: #{fees.total_fee} lamports")
```

### Estimate Custom Fees

```elixir
# Estimate fee for custom compute units and price
fee = PriorityFee.estimate(1_000_000, 1_000)
# Returns: 1000 lamports

# Suggest compute unit limit based on route complexity
limit = PriorityFee.suggest_compute_unit_limit(route_complexity: :medium)
# Returns: 500_000

# Suggest compute unit price
price = PriorityFee.suggest_unit_price()
# Returns: 1_000 micro-lamports
```

### Create Compute Budget Instructions

```elixir
instructions = PriorityFee.create_instructions(200_000, 1_000)
# Returns list of compute budget instructions
```

## Error Handling

```elixir
case Jup.quote_v1(client, from_mint, to_mint, amount, slippage) do
  {:ok, quote} ->
    # Process quote

  {:error, %ExSolana.Jupiter.Errors{reason: :insufficient_liquidity}} ->
    IO.puts("Not enough liquidity for this swap")

  {:error, %ExSolana.Jupiter.Errors{reason: :slippage_tolerance_exceeded}} ->
    IO.puts("Price moved too much, try again with higher slippage")

  {:error, %ExSolana.Jupiter.Errors{reason: :rate_limited}} ->
    IO.puts("Too many requests, please wait")

  {:error, %ExSolana.Jupiter.Errors{reason: :invalid_api_key}} ->
    IO.puts("Invalid or missing API key")

  {:error, %ExSolana.Jupiter.Errors{reason: reason}} ->
    IO.puts("Jupiter error: #{inspect(reason)}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Best Practices

### 1. Always Validate Quotes Before Swapping

```elixir
{:ok, quote} = Jup.quote_v1(client, from_mint, to_mint, amount, slippage)

# Check price impact
impact = Jup.calculate_price_impact(quote)
if impact > 0.01 do
  IO.puts("Warning: High price impact (#{Float.round(impact * 100, 2)}%)")
end

# Check route plan
if length(quote["routePlan"]) > 3 do
  IO.puts("Warning: Complex route with multiple hops")
end
```

### 2. Use Appropriate Slippage Tolerance

- **Low slippage (10-50 BPS)**: For stable pairs (SOL/USDC)
- **Medium slippage (50-100 BPS)**: For common pairs
- **High slippage (100-300 BPS)**: For volatile or low-liquidity pairs

```elixir
slippage = case pair do
  {:stable, _, _} -> 25  # 0.25%
  {:common, _, _} -> 50  # 0.5%
  {:volatile, _, _} -> 200  # 2%
end
```

### 3. Monitor Swap Status

Always track your swaps to completion:

```elixir
{:ok, pid} = SwapStatus.start_link()
{:ok, signature} = ExSolana.send(transaction, client: rpc_client)
:ok = SwapStatus.track(signature)

# Poll for completion
Process.send_after(self(), :check_swap, 5000)

receive do
  :check_swap ->
    case SwapStatus.get_status(signature) do
      {:ok, :completed} -> IO.puts("Done!")
      {:ok, :pending} -> # Retry
      {:ok, {:failed, reason}} -> IO.puts("Failed: #{reason}")
    end
end
```

### 4. Handle Rate Limits

Jupiter API has rate limits. Implement retry logic:

```elixir
def get_quote_with_retry(client, from, to, amount, slippage, opts \\ []) do
  max_retries = Keyword.get(opts, :max_retries, 3)
  retry_delay = Keyword.get(opts, :retry_delay, 1000)

  get_quote_with_retry(client, from, to, amount, slippage, max_retries, retry_delay)
end

defp get_quote_with_retry(client, from, to, amount, slippage, retries, delay) do
  case Jup.quote_v1(client, from, to, amount, slippage) do
    {:ok, quote} ->
      {:ok, quote}

    {:error, %ExSolana.Jupiter.Errors{reason: :rate_limited}} when retries > 0 ->
      :timer.sleep(delay)
      get_quote_with_retry(client, from, to, amount, slippage, retries - 1, delay * 2)

    {:error, reason} ->
      {:error, reason}
  end
end
```

### 5. Use ExactOut When You Need Specific Output

```elixir
# When you need exactly 1 USDC output
builder
|> JupiterSwap.jupiter_swap(
  from_mint,
  to_mint,
  1_000_000,  # 1 USDC
  50,
  swap_mode: :ExactOut
)
```

## Common Token Addresses

```elixir
# Native SOL
"So11111111111111111111111111111111111111112"

# USDC
"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

# USDT
"Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"

# RAY
"4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R"

# JUP
"JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
```

## API Reference

See the [`ExSolana.Jup`](https://hexdocs.pm/ex_solana/ExSolana.Jup.html) module documentation for complete API reference.

## Testing

For testing, you can use the test helpers:

```elixir
import ExSolana.JupiterTestHelpers

# Get mock quote response
quote = mock_quote_response()

# Get mock swap instructions
swap_instructions = mock_swap_instructions_response()

# Get common test tokens
tokens = test_tokens()
tokens.sol  # "So11111111111111111111111111111111111111112"
tokens.usdc  # "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

# Get mock signature
signature = mock_signature()
```

## Troubleshooting

### Common Issues

**"Invalid API Key"**
- Make sure you've configured your API key: `config :ex_solana, jupiter: [api_key: "..."]`
- Get your API key from https://portal.jup.ag

**"Rate limit exceeded"**
- Implement retry logic with exponential backoff
- Consider increasing delays between requests

**"Insufficient liquidity"**
- Try a different token pair
- Increase your slippage tolerance
- Reduce your swap amount

**High price impact**
- Consider swapping smaller amounts
- Try using `only_direct_routes: true`
- Check if the pool has sufficient liquidity

## Resources

- [Jupiter Developer Portal](https://portal.jup.ag)
- [Jupiter API Documentation](https://dev.jup.ag)
- [Jupiter GitHub](https://github.com/jup-ag/jupiter-api-rust-example)
- [Solana Documentation](https://solana.com/developers)
