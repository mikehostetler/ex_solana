defmodule JidoFlame.Actions.SpawnRemoteAgent do
  @moduledoc """
  Action to spawn a child Jido agent on a remote FLAME runner.

  The spawned agent is tracked in the parent's children map with `remote?: true`
  metadata and managed via the Owner pattern for reliable lifecycle handling.

  ## Examples

      params = %{
        pool: MyApp.FlamePool,
        agent: MyApp.WorkerAgent,
        tag: :worker_1,
        opts: %{initial_state: %{}},
        meta: %{purpose: "data processing"}
      }
  """

  use Jido.Action,
    name: "jido_flame_spawn_remote_agent",
    description: "Spawn a child agent on a remote FLAME runner",
    category: "flame",
    tags: ["flame", "remote", "agent", "spawn"],
    vsn: "1.0.0",
    schema: [
      pool: [type: :atom, required: true, doc: "FLAME pool name"],
      agent: [type: :any, required: true, doc: "Agent module or pre-built struct"],
      tag: [type: :any, required: true, doc: "Tracking tag in children map"],
      opts: [type: :map, default: %{}, doc: "Options passed to AgentServer"],
      meta: [type: :map, default: %{}, doc: "Metadata passed via ParentRef"],
      jido: [type: :atom, doc: "Jido instance name on remote node (optional)"],
      flame_opts: [type: :keyword_list, default: [], doc: "Options for FLAME.place_child/3"]
    ]

  alias JidoFlame.Directive.SpawnRemoteAgent

  @impl true
  def run(params, _context) do
    directive_attrs = %{
      pool: params.pool,
      agent: params.agent,
      tag: params.tag,
      opts: params[:opts] || %{},
      meta: params[:meta] || %{},
      jido: params[:jido],
      flame_opts: params[:flame_opts] || []
    }

    case SpawnRemoteAgent.new(directive_attrs) do
      {:ok, directive} ->
        {:ok,
         %{
           directive_type: :spawn_remote_agent,
           pool: params.pool,
           agent: params.agent,
           tag: params.tag
         }, [directive]}

      {:error, error} ->
        {:error, error}
    end
  end
end
