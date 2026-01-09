# Networking

HTTP access, URLs, port forwarding, and network configuration.

## Sprite URLs

Every Sprite has a unique HTTPS URL:

```
https://my-sprite-abc123.sprites.app
```

If code is listening on a port, the URL routes traffic to it.

### URL Authentication

```bash
# Make public (no auth)
sprite url update --auth public

# Require auth (default)
sprite url update --auth default
```

```elixir
Sprites.update_url_settings(sprite, %{auth: "public"})
```

## Port Forwarding

Forward local ports to your Sprite - makes remote services feel local.

### CLI

```bash
# Single port
sprite proxy 3000

# Multiple ports
sprite proxy 3000 8080 5432

# Access locally
curl http://localhost:3000
```

### Elixir

```elixir
# Single port
{:ok, session} = Sprites.proxy_port(sprite, 3000, 3000)

# Multiple ports
mappings = [
  %Sprites.Proxy.PortMapping{local_port: 3000, remote_port: 3000},
  %Sprites.Proxy.PortMapping{local_port: 8080, remote_port: 80},
  %Sprites.Proxy.PortMapping{local_port: 5432, remote_port: 5432}
]
{:ok, sessions} = Sprites.proxy_ports(sprite, mappings)

# Stop proxy
Sprites.Proxy.Session.stop(session)
```

## Network Behavior

| Direction | Access |
|-----------|--------|
| Outbound | Full access - all protocols/ports |
| Inbound | Only via Sprite URL or port forwarding |
| DNS | Standard resolution |

The environment includes common network tools: `curl`, `wget`, `netcat`, etc.

## Common Patterns

### Web Server

```bash
# Start server
sprite exec -detachable "python -m http.server 8080"

# Get URL
sprite url
# https://my-sprite-abc123.sprites.app

# Make public and access
sprite url update --auth public
curl https://my-sprite-abc123.sprites.app:8080/
```

### Development Server

```bash
# Start dev server
sprite exec -detachable "cd /home/sprite/app && npm run dev"

# Forward port locally
sprite proxy 3000

# Access
open http://localhost:3000
```

### Database Access

```bash
# Start PostgreSQL
sprite exec -detachable "pg_ctl start"

# Forward port
sprite proxy 5432

# Connect locally
psql -h localhost -p 5432 -U postgres
```

### Multiple Services

```bash
# Start services
sprite exec -detachable "cd /api && npm start"      # 3000
sprite exec -detachable "cd /worker && npm start"   # 3001
sprite exec -detachable "redis-server"              # 6379

# Forward all
sprite proxy 3000 3001 6379
```

## Port Notifications

Get notified when ports open:

```elixir
{:ok, cmd} = Sprites.spawn(sprite, "npm", ["run", "dev"])

receive do
  {:port_opened, ^cmd, %{port: port, address: addr, pid: pid}} ->
    IO.puts("Port #{port} opened on #{addr} by PID #{pid}")
end
```

## Security Notes

- **Default:** Sprite URLs are private (require token)
- **Forwarded ports:** Reachable from your machine only, not the Internet
- **Make public only when needed:** For demos, webhooks, etc.
- **Implement app-level auth:** For production use cases

## Troubleshooting

| Problem | Solution |
|---------|----------|
| App not visible on URL | Listen on `0.0.0.0`, not `localhost` |
| Forwarded port not responding | Check app is running, correct port |
| 403 on Sprite URL | Make public or authenticate |
| Dynamic app not ready | Use port open events to wait |
