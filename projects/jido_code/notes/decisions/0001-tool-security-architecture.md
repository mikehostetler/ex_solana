# ADR-0001: Tool Security Architecture

## Status

Accepted

## Date

2024-12-28

## Context

JidoCode provides tools that the LLM agent can invoke to interact with the file system, execute shell commands, and perform other potentially dangerous operations. These tools must be secured to prevent:

1. **Path traversal attacks** - Accessing files outside the project boundary
2. **Command injection** - Executing arbitrary shell commands
3. **Symlink escape** - Using symlinks to access protected files
4. **TOCTOU races** - Time-of-check to time-of-use vulnerabilities

The codebase has two security mechanisms:

1. **Lua Sandbox** (`Tools.Manager` + `Bridge`) - A Luerl-based sandbox that:
   - Removes dangerous Lua functions (`os.execute`, `io.popen`, `loadfile`, etc.)
   - Provides bridge functions (`jido.read_file`, `jido.shell`) that validate paths
   - Designed for executing user-defined Lua scripts

2. **Security Module** (`Tools.Security`) - Elixir module providing:
   - `validate_path/3` - Path boundary validation with symlink resolution
   - `atomic_read/2`, `atomic_write/3` - TOCTOU-safe file operations
   - Command allowlist validation

The question: Should built-in tools (read_file, write_file, grep, etc.) go through the Lua sandbox, or use direct Elixir handlers with the Security module?

## Decision

**All tools route through the Lua sandbox for defense-in-depth security.**

The architecture is:

```
┌─────────────────────────────────────────────────────────────┐
│                     Tool Executor                            │
│  Dispatches all tool calls through Lua sandbox              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Lua Sandbox                                │
│                   (Tools.Manager)                            │
│                                                              │
│  - Dangerous functions removed (os.execute, io.popen, etc.) │
│  - All operations go through Bridge functions                │
│  - Restricted execution environment                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Bridge Functions                           │
│                   (Tools.Bridge)                             │
│                                                              │
│  - jido.read_file()    - jido.write_file()                  │
│  - jido.list_dir()     - jido.delete_file()                 │
│  - jido.shell()        - jido.mkdir_p()                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Tools.Security Module                      │
│  - validate_path/3      - atomic_read/2                     │
│  - validate_command/1   - atomic_write/3                    │
└─────────────────────────────────────────────────────────────┘
```

All tool operations pass through two security layers:
1. Lua sandbox restrictions (no dangerous functions available)
2. Security module validation (path boundaries, command allowlist)

## Consequences

### Positive

- **Defense in depth**: Two independent security layers
- **Single code path**: All tools use the same security enforcement
- **Auditability**: One place to review security controls
- **User extensibility**: Same sandbox model for built-in and custom tools
- **Consistency**: Uniform execution model for all tools

### Negative

- **Performance overhead**: Lua VM adds latency to every tool call
- **Debugging complexity**: Lua stack traces mixed with Elixir
- **Dependency**: Requires Luerl library

### Neutral

- Existing Bridge functions already implement most tool operations
- Session-aware security context works through the sandbox

## Alternatives Considered

### Alternative 1: Direct Elixir Handlers

Bypass Lua sandbox, implement tools as direct Elixir handlers using Security module only.

**Pros:**
- Better performance (no Lua VM overhead)
- Easier debugging (pure Elixir stack traces)
- Type safety with pattern matching

**Cons:**
- Single security layer only
- Dual code paths (Bridge for Lua, handlers for Elixir)
- Less consistent execution model

**Why not chosen:** Security is paramount. The defense-in-depth approach of routing through the Lua sandbox provides an additional security barrier. The performance cost is acceptable for the added protection.

### Alternative 2: Remove Lua Sandbox Entirely

Implement all security in Elixir only, remove Lua sandbox.

**Pros:**
- Simpler codebase
- One language to maintain
- No Luerl dependency

**Cons:**
- Loses defense-in-depth
- Single point of failure for security
- No user-extensibility via scripts

**Why not chosen:** Removing a security layer is unacceptable. The Lua sandbox provides meaningful protection even if the Security module has bugs.

## Implementation Notes

All new tools in the tooling plan (Phase 1-6) must:

1. Define Bridge functions in `lib/jido_code/tools/bridge.ex`
2. Register functions via `Bridge.register/2`
3. Use `Security.validate_path/3` for all path operations
4. Use `Security.atomic_read/2` and `atomic_write/3` for file I/O
5. Validate shell commands against the allowlist

Tool handlers become thin wrappers that invoke Bridge functions through the sandbox.

## References

- `lib/jido_code/tools/security.ex` - Security validation module
- `lib/jido_code/tools/manager.ex` - Lua sandbox manager
- `lib/jido_code/tools/bridge.ex` - Lua bridge functions
- `notes/planning/tooling/` - Tool implementation plan
