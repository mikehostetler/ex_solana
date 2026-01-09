# Elixir SDK Reference

The Sprites Elixir SDK provides an idiomatic interface for managing Sprites programmatically.

## Installation

```elixir
# mix.exs
defp deps do
  [{:sprites, github: "superfly/sprites-ex"}]
end
```

**Requirements:** Elixir 1.15+, OTP 27+

## Authentication

```elixir
# From environment variable
client = Sprites.new(System.get_env("SPRITE_TOKEN"))

# With options
client = Sprites.new(token,
  base_url: "https://api.sprites.dev",
  timeout: 30_000
)
```

## Sprite Management

### Create

```elixir
{:ok, sprite} = Sprites.create(client, "my-sprite")
```

### Get Handle

```elixir
# Handle only (doesn't verify existence)
sprite = Sprites.sprite(client, "my-sprite")

# Get and verify
{:ok, info} = Sprites.get_sprite(client, "my-sprite")
IO.puts(info["url"])
```

### List

```elixir
{:ok, sprites} = Sprites.list(client)
{:ok, dev_sprites} = Sprites.list(client, prefix: "dev-")
```

### Destroy

```elixir
:ok = Sprites.destroy(sprite)
```

## Command Execution

### `cmd/4` - Synchronous (System.cmd-style)

Blocks until completion. Returns `{output, exit_code}`.

```elixir
{output, exit_code} = Sprites.cmd(sprite, "echo", ["hello"])

# With options
{output, 0} = Sprites.cmd(sprite, "npm", ["test"],
  dir: "/home/sprite/project",
  env: [{"NODE_ENV", "test"}],
  timeout: 60_000,
  stderr_to_stdout: true
)
```

### `spawn/4` - Async (Port-like Messages)

Returns immediately, sends messages to owner process.

```elixir
{:ok, cmd} = Sprites.spawn(sprite, "npm", ["run", "dev"])

receive do
  {:stdout, %{ref: ref}, data} when ref == cmd.ref -> IO.write(data)
  {:stderr, %{ref: ref}, data} when ref == cmd.ref -> IO.write(:stderr, data)
  {:exit, %{ref: ref}, code} when ref == cmd.ref -> IO.puts("Exit: #{code}")
  {:error, %{ref: ref}, reason} when ref == cmd.ref -> IO.inspect(reason)
end
```

**Message Types:**

| Message | Description |
|---------|-------------|
| `{:stdout, %{ref: ref}, data}` | Stdout data |
| `{:stderr, %{ref: ref}, data}` | Stderr data |
| `{:exit, %{ref: ref}, exit_code}` | Command completed |
| `{:error, %{ref: ref}, reason}` | Error occurred |
| `{:port, %{ref: ref}, port}` | Port assignment (TTY) |

### `stream/4` - Lazy Stream

Returns `Enumerable` that lazily emits output.

```elixir
sprite
|> Sprites.stream("tail", ["-f", "/var/log/app.log"])
|> Stream.filter(&String.contains?(&1, "ERROR"))
|> Stream.each(&Logger.error/1)
|> Stream.run()
```

## Command Options

**Common options:**
```elixir
[
  env: [{"KEY", "value"}],   # Environment variables
  dir: "/path/to/workdir",   # Working directory
  tty: true,                 # Allocate TTY
  tty_rows: 24,              # TTY height
  tty_cols: 80               # TTY width
]
```

**cmd/4 specific:**
```elixir
[
  timeout: 30_000,           # Timeout in ms
  stderr_to_stdout: false    # Merge stderr
]
```

**spawn/4 specific:**
```elixir
[
  owner: self(),             # Message recipient
  detachable: false,         # Create detachable session
  session_id: "id"           # Attach to session
]
```

## Working with stdin

```elixir
{:ok, cmd} = Sprites.spawn(sprite, "cat", [])
:ok = Sprites.write(cmd, "Hello\n")
:ok = Sprites.write(cmd, "World\n")
:ok = Sprites.close_stdin(cmd)
{:ok, 0} = Sprites.await(cmd)
```

