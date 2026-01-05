# AGENTS.md - Jido Sandbox

## Project Overview

Jido Sandbox provides a lightweight, pure-BEAM sandbox for LLM tool calls. It implements an in-memory virtual filesystem (VFS) and sandboxed Lua execution.

## Key Constraints (Features, not bugs)

- **No real filesystem access** - All files are virtual
- **No networking** - No HTTP, sockets, or external connections
- **No shell/process execution** - No System.cmd, ports, or NIFs
- **Lua-only scripting** - Sandboxed Lua with VFS bindings only
- **All paths are virtual and absolute** - Must start with `/`

## Common Commands

- `mix test` - Run tests
- `mix quality` - Run all quality checks
- `mix coveralls` - Run tests with coverage

## Public API

- `JidoSandbox.new/1` - Create a new sandbox
- `JidoSandbox.write/3` - Write file to VFS
- `JidoSandbox.read/2` - Read file from VFS
- `JidoSandbox.list/2` - List directory contents
- `JidoSandbox.delete/2` - Delete file from VFS
- `JidoSandbox.mkdir/2` - Create directory
- `JidoSandbox.snapshot/1` - Save VFS state
- `JidoSandbox.restore/2` - Restore VFS state
- `JidoSandbox.eval_lua/2` - Execute Lua code

## Architecture

- `JidoSandbox` - Public API module
- `JidoSandbox.Sandbox` - Core sandbox struct and operations
- `JidoSandbox.VFS` - VFS behavior
- `JidoSandbox.VFS.InMemory` - In-memory VFS implementation
- `JidoSandbox.Lua.Runtime` - Sandboxed Lua execution
