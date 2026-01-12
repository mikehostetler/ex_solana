# ExSolana Package Split - Strategic Implementation Plan

**Date**: 2026-01-12
**Planning Phase**: Strategic Implementation Plan
**Status**: Ready for Breakdown

---

## Executive Summary

This plan transforms the research findings into a comprehensive implementation strategy for splitting `ex_solana` into 5 focused packages with **modern technology choices**:

- **`req`** - Replace Tesla/Mint with `req` for HTTP client
- **`zoi`** - Replace TypedStruct and NimbleOptions with `zoi` for all data schema concerns
- **`splode`** - Replace tuple error handling with `splode` for structured error management

---

## 1. Technology Migration Strategy

### 1.1 HTTP Client Migration: Tesla → `req`

**Current State** (`lib/ex_solana/rpc.ex:15-102`):
```elixir
# Uses Tesla with Mint adapter
@type client :: Tesla.Client.t()
def client(opts) do
  middleware = build_middleware(config, base_url)
  Tesla.client(middleware, config.adapter)
end
```

**Target State**:
```elixir
# Use req for simpler, composable HTTP client
@type client :: Req.t()
def client(opts) do
  Req.new(base_url: base_url, auth: auth, retry: :safe_transient)
end
```

**Benefits**:
- Built-in retry logic (`:safe_transient`)
- Simpler API (no middleware stack complexity)
- Better debugging with `req:` logger
- Native support for WebSockets
- Smaller dependency footprint

**Migration Scope**:
- `lib/ex_solana/rpc.ex` - Main RPC client
- `lib/ex_solana/rpc/middleware.ex` - Can be removed
- `lib/ex_solana/websocket.ex` - Use `req_websocket` adapter

---

### 1.2 Schema Migration: TypedStruct + NimbleOptions → `zoi`

**Current State** (`lib/ex_solana/rpc.ex:18-49`):
```elixir
# Uses NimbleOptions for client options validation
@client_schema [
  adapter: [
    type: :any,
    default: Tesla.Adapter.Mint,
    doc: "Which `Tesla` adapter to use."
  ],
  network: [
    type: {:custom, __MODULE__, :cluster_url, []},
    required: false,
    doc: "Which cluster to connect to."
  ]
]
```

**Target State**:
```elixir
# Use zoi for schemas
use Zoi

schema :client_config do
  field :network, :string, default: "mainnet-beta"
  field :base_url, :string
  field :api_key, :string
  field :retry_enabled, :boolean, default: true
  field :max_retries, :integer, default: 10
end
```

**Current State** (TypedStruct usage in core types):
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

**Target State**:
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

**Benefits**:
- Single library for all schema concerns
- Built-in validation at compile time
- Better error messages
- Consistent API across all modules

**Migration Scope**:
- All TypedStruct usages in `lib/ex_solana/core/`
- All NimbleOptions usages in `lib/ex_solana/rpc.ex`
- Configuration validation in `lib/ex_solana/config.ex`

---

### 1.3 Error Handling Migration: Tuples → `splode`

**Current State** (`lib/ex_solana/core/key.ex:46-54`):
```elixir
@spec decode(encoded :: binary) :: {:ok, t} | {:error, binary}
def decode(encoded) when is_binary(encoded) do
  case B58.decode58(encoded) do
    {:ok, decoded} -> check(decoded)
    _ -> {:error, "invalid public key"}
  end
end
```

**Target State**:
```elixir
defmodule ExSolana.Errors.InvalidKeyError do
  use Splode.Error,
    fields: [:key, :reason],
    class: :invalid
end

@spec decode(encoded :: binary) :: {:ok, t} | Splode.Error.t()
def decode(encoded) when is_binary(encoded) do
  case B58.decode58(encoded) do
    {:ok, decoded} -> check(decoded)
    _ -> splode(InvalidKeyError, key: encoded, reason: "decode_failed")
  end
end
```

