defmodule JidoFlame.Skill do
  require JidoFlame.Actions.SpawnRemoteAgent
  require JidoFlame.Actions.RemoteCall
  require JidoFlame.Actions.RemoteCast
  require JidoFlame.Actions.StopRemoteAgent

  @moduledoc """
  Skill providing FLAME remote execution capabilities.

  Add this skill to your agent for easy access to FLAME actions:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          skills: [JidoFlame.Skill]
      end

  ## Actions Provided

  - `jido.flame.remote.agent.spawn` - Spawn child agent on remote runner
  - `jido.flame.remote.call` - Execute function on remote runner
  - `jido.flame.remote.cast` - Fire-and-forget remote execution
  - `jido.flame.remote.agent.stop` - Stop remote child agent

  ## State

  The skill adds a `:flame` key to agent state with:

  - `default_pool` - Default FLAME pool to use when not specified

  ## Configuration

  Configure the default pool in your agent:

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          skills: [{JidoFlame.Skill, default_pool: MyApp.FlamePool}]
      end

  Or globally in config:

      config :jido_flame, default_pool: MyApp.FlamePool

  ## Signal Routing

  The skill routes these signal patterns to actions:

  - `jido.flame.remote.agent.spawn` → `SpawnRemoteAgent`
  - `jido.flame.remote.call` → `RemoteCall`
  - `jido.flame.remote.cast` → `RemoteCast`
  - `jido.flame.remote.agent.stop` → `StopRemoteAgent`
  """

  use Jido.Skill,
    name: "flame",
    description: "FLAME remote execution capabilities for Jido agents",
    category: "infrastructure",
    tags: ["flame", "remote", "distributed", "fly.io"],
    vsn: "0.1.0",
    state_key: :flame,
    actions: [
      JidoFlame.Actions.SpawnRemoteAgent,
      JidoFlame.Actions.RemoteCall,
      JidoFlame.Actions.RemoteCast,
      JidoFlame.Actions.StopRemoteAgent
    ],
    schema: [
      default_pool: [
        type: :atom,
        doc: "Default FLAME pool name"
      ]
    ],
    signal_patterns: ["jido.flame.**"]

  @impl true
  def mount(_agent, config) do
    default_pool = Map.get(config, :default_pool) || JidoFlame.default_pool()

    {:ok,
     %{
       default_pool: default_pool
     }}
  end

  @impl true
  def router(_agent) do
    [
      {"jido.flame.remote.agent.spawn", JidoFlame.Actions.SpawnRemoteAgent},
      {"jido.flame.remote.call", JidoFlame.Actions.RemoteCall},
      {"jido.flame.remote.cast", JidoFlame.Actions.RemoteCast},
      {"jido.flame.remote.agent.stop", JidoFlame.Actions.StopRemoteAgent}
    ]
  end
end
