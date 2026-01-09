# Services

Long-running processes that persist across Sprite reboots.

## Overview

Services are managed by the Sprite runtime and automatically restart when your Sprite boots. Unlike detachable sessions, services survive full Sprite restarts.

**Use Cases:**
- Development servers that should always run
- Databases (PostgreSQL, Redis, SQLite servers)
- Background workers processing queues
- Reverse proxies and infrastructure

## Managing Services

Services use the internal API at `/.sprite/api.sock`:

```bash
# List all services
sprite-env services list

# Get help
sprite-env services --help
```

## Creating Services

```bash
# Simple service
sprite-env curl -X PUT /v1/services/myapp -d '{
  "cmd": "/usr/bin/myapp",
  "args": ["--port", "8080"]
}'

# Service with dependencies
sprite-env curl -X PUT /v1/services/webapp -d '{
  "cmd": "npm",
  "args": ["run", "dev"],
  "needs": ["database"]
}'
```

### Configuration Fields

| Field | Type | Description |
|-------|------|-------------|
| `cmd` | string | Path to executable (required) |
| `args` | string[] | Command arguments |
| `needs` | string[] | Services that must start first |

### Streaming Logs

Stream logs during creation:

```bash
# Stream for 10 seconds
sprite-env curl -X PUT '/v1/services/myapp?duration=10s' -d '{
  "cmd": "npm",
  "args": ["run", "dev"]
}'
```

Default: 5 seconds. Use `duration=0` to return immediately.

## Service Operations

### List

```bash
sprite-env services list
```

Returns:
```json
[{
  "name": "webapp",
  "cmd": "npm",
  "args": ["run", "dev"],
  "needs": [],
  "state": {
    "status": "running",
    "pid": 1234,
    "started_at": "2024-01-15T10:30:00Z"
  }
}]
```

### Get State

```bash
sprite-env services get webapp
```

### Delete

```bash
sprite-env services delete webapp
```

### Send Signals

```bash
# Graceful shutdown
sprite-env curl -X POST /v1/services/signal -d '{
  "name": "webapp",
  "signal": "TERM"
}'

# Force kill
sprite-env curl -X POST /v1/services/signal -d '{
  "name": "webapp",
  "signal": "KILL"
}'

# Reload config
sprite-env curl -X POST /v1/services/signal -d '{
  "name": "nginx",
  "signal": "HUP"
}'
```

## Services vs Detachable Sessions

| Feature | Services | Detachable Sessions |
|---------|----------|---------------------|
| Survives restart | Yes | No |
| Auto-starts on boot | Yes | No |
| Managed via | Internal API | External CLI/SDK |
| Dependencies | Supported | Not supported |
| Best for | Daemons, servers | One-off tasks |

## Common Patterns

### Development Server

```bash
sprite-env curl -X PUT /v1/services/devserver -d '{
  "cmd": "npm",
  "args": ["run", "dev"]
}'
```

### Database with Dependent Service

```bash
# Create database first
sprite-env curl -X PUT /v1/services/postgres -d '{
  "cmd": "/usr/lib/postgresql/16/bin/postgres",
  "args": ["-D", "/home/sprite/pgdata"]
}'

# Create dependent webapp
sprite-env curl -X PUT /v1/services/webapp -d '{
  "cmd": "npm",
  "args": ["start"],
  "needs": ["postgres"]
}'
```

### Background Worker

```bash
sprite-env curl -X PUT /v1/services/worker -d '{
  "cmd": "python",
  "args": ["-m", "celery", "worker", "-A", "tasks"]
}'
```

## LLM Integration

Point LLM at `/.sprite/llm.txt` to enable service management:

```bash
# Create service
sprite-env curl -X PUT /v1/services/devserver -d '{
  "cmd": "npm",
  "args": ["run", "dev"],
  "dir": "/home/sprite/project"
}'

# Check status
sprite-env services get devserver

# Restart (send TERM, auto-restarts)
sprite-env curl -X POST /v1/services/signal -d '{"name": "devserver", "signal": "TERM"}'
```

## Troubleshooting

### Service Won't Start

1. Check command path exists and is executable
2. Verify working directory exists
3. Check dependencies are running (`needs`)

### Service Keeps Restarting

1. Stream logs with `duration=30s`
2. Verify environment variables
3. Test command manually first

### Viewing Logs

```bash
# During creation
sprite-env curl -X PUT '/v1/services/myapp?duration=60s' -d '{...}'

# System logs
journalctl -f
tail -f /var/log/syslog
```