**Error Class Hierarchy**:
```
ExSolana.Error (base)
├── ExSolana.Errors.InvalidKeyError
├── ExSolana.Errors.RPCError
│   ├── ExSolana.Errors.NetworkError
│   ├── ExSolana.Errors.TimeoutError
│   └── ExSolana.Errors.RateLimitError
├── ExSolana.Errors.TransactionError
│   ├── ExSolana.Errors.InstructionError
│   └── ExSolana.Errors.ConfirmationError
└── ExSolana.Errors.IDLError
```

**Benefits**:
- Structured error classes with stack traces
- Better error messages for debugging
- Consistent error handling across packages
- Integration with Logger and telemetry

**Migration Scope**:
- All error tuples in `lib/ex_solana/`
- RPC error handling in `lib/ex_solana/rpc/`
- Transaction error handling in `lib/ex_solana/core/tx.ex`

---

## 2. Package Architecture

### 2.1 Dependency Graph (Updated)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              ex_solana                                    │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  Core Package (~106 files)                                          │  │
│  │  Technology: req, zoi, splode, grpc, protobuf                       │  │
│  │                                                                     │  │
│  │  ┌─────────────────┐  ┌─────────────┐  ┌─────────────────────┐    │  │
│  │  │ Core Types      │  │ RPC Client  │  │ WebSocket           │    │  │
│  │  │ • Key           │  │ • Req       │  │ • req_websocket     │    │  │
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
│  Errors: splode | Schemas: zoi | HTTP: req                                │
└────────────────────────────────┬──────────────────────────────────────────┘
                                 │
         ┌───────────────────────┼───────────────────────┐
         │                       │                       │
    ┌────▼────────┐       ┌──────▼──────┐        ┌──────▼──────┐
    │ex_solana_   │       │ex_solana_   │        │ex_solana_   │
    │jito         │       │geyser       │        │programs     │
    │(~17 files)  │       │(~7 files)   │        │(~28 files)  │
    │MEV bundles  │       │Streaming    │        │DEX, SPL     │
    │req, grpc    │       │grpc,broadway│        │zoi schemas  │
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

### 2.2 Module Namespace Strategy

| Package | Module Prefix | Example |
|---------|---------------|---------|
| ex_solana | `ExSolana.*` | `ExSolana.RPC`, `ExSolana.Key` |
| ex_solana_jito | `ExSolanaJito.*` | `ExSolanaJito.Bundle`, `ExSolanaJito.SearcherClient` |
| ex_solana_geyser | `ExSolanaGeyser.*` | `ExSolanaGeyser.Client`, `ExSolanaGeyser.Pipeline` |
| ex_solana_programs | `ExSolanaPrograms.*` | `ExSolanaPrograms.SPL.Token`, `ExSolanaPrograms.Jupiter` |
| ex_solana_trading | `ExSolanaTrading.*` | `ExSolanaTrading.ProfitLoss`, `ExSolanaTrading.RiskManager` |

---

## 3. Implementation Phases

### Phase 1: Foundation and Technology Migration (Week 1-2)

**Objective**: Set up package structure and migrate core technologies

#### 1.1 Create Package Structure
- [ ] Create 5 new mix projects in monorepo `projects/` directory
- [ ] Set up umbrella app configuration
- [ ] Configure Hex.pm publishing for each package

#### 1.2 Core Technology Migration (ex_solana)
- [ ] Add `req` dependency, remove Tesla/Mint
- [ ] Add `zoi` dependency, remove TypedStruct/NimbleOptions
- [ ] Add `splode` dependency
- [ ] Define error class hierarchy with Splode
- [ ] Migrate RPC client from Tesla to Req
- [ ] Migrate all schemas to Zoi
- [ ] Migrate error handling to Splode

**Success Criteria**:
- All tests pass with new technology stack
- RPC client successfully connects using Req
- Schema validation works with Zoi
- Error classes properly raise with Splode

---

### Phase 2: File Migration and Module Updates (Week 2-3)

**Objective**: Move files to appropriate packages and update module names

