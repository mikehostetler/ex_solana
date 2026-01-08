defmodule JidoFlame do
  @moduledoc """
  FLAME integration for Jido agents.

  JidoFlame enables Jido agents to spawn child agents on remote FLAME runners
  (e.g., Fly.io machines) while maintaining parent-child hierarchy, signal
  communication, and distributed Erlang connectivity.

  ## Overview

  FLAME (Fleeting Lambda Application for Modular Execution) allows you to
  execute code on ephemeral nodes that run your entire application. JidoFlame
  bridges FLAME with Jido's directive-based architecture, providing:

  - **Remote agent spawning** - Spawn child agents on FLAME runners
  - **Remote function calls** - Execute functions on remote nodes
  - **Parent-child hierarchy** - Track remote children like local ones
  - **Signal communication** - `emit_to_parent/3` works across nodes

  ## Quick Start

  Add JidoFlame to your supervision tree alongside a FLAME pool:

      children = [
        {Jido, name: MyApp.Jido},
        {FLAME.Pool,
         name: MyApp.FlamePool,
         backend: FLAME.LocalBackend,
         min: 0,
         max: 10}
      ]

  Use the skill in your agent:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          skills: [JidoFlame.Skill]

        def cmd(agent, %{type: "work.distribute"} = signal) do
          directive = JidoFlame.Directive.spawn_remote_agent(
            MyApp.FlamePool,
            WorkerAgent,
            :worker_1,
            meta: %{task: signal.data}
          )
          {agent, [directive]}
        end
      end

  ## Configuration

      # config/config.exs
      config :jido_flame,
        default_pool: MyApp.FlamePool

      # config/runtime.exs
      config :flame,
        backend: FLAME.LocalBackend  # or FLAME.FlyBackend for production

  ## Directives

  JidoFlame provides these directives:

  - `JidoFlame.Directive.RemoteCall` - Execute a function on a remote runner
  - `JidoFlame.Directive.RemoteCast` - Fire-and-forget remote execution
  - `JidoFlame.Directive.SpawnRemoteAgent` - Spawn a child agent remotely
  - `JidoFlame.Directive.PlaceRemoteChild` - Place any child process remotely
  - `JidoFlame.Directive.StopRemoteAgent` - Stop a remote child agent
  """

  @doc """
  Returns a child_spec for a named FLAME pool.

  ## Options

  All options are passed to `FLAME.Pool`:

  - `:name` - Pool name (required)
  - `:backend` - FLAME backend module (default: from config)
  - `:min` - Minimum runners (default: 0)
  - `:max` - Maximum runners (default: 10)
  - `:max_concurrency` - Concurrent tasks per runner (default: 5)
  - `:idle_shutdown_after` - Idle timeout in ms (default: 30_000)

  ## Examples

      JidoFlame.pool_child_spec(
        name: MyApp.FlamePool,
        min: 0,
        max: 10,
        max_concurrency: 5
      )
  """
  @spec pool_child_spec(keyword()) :: {module(), keyword()}
  def pool_child_spec(opts) do
    {FLAME.Pool, opts}
  end

  @doc """
  Returns the default FLAME pool name from configuration.

  Falls back to checking application config for `:jido_flame, :default_pool`.
  """
  @spec default_pool() :: atom() | nil
  def default_pool do
    Application.get_env(:jido_flame, :default_pool)
  end

  @doc """
  Checks if the current node is running as a FLAME runner.

  Use this to conditionally start services:

      if JidoFlame.flame_runner?() do
        # Lean stack for FLAME runners
        []
      else
        # Full stack for main nodes
        [{Phoenix.Endpoint, ...}]
      end
  """
  @spec flame_runner?() :: boolean()
  def flame_runner? do
    FLAME.Parent.get() != nil
  end

  @doc """
  Returns the parent info if running as a FLAME runner.

  Returns `nil` if this is not a FLAME runner node.
  """
  @spec flame_parent() :: map() | nil
  def flame_parent do
    FLAME.Parent.get()
  end
end
