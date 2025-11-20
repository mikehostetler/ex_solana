# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Parallel dispatch processing for multiple targets with configurable concurrency (default: 8)
- Configuration option `:dispatch_max_concurrency` to control parallel dispatch concurrency
- Self-call detection for Named adapter in sync mode to prevent deadlocks

### Changed
- **BREAKING:** `dispatch/2` with multiple configs now returns `{:error, [errors]}` instead of first error only
- Removed double validation overhead (internal optimization - no API impact)
- Simplified batch processing to use single async stream (internal optimization)
- Improved batch dispatch concurrency defaults from 5 to 8

### Deprecated
- `batch_size` option in `dispatch_batch/3` - kept for backwards compatibility but no longer used

### Performance
- ~40% reduction in hot-path overhead from eliminating double validation
- Significant speedup for multi-target dispatch (e.g., 10 targets with 100ms latency: ~200ms vs ~1000ms sequential)
- **Router optimizations (50-100x improvement in pattern matching):**
  - Optimized `Router.matches?/2` - eliminated trie build and UUID generation per call
  - Optimized multi-wildcard (`**`) matching - reduced memory allocations
  - Optimized `route_count` tracking - O(N) → O(1) for removal operations
  - Optimized `has_route?/2` - O(N) → O(depth) direct trie lookup
  - Optimized trie build - precomputed segments to avoid repeated string splits

### Fixed
- Named adapter now prevents self-call deadlocks in sync delivery mode

### Removed
### Security

## [1.0.0] - 2025-02-03

### Added
- Initial release of Jido Signal
- Signal processing and event handling framework
- Bus-based pub/sub system with adapters
- Signal routing with pattern matching
- Multiple dispatch adapters: `:pid`, `:pubsub`, `:http`, `:bus`, `:named`, `:console`, `:logger`, `:noop`
- In-memory persistence via ETS
- Middleware pipeline support
- Comprehensive test suite with 80%+ coverage
- Documentation with guides and examples
- OTP supervision tree architecture

[Unreleased]: https://github.com/agentjido/jido_signal/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/agentjido/jido_signal/releases/tag/v1.0.0