#### 2.1 Core Package (ex_solana) - ~106 files
Move and update:
- `core/` → Core types with Zoi schemas
- `rpc/` → RPC with Req client
- `websocket/` → WebSocket with req_websocket
- `idl/` → IDL parser/generator
- `ix/` → Instruction builders
- `decoder/` → Transaction/instruction decoder
- `util/` → Utilities
- Root files → Main entry points

#### 2.2 Jito Package (ex_solana_jito) - ~17 files
- Create `projects/ex_solana_jito/`
- Move `jito/` directory
- Update modules: `ExSolana.Jito.*` → `ExSolanaJito.*`
- Use `req` for HTTP calls
- Use `ExSolana.Errors.*` from core

#### 2.3 Geyser Package (ex_solana_geyser) - ~7 files
- Create `projects/ex_solana_geyser/`
- Move `geyser/` directory
- Update modules: `ExSolana.Geyser.*` → `ExSolanaGeyser.*`
- Use `ExSolana.Errors.*` from core

#### 2.4 Programs Package (ex_solana_programs) - ~28 files
- Create `projects/ex_solana_programs/`
- Move `programs/` directory
- Update modules: `ExSolana.Programs.*` → `ExSolanaPrograms.*`
- Use Zoi for all program schemas
- Use `ExSolana.Errors.*` from core

#### 2.5 Trading Package (ex_solana_trading) - ~3 files
- Create `projects/ex_solana_trading/`
- Move `trading/` directory
- Update modules: `ExSolana.Trading.*` → `ExSolanaTrading.*`
- Use Zoi for trading schemas
- Use `ExSolana.Errors.*` from core

**Success Criteria**:
- All files moved to correct packages
- All module names updated
- All imports/aliases updated
- Packages compile without errors

---

### Phase 3: Testing and Validation (Week 3)

**Objective**: Ensure all packages work independently and together

#### 3.1 Unit Tests
- [ ] Port existing tests to each package
- [ ] Update test helpers for new technology stack
- [ ] Add tests for Req client
- [ ] Add tests for Zoi schemas
- [ ] Add tests for Splode errors

#### 3.2 Integration Tests
- [ ] Test package dependencies
- [ ] Test inter-package communication
- [ ] Test error propagation across packages

#### 3.3 Documentation Updates
- [ ] Update README for each package
- [ ] Create migration guide from old package
- [ ] Update examples with new APIs

**Success Criteria**:
- 100% test coverage for core functionality
- All integration tests pass
- Documentation is complete and accurate

---

### Phase 4: Publishing and Release (Week 4)

**Objective**: Publish packages to Hex.pm in dependency order

#### 4.1 Publish Order
1. **ex_solana** (core) - No internal dependencies
2. **ex_solana_programs** - Depends on ex_solana
3. **ex_solana_jito** - Depends on ex_solana
4. **ex_solana_geyser** - Depends on ex_solana
5. **ex_solana_trading** - Depends on ex_solana

#### 4.2 Post-Publish
- [ ] Verify all packages install correctly
- [ ] Test with fresh project
- [ ] Add deprecation notice to original package
- [ ] Update GitHub repositories

**Success Criteria**:
- All packages published to Hex.pm
- Fresh project test succeeds
- Original package has deprecation notice

---

## 4. Dependencies by Package

### ex_solana (Core)
```elixir
defp deps do
  [
    # Core dependencies
    {:jason, "~> 1.4"},
    {:zoi, "~> 0.2"},           # Replace TypedStruct + NimbleOptions
    {:splode, "~> 0.2"},        # Error handling

    # Cryptography
    {:basefiftyeight, "~> 0.1.0"},
    {:ed25519, "~> 1.3"},
    {:mnemonic, "~> 0.3.1"},
    {:block_keys, "~> 1.0"},

    # HTTP/WebSocket
    {:req, "~> 0.5"},           # Replace Tesla + Mint
    {:websockex, "~> 0.4.3"},   # Keep for WebSocket fallback
    {:phx_json_rpc, "~> 0.7"},
    {:ex_json_schema, "~> 0.11.1"},

    # GRPC
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.15.0"},

    # Dev & Test
    {:mimic, "~> 2.1.0", only: :test}
  ]
end
```

