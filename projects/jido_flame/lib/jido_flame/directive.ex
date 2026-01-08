defmodule JidoFlame.Directive do
  @moduledoc """
  FLAME-specific directives for remote execution.

  These directives extend Jido's directive system to support FLAME operations:

  - `RemoteCall` - Synchronous remote function execution
  - `RemoteCast` - Asynchronous remote function execution
  - `SpawnRemoteAgent` - Spawn a child agent on a remote runner
  - `PlaceRemoteChild` - Place any child process on a remote runner
  - `StopRemoteAgent` - Stop a tracked remote child agent

  ## Usage

  Directives are returned from agent `cmd/2` functions:

      def cmd(agent, signal) do
        directive = JidoFlame.Directive.spawn_remote_agent(
          MyApp.FlamePool,
          WorkerAgent,
          :worker_1
        )
        {agent, [directive]}
      end

  The runtime (AgentServer) executes these directives via `JidoFlame.DirectiveExec`.
  """

  alias __MODULE__.{RemoteCall, RemoteCast, SpawnRemoteAgent, PlaceRemoteChild, StopRemoteAgent}

  @type t ::
          RemoteCall.t()
          | RemoteCast.t()
          | SpawnRemoteAgent.t()
          | PlaceRemoteChild.t()
          | StopRemoteAgent.t()

  # ===========================================================================
  # Helper Constructors
  # ===========================================================================

  @doc """
  Creates a RemoteCall directive.

  ## Examples

      JidoFlame.Directive.remote_call(MyPool, fn -> expensive_work() end)
      JidoFlame.Directive.remote_call(MyPool, fn -> work() end,
        result_type: "work.completed",
        tag: :batch_1
      )
  """
  @spec remote_call(atom(), (-> term()), keyword()) :: RemoteCall.t()
  def remote_call(pool, fun, opts \\ []) when is_function(fun, 0) do
    %RemoteCall{
      pool: pool,
      fun: fun,
      opts: Keyword.get(opts, :flame_opts, []),
      result_type: Keyword.get(opts, :result_type),
      result_dispatch: Keyword.get(opts, :result_dispatch),
      tag: Keyword.get(opts, :tag)
    }
  end

  @doc """
  Creates a RemoteCast directive (fire-and-forget).

  ## Examples

      JidoFlame.Directive.remote_cast(MyPool, fn -> background_work() end)
  """
  @spec remote_cast(atom(), (-> term()), keyword()) :: RemoteCast.t()
  def remote_cast(pool, fun, opts \\ []) when is_function(fun, 0) do
    %RemoteCast{
      pool: pool,
      fun: fun,
      opts: Keyword.get(opts, :flame_opts, []),
      tag: Keyword.get(opts, :tag)
    }
  end

  @doc """
  Creates a SpawnRemoteAgent directive.

  ## Options

  - `:opts` - Options passed to the child AgentServer
  - `:meta` - Metadata passed via ParentRef
  - `:jido` - Jido instance name on remote node
  - `:flame_opts` - Options for FLAME.place_child/3

  ## Examples

      JidoFlame.Directive.spawn_remote_agent(MyPool, WorkerAgent, :worker_1)
      JidoFlame.Directive.spawn_remote_agent(MyPool, WorkerAgent, :processor,
        opts: %{initial_state: %{batch_size: 100}},
        meta: %{assigned_topic: "events"}
      )
  """
  @spec spawn_remote_agent(atom(), module() | struct(), term(), keyword()) :: SpawnRemoteAgent.t()
  def spawn_remote_agent(pool, agent, tag, opts \\ []) do
    %SpawnRemoteAgent{
      pool: pool,
      agent: agent,
      tag: tag,
      opts: Keyword.get(opts, :opts, %{}),
      meta: Keyword.get(opts, :meta, %{}),
      jido: Keyword.get(opts, :jido),
      flame_opts: Keyword.get(opts, :flame_opts, [])
    }
  end

  @doc """
  Creates a PlaceRemoteChild directive for generic processes.

  ## Examples

      JidoFlame.Directive.place_remote_child(MyPool, {MyWorker, arg: value})
      JidoFlame.Directive.place_remote_child(MyPool, child_spec, track?: true, tag: :worker)
  """
  @spec place_remote_child(atom(), term(), keyword()) :: PlaceRemoteChild.t()
  def place_remote_child(pool, child_spec, opts \\ []) do
    %PlaceRemoteChild{
      pool: pool,
      child_spec: child_spec,
      opts: Keyword.get(opts, :flame_opts, []),
      tag: Keyword.get(opts, :tag),
      track?: Keyword.get(opts, :track?, false)
    }
  end

  @doc """
  Creates a StopRemoteAgent directive.

  ## Examples

      JidoFlame.Directive.stop_remote_agent(:worker_1)
      JidoFlame.Directive.stop_remote_agent(:processor, :shutdown)
  """
  @spec stop_remote_agent(term(), term()) :: StopRemoteAgent.t()
  def stop_remote_agent(tag, reason \\ :normal) do
    %StopRemoteAgent{tag: tag, reason: reason}
  end
end
