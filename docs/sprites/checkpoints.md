# Checkpoints

Save and restore Sprite state with checkpoints.

## What is a Checkpoint?

A snapshot of your Sprite's persistent state:

**Included:**
- Complete filesystem
- Installed packages
- Configuration files
- Services and policies

**Not Included:**
- Running processes
- Network connections
- In-memory state

Creating a checkpoint takes ~300ms and doesn't interrupt the Sprite.

## Creating Checkpoints

### CLI

```bash
sprite checkpoint create --comment "Clean Python 3.11 + Node 20 setup"
# Checkpoint created: v1
```

### Elixir

```elixir
{:ok, messages} = Sprites.create_checkpoint(sprite, comment: "Before deploy")

Enum.each(messages, fn
  %{"status" => "complete", "id" => id} -> IO.puts("Checkpoint: #{id}")
  %{"type" => "info", "data" => data} -> IO.puts(data)
  _ -> :ok
end)
```

## Restoring from Checkpoints

Replaces current filesystem with saved snapshot. Stops running processes.

### CLI

```bash
sprite restore v1
```

### Elixir

```elixir
{:ok, messages} = Sprites.restore_checkpoint(sprite, "v1")

Enum.each(messages, fn
  %{"status" => "complete"} -> IO.puts("Restore complete")
  _ -> :ok
end)
```

**Restore Notes:**
- Fast - typically under a second
- Destructive - current state replaced
- Processes terminated - restart manually
- CLI auto-retries if Sprite still restarting

## Managing Checkpoints

### List

```bash
sprite checkpoint list
```

```elixir
{:ok, checkpoints} = Sprites.list_checkpoints(sprite)
```

### Get Info

```bash
sprite checkpoint info v1
```

```elixir
{:ok, cp} = Sprites.get_checkpoint(sprite, "v1")
IO.puts("ID: #{cp.id}, Created: #{cp.create_time}, Comment: #{cp.comment}")
```

### Delete

```bash
sprite checkpoint delete v3
```

**Restrictions:**
- Cannot delete active checkpoint
- Deleted checkpoints cannot be recovered

## Internal API

Manage checkpoints from within the Sprite:

```bash
# Using sprite-env
sprite-env checkpoints list
sprite-env checkpoints create
sprite-env checkpoints restore v1

# Direct API
curl --unix-socket /.sprite/api.sock \
  -H "Content-Type: application/json" \
  http://sprite/v1/checkpoints
```

## Storage

- **Copy-on-write:** Only changed blocks copied
- **Geographically redundant:** Replicated across regions
- **Billing:** $0.50/GB/month (actual usage only)

Last 5 checkpoints are mounted read-only at `/.sprite/checkpoints/`.

## Common Patterns

### Environment Templates

```bash
# Create baseline
sprite create gold-standard
sprite exec "install-base-tools.sh"
sprite checkpoint create --comment "Gold standard v1.0"

# Start new projects from baseline
sprite use gold-standard
sprite restore v1
```

### Automated Rollback

```bash
#!/bin/bash
# Create safety checkpoint
sprite checkpoint create --comment "Pre-deploy $(date)"

# Try deployment
if ! sprite exec "deploy.sh"; then
  echo "Rolling back..."
  sprite restore v$(sprite checkpoint list | head -2 | tail -1 | awk '{print $1}')
  exit 1
fi
```

### A/B Testing

```bash
# Create base
sprite exec "setup-base.sh"
sprite checkpoint create --comment "Base for A/B"

# Variant A
sprite create variant-a
sprite restore v1
sprite exec "apply-config-a.sh"

# Variant B
sprite create variant-b
sprite restore v1
sprite exec "apply-config-b.sh"
```

### LLM Self-Checkpointing

Point LLM at `/.sprite/llm.txt` to enable programmatic checkpoint management:

```bash
# Before risky operations
sprite-env checkpoints create

# If things go wrong
sprite-env checkpoints restore v4
```

## Best Practices

1. **Use descriptive comments** - Sequential IDs (v0, v1, v2) need context

2. **When to checkpoint:**
   - Daily during active development
   - Before risky operations
   - After milestones

3. **Clean up old checkpoints** - They use storage

4. **Use Git for code** - Checkpoints are for environment state, not version control

5. **Keep one stable checkpoint** - Always have a known-good fallback
