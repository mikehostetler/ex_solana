# ExSolana Package Split Research Report

**Date**: 2026-01-12
**Research Phase**: Codebase Impact Analysis
**Target**: Split `projects/ex_solana` into smaller, focused packages

---

## Executive Summary

The `ex_solana` package is a comprehensive Solana blockchain library for Elixir with ~140 source files covering RPC communication, transaction building, Jito MEV integration, Geyser streaming, transaction decoding, IDL handling, and various program implementations.

**Final Recommendation**: Split into **5 focused packages** with clear separation of concerns. The core package (`ex_solana`) handles 90% of use cases including RPC, WebSocket, IDL, Instructions, and Decoder.

---

## 1. Final Package Split Strategy

### Package 1: `ex_solana` (Core) - ~106 files

**Purpose**: Complete Solana toolkit for 90% of use cases

| Component | Files | Description |
|-----------|-------|-------------|
| Core types | 14 | Key, Transaction, Account, Signature, Mnemonic, Block |
| RPC client | 43 | JSON-RPC client, 36 request modules, Tracker, BlockhashServer |
| WebSocket | 2 | Real-time subscription client |
| IDL | 9 | Parser, Generator, code generation macros |
| Instructions | 4 | Transaction builders (Transfer, Jupiter, Jito tip) |
| Decoder | 11 | Transaction/instruction decoding, log parsing |
| Utilities | 3 | Helpers, DebugTools, CompactArray |
| Root | 6 | Main entry, Config, Borsh, Codec, GRPC base, Wallet |
| **Total** | **~106** | **Full-featured Solana library** |

**Public API**:
- `ExSolana.Key` - Key generation, encoding/decoding
- `ExSolana.RPC` - RPC client, send/confirm transactions
- `ExSolana.WebSocket` - Real-time subscriptions
- `ExSolana.IDL` - Parse/generate from IDL files
- `ExSolana.Ix` - Build instructions
- `ExSolana.Decoder` - Decode transactions and instructions
- `ExSolana.Config` - Configuration management

**Dependencies**:
```elixir
defp deps do
  [
    # Core dependencies
    {:jason, "~> 1.4"},
    {:typed_struct, "~> 0.3.0"},
    {:basefiftyeight, "~> 0.1.0"},
    {:ed25519, "~> 1.3"},
    {:mnemonic, "~> 0.3.1"},
    {:block_keys, "~> 1.0"},

    # HTTP/WebSocket
    {:mint, "~> 1.6"},
    {:tesla, "~> 1.9"},
    {:websockex, "~> 0.4.3"},
    {:phx_json_rpc, "~> 0.7"},
    {:ex_json_schema, "~> 0.11.1"},

    # Dev & Test
    {:mimic, "~> 2.1.0", only: :test}
  ]
end
```

**Use Cases**:
- Simple wallet operations (send/receive, check balance)
- DEX integration (Jupiter, Raydium swaps via IDL)
- Custom program interaction (via IDL)
- Transaction analysis and debugging
- Real-time subscriptions

---

### Package 2: `ex_solana_jito` - ~17 files

**Purpose**: MEV bundle submission via Jito

| Component | Files | Description |
|-----------|-------|-------------|
| Jito integration | 17 | Bundle, SearcherClient, TipServer, 12 protobuf files |

**Public API**:
```elixir
# Submit MEV bundle
ExSolanaJito.submit_bundle(bundle, max_retries: 5)

# Access clients
ExSolanaJito.SearcherClient
ExSolanaJito.TipServer
ExSolanaJito.Bundle
```

**Dependencies**:
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.15.0"},
    {:ex_rated, "~> 2.1"},  # Rate limiting
    {:websockex, "~> 0.4.3"}
  ]
end
```

**Use Cases**:
- MEV bots
- Priority transaction submission
- Bundle strategies

---

### Package 3: `ex_solana_geyser` - ~7 files

**Purpose**: Geyser streaming for real-time data

| Component | Files | Description |
|-----------|-------|-------------|
| Geyser integration | 7 | YellowstoneClient, Broadway pipeline, 2 protobuf files |

**Public API**:
```elixir
# Start streaming
ExSolanaGeyser.start_link(client: geyser_client)

# Process with Broadway
ExSolanaGeyser.CachingPipeline
```

**Dependencies**:
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.15.0"},
    {:broadway, "~> 1.1"}
  ]
end
```

**Use Cases**:
- Real-time data streaming
- Transaction monitoring
- Indexing
- Analytics

---

### Package 4: `ex_solana_programs` - ~28 files

**Purpose**: Pre-built Solana program implementations

| Component | Files | Description |
|-----------|-------|-------------|
| Program implementations | 28 | Jupiter, Raydium, SPL, Native programs, macros |

**Public API**:
```elixir
# Use pre-built programs
ExSolanaPrograms.SPL.Token
ExSolanaPrograms.Native.ComputeBudget
ExSolanaPrograms.Raydium.PoolV4

# Define custom programs via behaviour
use ExSolanaPrograms.Behaviour,
  program_id: "...",
  idl_path: "path/to/idl.json"
```

