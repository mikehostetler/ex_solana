# Pump.fun Testing Guide

This guide explains how to run comprehensive tests for pump.fun functionality in your `ex_solana` library.

## Test Levels

### 1. Unit Tests (Always Available)
Tests the pump.fun IDL decoders without requiring network access:
```bash
mix test test/ex_solana/programs/pump_fun_test.exs
```

### 2. Integration Tests (Network Dependent)
Tests the full pump.fun lifecycle with real or simulated program execution.

## Network Configuration

### Local Test Validator (Default)
```bash
# Run with local test validator (default)
mix test test/ex_solana/integration/pump_fun_lifecycle_test.exs
```

### Testnet
```bash
# Test against Solana testnet
PUMP_TEST_NETWORK=testnet mix test test/ex_solana/integration/pump_fun_lifecycle_test.exs
```

### Devnet
```bash
# Test against Solana devnet
PUMP_TEST_NETWORK=devnet mix test test/ex_solana/integration/pump_fun_lifecycle_test.exs
```

### Mainnet (Read-only tests)
```bash
# Test against Solana mainnet (read-only validation)
PUMP_TEST_NETWORK=mainnet mix test test/ex_solana/integration/pump_fun_lifecycle_test.exs
```

## Full Program Testing

For complete end-to-end testing with actual program execution, you need the pump.fun program binary:

### 1. Obtain Program Binary
```bash
# Create programs directory
mkdir -p priv/programs

# Option A: Extract from existing deployment (requires solana CLI)
solana program dump 6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P priv/programs/pump.so --url mainnet-beta

# Option B: Use a locally built version (if available)
# cp /path/to/pump-program/target/deploy/pump.so priv/programs/pump.so
# cp /path/to/pump-program/target/deploy/pump-keypair.json priv/programs/pump-keypair.json
```

### 2. Run Full Integration Tests
```bash
# With program binary available, run complete tests
mix test test/ex_solana/integration/ --include integration
```

## Test Tags

Use test tags to run specific test categories:

```bash
# Run only network connectivity tests
mix test --only network_check

# Run only local validator tests
mix test --only local_only

# Run error handling tests
mix test --only error_handling

# Run network configuration tests
mix test --only network_config

# Include integration tests (normally excluded)
mix test --include integration
```

## Expected Test Behavior

### Without Program Binary
- Unit tests: ✅ Full functionality
- Integration tests: ⚠️ Limited to network validation and instruction encoding

### With Program Binary (Local)
- Unit tests: ✅ Full functionality
- Integration tests: ✅ Complete create → buy → sell lifecycle testing

### Live Networks (Testnet/Devnet/Mainnet)
- Unit tests: ✅ Full functionality
- Integration tests: ✅ Program validation and account reading
- Transaction tests: ⚠️ Requires funded test accounts

## Security Considerations

### Testnet/Devnet Testing
- Use test SOL only
- Never use real funds for testing
- Test accounts should have minimal balances

### Mainnet Testing
- **READ-ONLY operations only**
- Never submit test transactions to mainnet
- Use for validation and account inspection only

## Troubleshooting

### Program Not Found Error
```
Error: pump.fun program not found on target network
```
- Verify network connectivity
- Check if pump.fun is deployed on the target network
- For local testing, ensure test validator is running

### Test Timeout
```
Error: Test timeout after 120 seconds
```
- Network congestion on live networks
- Increase timeout in test configuration
- Use local test validator for faster testing

### Insufficient Funds
```
Error: Insufficient lamports for transaction
```
- For local: Test helper will fund accounts automatically
- For live networks: Ensure test accounts have sufficient balance

## Advanced Configuration

### Custom RPC Endpoints
```bash
# Use custom RPC endpoint
SOLANA_RPC_URL=https://your-custom-rpc.com mix test
```

### Test Account Management
```bash
# Generate test keypairs for live network testing
solana-keygen new -o test-creator.json
solana-keygen new -o test-trader1.json
solana-keygen new -o test-trader2.json

# Fund on testnet
solana airdrop 5 test-creator.json --url testnet
```

## Continuous Integration

For CI/CD pipelines, use local test validator:

```yaml
# Example GitHub Actions step
- name: Run Pump.fun Tests
  run: |
    mix test test/ex_solana/programs/pump_fun_test.exs
    mix test test/ex_solana/integration/ --exclude live_network
```

## Performance Benchmarks

The test suite includes performance validation:
- Instruction encoding/decoding: < 1ms
- Account parsing: < 5ms
- Network round-trip (local): < 100ms
- Network round-trip (testnet): < 2s

## Contributing

When adding new pump.fun functionality:

1. Add unit tests for all new IDL elements
2. Update integration tests for new instruction types
3. Verify tests pass on both local and testnet
4. Document any new environment requirements