## TTY Mode

```elixir
{:ok, cmd} = Sprites.spawn(sprite, "bash", ["-i"],
  tty: true,
  tty_rows: 24,
  tty_cols: 80
)

Sprites.write(cmd, "ls -la\n")
Sprites.resize(cmd, 40, 120)
```

## Detachable Sessions

Sessions that persist after disconnecting:

```elixir
# Create
{:ok, cmd} = Sprites.spawn(sprite, "npm", ["run", "dev"], detachable: true)

# List
{:ok, sessions} = Sprites.list_sessions(sprite)

# Attach
{:ok, cmd} = Sprites.attach_session(sprite, session.id)
```

## Port Forwarding

```elixir
# Single port
{:ok, session} = Sprites.proxy_port(sprite, 3000, 3000)

# Multiple ports
mappings = [
  %Sprites.Proxy.PortMapping{local_port: 3000, remote_port: 3000},
  %Sprites.Proxy.PortMapping{local_port: 8080, remote_port: 80}
]
{:ok, sessions} = Sprites.proxy_ports(sprite, mappings)

# Stop
Sprites.Proxy.Session.stop(session)
```

## Network Policy

```elixir
# Get policy
{:ok, policy} = Sprites.get_network_policy(sprite)

# Update policy
policy = %Sprites.Policy{
  rules: [
    %Sprites.Policy.Rule{domain: "api.github.com", action: "allow"},
    %Sprites.Policy.Rule{domain: "blocked.com", action: "deny"}
  ]
}
:ok = Sprites.update_network_policy(sprite, policy)
```

## Checkpoints

```elixir
# List
{:ok, checkpoints} = Sprites.list_checkpoints(sprite)

# Get
{:ok, checkpoint} = Sprites.get_checkpoint(sprite, "v1")

# Create (streams progress)
{:ok, messages} = Sprites.create_checkpoint(sprite, comment: "Before deploy")

# Restore
{:ok, messages} = Sprites.restore_checkpoint(sprite, "v1")
```

## Error Handling

```elixir
case Sprites.create(client, "my-sprite") do
  {:ok, sprite} ->
    # Success

  {:error, {:api_error, status, body}} ->
    IO.puts("API error #{status}")

  {:error, {:not_found, _}} ->
    IO.puts("Not found")

  {:error, reason} ->
    IO.inspect(reason)
end
```

**Error Types:**

| Error | Description |
|-------|-------------|
| `{:error, {:api_error, status, body}}` | API error |
| `{:error, {:not_found, body}}` | 404 not found |
| `{:error, {:invalid_policy, body}}` | Invalid network policy |
| `{:error, :timeout}` | Operation timed out |

## Complete Example

```elixir
defmodule CIRunner do
  require Logger

  def run do
    client = Sprites.new(System.get_env("SPRITE_TOKEN"))
    {:ok, sprite} = Sprites.create(client, "ci-runner")

    try do
      # Clone repo
      {_, 0} = Sprites.cmd(sprite, "git", [
        "clone", "https://github.com/user/repo.git", "/home/sprite/repo"
      ])

      # Install deps
      {_, 0} = Sprites.cmd(sprite, "npm", ["install"], dir: "/home/sprite/repo")

      # Run tests with streaming
      {:ok, cmd} = Sprites.spawn(sprite, "npm", ["test"], dir: "/home/sprite/repo")
      stream_output(cmd)
    after
      Sprites.destroy(sprite)
    end
  end

  defp stream_output(cmd) do
    ref = cmd.ref
    receive do
      {:stdout, %{ref: ^ref}, data} -> IO.write(data); stream_output(cmd)
      {:stderr, %{ref: ^ref}, data} -> IO.write(:stderr, data); stream_output(cmd)
      {:exit, %{ref: ^ref}, code} -> code
      {:error, %{ref: ^ref}, reason} -> Logger.error(inspect(reason)); 1
    end
  end
end
```