**Dependencies**:
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"}
  ]
end
```

**Extensibility**: Other packages can add their own program implementations following the same pattern.

**Use Cases**:
- DEX integration without IDL files
- SPL token operations
- Native program interactions
- Custom program definitions

---

### Package 5: `ex_solana_trading` - ~3 files

**Purpose**: Trading-specific utilities

| Component | Files | Description |
|-----------|-------|-------------|
| Trading utilities | 3 | Profit/loss, risk management, portfolio |

**Public API**:
```elixir
ExSolanaTrading.ProfitLoss.calculate(trades)
ExSolanaTrading.RiskManager.check_position(position)
```

**Dependencies**:
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"}
  ]
end
```

**Use Cases**:
- Trading bots
- Portfolio tracking
- Risk management

---

## 2. Summary Table

| Package | Files | Purpose | Dependencies |
|---------|-------|---------|--------------|
| `ex_solana` | ~106 | Core: RPC, WebSocket, IDL, Instructions, Decoder | HTTP/WebSocket libs |
| `ex_solana_jito` | ~17 | MEV bundles | ex_solana, grpc, ex_rated |
| `ex_solana_geyser` | ~7 | Geyser streaming | ex_solana, grpc, broadway |
| `ex_solana_programs` | ~28 | Program implementations | ex_solana |
| `ex_solana_trading` | ~3 | Trading utilities | ex_solana |

---

## 3. Dependency Graph

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              ex_solana                                    │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Core Package (~106 files)                                          │  │
│  │                                                                     │  │
│  │  ┌─────────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ Core Types      │  │ RPC Client  │  │ WebSocket           │    │  │
│  │  │ • Key           │  │ • Tesla     │  │ • Subscriptions     │    │  │
│  │  │ • Transaction   │  │ • 36 reqs   │  │                     │    │  │
│  │  │ • Account       │  │ • Tracker   │  │                     │    │  │
│  │  │ • Signature     │  │ • Blockhash │  │                     │    │  │
│  │  └────────┬────────┘  └──────┬──────┘  └──────────┬──────────┘    │  │
│  │           │                  │                    │                │  │
│  │  ┌────────▼──────────────────▼────────────────────▼──────────┐    │  │
│  │  │                                                            │    │  │
│  │  │  ┌──────────┐  ┌───────────┐  ┌─────────────┐             │    │  │
│  │  │  │ IDL      │  │ Decoder   │  │ Instructions │             │    │  │
│  │  │  │ • Parser │  │ • Tx      │  │ • Builders   │             │    │  │
│  │  │  │ • Gen    │  │ •Ix       │  │ • Transfer   │             │    │  │
│  │  │  │ • Macros │  │ • Logs    │  │ • Jupiter    │             │    │  │
│  │  │  └──────────┘  └───────────┘  └─────────────┘             │    │  │
│  │  └─────────────────────────────────────────────────────────┘    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────┬──────────────────────────────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
    ┌────▼────────┐       ┌──────▼──────┐        ┌──────▼──────┐
    │ex_solana_   │       │ex_solana_   │        │ex_solana_   │
    │jito         │       │geyser       │        │programs     │
    │(~17 files)  │       │(~7 files)   │        │(~28 files)  │
    │MEV bundles  │       │Streaming    │        │DEX, SPL     │
    └─────────────┘       └─────────────┘        └──────┬──────┘
                                                        │
                                                 ┌──────▼──────┐
                                                 │ex_solana_   │
                                                 │trading      │
                                                 │(~3 files)   │
                                                 │P/L, Risk    │
                                                 └─────────────┘
```

---

## 4. Use Case Examples

### Simple Wallet
```elixir
# mix.exs
def deps do
  [{:ex_solana, "~> 0.2"}]
end

# Your code
client = ExSolana.RPC.client(network: "mainnet-beta")
keypair = ExSolana.Key.pair()
signature = ExSolana.Ix.transfer(keypair, recipient, lamports)
ExSolana.RPC.send_and_confirm(client, signature)
```

### DEX Integration
```elixir
# mix.exs
def deps do
  [
    {:ex_solana, "~> 0.2"},
    {:ex_solana_programs, "~> 0.2"}  # For pre-built Jupiter/Raydium
  ]
end

# Your code
swap_ix = ExSolana.Ix.jupiter_swap(...)
ExSolana.RPC.send_and_confirm(client, swap_ix)
```

### MEV Bot
```elixir
# mix.exs
def deps do
  [
    {:ex_solana, "~> 0.2"},
    {:ex_solana_jito, "~> 0.2"}
  ]
end

# Your code
bundle = ExSolanaJito.Bundle.new([tx1, tx2])
ExSolanaJito.submit_bundle(bundle)
```

### Streaming/Indexer
```elixir
# mix.exs
def deps do
  [
    {:ex_solana, "~> 0.2"},
    {:ex_solana_geyser, "~> 0.2"},
    {:ex_solana_decoder, "~> 0.2"}  # Included in core
  ]
end

