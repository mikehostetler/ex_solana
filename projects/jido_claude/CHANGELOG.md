# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-08

### Added

- Initial release
- `ClaudeSessionAgent` for managing single Claude sessions
- `StartSession`, `HandleMessage`, `CancelSession` actions
- `StreamRunner` for handling SDK streaming
- `Signals` module for Claude event signals
- Parent integration modules:
  - `SessionRegistry` for tracking multiple sessions
  - `SpawnSession` for spawning child sessions
  - `HandleSessionEvent` for processing child signals
  - `CancelSession` for cancelling child sessions
