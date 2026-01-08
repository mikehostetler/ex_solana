# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-01-08

### Added

- Initial release
- `JidoFlame.Directive.RemoteCall` - FLAME.call/3 directive
- `JidoFlame.Directive.RemoteCast` - FLAME.cast/3 directive  
- `JidoFlame.Directive.SpawnRemoteAgent` - Spawn Jido agents on FLAME runners
- `JidoFlame.Directive.PlaceRemoteChild` - Generic FLAME.place_child/3
- `JidoFlame.Directive.StopRemoteAgent` - Stop remote child agents
- `JidoFlame.Owner` - GenServer managing FLAME links with Owner pattern
- `JidoFlame.AgentRegistry` - Logical agent ID to PID mapping
- `JidoFlame.ChildRegistry` - {agent_id, tag} to Owner PID mapping
- `JidoFlame.DirectiveExec` - Directive execution engine
- `JidoFlame.Skill` - Skill for easy agent integration
- `JidoFlame.TestAgent` - Test agent for remote spawning verification
- `JidoFlame.Remote` - Helper functions for remote FLAME nodes
- `mix jido.flame.doctor` - Diagnostic task
- Actions: `RemoteCall`, `RemoteCast`, `SpawnRemoteAgent`, `StopRemoteAgent`
