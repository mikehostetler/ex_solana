# Jido Sandbox

[![Hex.pm](https://img.shields.io/hexpm/v/jido_sandbox.svg)](https://hex.pm/packages/jido_sandbox)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/jido_sandbox)

In-memory sandbox (VFS + Lua) for LLM tool calls.

## Installation

Add `jido_sandbox` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_sandbox, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Create a new sandbox
sandbox = JidoSandbox.new()

# Write a file
{:ok, sandbox} = JidoSandbox.write(sandbox, "/hello.txt", "Hello, World!")

# Read it back
{:ok, content} = JidoSandbox.read(sandbox, "/hello.txt")
# => "Hello, World!"

# List directory
{:ok, files} = JidoSandbox.list(sandbox, "/")
# => ["hello.txt"]

# Create a snapshot
{:ok, snapshot_id, sandbox} = JidoSandbox.snapshot(sandbox)

# Make changes and restore
{:ok, sandbox} = JidoSandbox.delete(sandbox, "/hello.txt")
{:ok, sandbox} = JidoSandbox.restore(sandbox, snapshot_id)
# File is back!

# Execute Lua (with VFS access)
{:ok, result, sandbox} = JidoSandbox.eval_lua(sandbox, """
  local content = vfs.read("/hello.txt")
  return string.upper(content)
""")
# => "HELLO, WORLD!"
```

## Key Features

- **Pure in-memory VFS** - No real filesystem access
- **Sandboxed Lua execution** - Safe scripting with VFS bindings
- **Snapshot/restore** - Save and restore VFS state
- **Path validation** - Blocks traversal attacks
- **Zero external dependencies** at runtime (except Lua NIF)

## Documentation

See [HexDocs](https://hexdocs.pm/jido_sandbox) for full documentation.

## License

Apache-2.0