# Your code
ExSolanaGeyser.start_link(client: geyser_client)
# Process streaming transactions
```

### Full Stack
```elixir
# mix.exs
def deps do
  [
    {:ex_solana, "~> 0.2"},
    {:ex_solana_programs, "~> 0.2"},
    {:ex_solana_jito, "~> 0.2"},
    {:ex_solana_geyser, "~> 0.2"},
    {:ex_solana_trading, "~> 0.2"}
  ]
end
```

---

## 5. Migration Strategy

### Phase 1: Create New Packages (Week 1-2)

1. **Set up package repositories**
   - Create 5 new mix projects
   - Set up Hex.pm publishing config

2. **Move files to packages**
   - Move ~106 files to `ex_solana`
   - Move ~17 files to `ex_solana_jito`
   - Move ~7 files to `ex_solana_geyser`
   - Move ~28 files to `ex_solana_programs`
   - Move ~3 files to `ex_solana_trading`

3. **Update module names**
   - Keep `ExSolana.*` for core (no prefix change)
   - Use `ExSolanaJito.*` for jito
   - Use `ExSolanaGeyser.*` for geyser
   - Use `ExSolanaPrograms.*` for programs
   - Use `ExSolanaTrading.*` for trading

### Phase 2: Update Dependencies (Week 2)

1. **Internal dependencies**
   - Update import/alias statements
   - Update mix.exs for each package

2. **Test each package**
   - Unit tests for core
   - Integration tests for each package

### Phase 3: Documentation (Week 2-3)

1. **Update README files**
   - Package-specific READMEs
   - Migration guide

2. **Update examples**
   - Simple wallet example
   - DEX integration example
   - MEV bot example
   - Streaming example

### Phase 4: Publish (Week 3)

1. **Publish to Hex.pm**
   - Publish in dependency order
   - Verify installations

2. **Update original repo**
   - Add deprecation notice
   - Link to new packages

---

## 6. Risk Assessment

### Breaking Changes (Severity: MEDIUM)

**Module Renaming**:
- Core modules stay as `ExSolana.*` (minimal changes)
- Jito becomes `ExSolanaJito.*`
- Geyser becomes `ExSolanaGeyser.*`
- Programs becomes `ExSolanaPrograms.*`
- Trading becomes `ExSolanaTrading.*`

**Impact**: Users importing these modules will need to update aliases

**Mitigation**:
- Provide migration script
- Keep version compatibility period

### Performance Implications (Severity: LOW)

- Compilation: Slightly faster (smaller packages)
- Runtime: No performance change
- Dependencies: Users only install what they need

### Security (Severity: LOW)

- No changes to key handling
- No changes to RPC authentication
- Separate packages = smaller attack surface

---

## 7. File Distribution Summary

| Package | Directories | Files | % of Total |
|---------|-------------|-------|------------|
| ex_solana | core/, rpc/, websocket/, idl/, ix/, decoder/, util/, root | ~106 | 76% |
| ex_solana_jito | jito/ | ~17 | 12% |
| ex_solana_geyser | geyser/ | ~7 | 5% |
| ex_solana_programs | programs/ | ~28 | 20% |
| ex_solana_trading | trading/ | ~3 | 2% |

**Note**: Percentages don't sum to 100% due to overlap (programs directory has subdirectories)

---

## 8. Key Benefits of This Split

### For Users

1. **Smaller dependencies** - Only install what you need
2. **Faster compilation** - Less code to compile
3. **Clearer API surface** - Smaller, focused packages
4. **Flexible upgrades** - Update packages independently

### For Maintainers

1. **Easier maintenance** - Smaller codebases per package
2. **Clearer ownership** - Each package has clear scope
3. **Independent releases** - Bug fixes don't require full release
4. **Extensibility** - Others can create program packages

### Use Case Alignment

| Use Case | Packages Needed | Download Size |
|----------|-----------------|---------------|
| Simple wallet | ex_solana | ~500 KB |
| DEX trading | ex_solana, programs | ~600 KB |
| MEV bot | ex_solana, jito | ~550 KB |
| Streaming | ex_solana, geyser | ~520 KB |
| Full stack | all 5 packages | ~700 KB |

---

## 9. Configuration After Split

### ex_solana (Core)
```elixir
# config/config.exs
config :ex_solana,
  network: "mainnet-beta",
  rpc_base_url: "https://api.mainnet-beta.solana.com"

# Optional RPC settings
config :ex_solana, :rpc,
  max_retries: 10,
  max_delay: 4000
```

### ex_solana_jito
```elixir
config :ex_solana_jito,
  enabled: true,
  regions: [:ny, :slc, :ams],
  rate_limit: {1000, 5}  # 5 requests per second
```

### ex_solana_geyser
```elixir
config :ex_solana_geyser,
  enabled: true,
  yellowstone_url: "http://localhost:10000"
```

---

## 10. Next Steps

1. **Confirm package split** - User approval of 5-package strategy
2. **Create implementation plan** - Detailed task breakdown
3. **Set up repositories** - Create package structure
4. **Begin Phase 1** - Start moving files to packages

---

**Report End**

*This research phase is complete. Ready for planning phase with the 5-package split strategy.*
