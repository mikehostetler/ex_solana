# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Modern core package structure following Jido ecosystem standards
- Zoi schema validation for all data structures
- Splode error handling with structured error classes
- Req HTTP client for RPC communication
- GitHub Actions CI/CD workflows
- Quality tooling (Credo, Dialyzer, ExCoveralls)

### Changed
- Migrated from TypedStruct to Zoi for schema validation
- Migrated from Tesla to Req for HTTP client
- Migrated from tuple errors to Splode error classes
- Updated to modern Elixir 1.18+

## [0.2.0] - 2025-01-XX

### Added
- Initial release of modernized ex_solana package
- Core type modules (Key, Account, Transaction, Signature, Mnemonic, Block)
- RPC client with Req
- Error hierarchy with Splode
- Utility modules
