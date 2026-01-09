# Lifecycle and Persistence

Understanding how Sprites hibernate, wake, and persist state.

## The Sprite Lifecycle

```
Created → Active → Idle (30s) → Hibernated → Wake-on-Request → Active
```

Sprites aren't always running. They:
1. Start **active** when created
2. **Hibernate** after 30 seconds idle
3. **Wake** automatically when accessed

## Automatic Hibernation

**Default timeout:** 30 seconds (not configurable yet)

A Sprite is **active** when any of these are true:

| Activity | Description |
|----------|-------------|
| Command executing | Via `exec` or console |
| stdin being written | Data flowing to process |
| TCP connection | Active connection to Sprite URL |
| Detachable session | Background process running |

When **hibernated:**
- **No compute charges** - Only pay for storage
- **Full state preserved** - All files intact
- **Instant wake** - Resumes on next request

## Wake-on-Request

Sprites wake automatically when:
- CLI command executes
- HTTP request hits the Sprite URL
- API call is made

Wake time is typically under a few seconds. Requests block until ready.

## Persistence

### What's Preserved

Every Sprite has a persistent ext4 filesystem:

| Persisted | Not Persisted |
|-----------|---------------|
| All files and directories | Running processes |
| Installed packages | Network connections |
| Environment configurations | In-memory state |
| Git repositories | `/tmp` files |
| Databases (SQLite, etc.) | Process PIDs |

### Storage Architecture

- **Active:** Fast NVMe-backed storage
- **Hibernated:** Snapshotted to object storage
- **Resume:** Snapshot restored and mounted

### Storage Specs

| Property | Value |
|----------|-------|
| Provisioned | 100 GB |
| Filesystem | ext4 |
| Billing | Actual usage (TRIM-friendly) |

## Sprite States

| State | Description |
|-------|-------------|
| `pending` | Being created |
| `active` | Running and ready |
| `hibernating` | Transitioning to sleep |
| `hibernated` | No compute, storage only |
| `waking` | Coming back from hibernation |
| `error` | Encountered an error |

## Resource Profile

Fixed per Sprite:

| Resource | Value |
|----------|-------|
| vCPUs | 8 |
| RAM | 8 GB |
| Storage | 100 GB |

## Detached Sessions

Long-running processes that:
- Persist across CLI disconnects
- Survive hibernation
- Resume when Sprite wakes

```elixir
{:ok, cmd} = Sprites.spawn(sprite, "npm", ["run", "dev"], detachable: true)
```

For persistent services that auto-start on wake, see [Services](./services.md).

## Best Practices

1. **Use file-based databases** - SQLite works great with persistent storage

2. **Plan for 30s hibernation** - Keep something running to stay warm

3. **Clean up temp state** - Flush data before idle

4. **Checkpoint long-running work** - Write progress to disk

5. **Don't fight the lifecycle** - Let Sprites sleep unless you need real-time