### ex_solana_jito
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:zoi, "~> 0.2"},
    {:splode, "~> 0.2"},
    {:req, "~> 0.5"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.15.0"},
    {:ex_rated, "~> 2.1"}
  ]
end
```

### ex_solana_geyser
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:zoi, "~> 0.2"},
    {:splode, "~> 0.2"},
    {:grpc, "~> 0.9"},
    {:protobuf, "~> 0.15.0"},
    {:broadway, "~> 1.1"}
  ]
end
```

### ex_solana_programs
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:zoi, "~> 0.2"},
    {:splode, "~> 0.2"}
  ]
end
```

### ex_solana_trading
```elixir
defp deps do
  [
    {:ex_solana, "~> 0.2"},
    {:zoi, "~> 0.2"},
    {:splode, "~> 0.2"}
  ]
end
```

---

## 5. Configuration Examples

### ex_solana (Core)
```elixir
# config/config.exs
import Config

config :ex_solana,
  network: "mainnet-beta",
  rpc_base_url: "https://api.mainnet-beta.solana.com"

# RPC settings
config :ex_solana, :rpc,
  max_retries: 10,
  max_delay: 4000,
  retry_enabled: true

# Error handling
config :splode, :default_error_class, ExSolana.Error
```

### ex_solana_jito
```elixir
config :ex_solana_jito,
  enabled: true,
  regions: [:ny, :slc, :ams],
  rate_limit: {1000, 5}
```

### ex_solana_geyser
```elixir
config :ex_solana_geyser,
  enabled: true,
  yellowstone_url: "http://localhost:10000"
```

---

## 6. Risk Assessment

### Breaking Changes (Severity: MEDIUM-HIGH)

**Technology Migration**:
- Tesla → Req: API changes for client creation
- TypedStruct → Zoi: Schema definition syntax changes
- Tuples → Splode: Error handling pattern changes

**Mitigation**:
- Provide comprehensive migration guide
- Create compatibility shim if needed
- Release as major version bump (0.1.0 → 1.0.0)

**Module Renaming**:
- Core modules stay as `ExSolana.*`
- Sub-packages use new prefixes

**Mitigation**:
- Old modules can re-export new ones temporarily
- Clear deprecation messages

---

## 7. Migration Guide for Users

### Before (Old Package)
```elixir
# mix.exs
{:ex_solana, "~> 0.1"}

# Your code
client = ExSolana.RPC.client(network: "mainnet-beta")
case ExSolana.Key.decode(pubkey) do
  {:ok, key} -> key
  {:error, reason} -> handle_error(reason)
end
```

### After (New Packages)
```elixir
# mix.exs
{:ex_solana, "~> 1.0"}

# Your code
client = ExSolana.RPC.client(network: "mainnet-beta")
case ExSolana.Key.decode(pubkey) do
  {:ok, key} -> key
  {:error, %ExSolana.Errors.InvalidKeyError{} = error} ->
    handle_error(error)
end
```

### Error Handling Changes

**Before**:
```elixir
case ExSolana.RPC.send(client, request) do
  {:ok, result} -> result
  {:error, "network error"} -> retry()
end
```

**After**:
```elixir
case ExSolana.RPC.send(client, request) do
  {:ok, result} -> result
  {:error, %ExSolana.Errors.NetworkError{}} = error -> retry(error)
end
```

---

## 8. Success Criteria

Planning phase is complete when:

- [x] Strategic implementation plan created in notes/solana-split/plan.md
- [x] Technology migration strategy defined (req, zoi, splode)
- [x] Package architecture designed with clear dependencies
- [x] Implementation phases defined with objectives and success criteria
- [x] Risk assessment and mitigation strategies documented
- [x] Migration guide for users created
- [x] Ready for **breakdown** phase with comprehensive strategic guidance

---

**Plan Status**: Complete

**Next Phase**: `/breakdown` - Create detailed task breakdown for implementation execution
