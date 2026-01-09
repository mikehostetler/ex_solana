# Sprites Documentation

Local reference for Fly.io Sprites - programmable Linux containers for code execution.

> Source: https://docs.sprites.dev | SDK: https://github.com/superfly/sprites-ex

## Contents

- [Overview](./overview.md) - What Sprites are and core concepts
- [Elixir SDK](./elixir-sdk.md) - Complete Elixir SDK reference
- [Lifecycle](./lifecycle.md) - Hibernation, persistence, and state management  
- [Networking](./networking.md) - URLs, port forwarding, and network access
- [Checkpoints](./checkpoints.md) - Save and restore Sprite state
- [Services](./services.md) - Long-running processes that persist across reboots

## Quick Reference

```elixir
# Create client
client = Sprites.new(System.get_env("SPRITE_TOKEN"))

# Create sprite
{:ok, sprite} = Sprites.create(client, "my-sprite")

# Execute command (blocking)
{output, 0} = Sprites.cmd(sprite, "echo", ["hello"])

# Execute command (async/streaming)
sprite
|> Sprites.stream("npm", ["run", "dev"])
|> Stream.each(&IO.write/1)
|> Stream.run()

# Destroy
:ok = Sprites.destroy(sprite)
```

## Why Sprites for Jido?

Sprites provide:

1. **Secure code execution** - Run LLM-generated code in isolated containers
2. **Persistent environments** - Clone repos, install deps, run tests across sessions
3. **Checkpoints** - Save state before risky operations, restore on failure
4. **Auto-hibernation** - No compute charges when idle, instant wake on demand
5. **Pre-installed tools** - Node.js, Python, Go, Ruby, Rust, Elixir, AI CLIs

## Workspace Commands

```bash
mix sprite.list              # List all sprites
mix sprite.create NAME       # Create a new sprite
mix sprite.destroy NAME      # Destroy a sprite
```
