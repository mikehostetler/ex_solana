defmodule Jido.Supervisor do
  @moduledoc """
  Core supervision tree for the Jido runtime.

  This module provides programmatic access to the Jido supervision tree,
  which is started automatically by `Jido.Application`. The tree consists of:

  ## Supervision Tree

  ```
  Jido.Supervisor (one_for_one)
  ├── Jido.Telemetry          - Telemetry handler for metrics
  ├── Jido.TaskSupervisor     - Shared pool for async directive work
  ├── Jido.Registry           - Unique registry for agent lookup by ID
  └── Jido.AgentSupervisor    - DynamicSupervisor for all agent instances
  ```

  ## Process Counts

  | Agents | Total Processes | Memory  |
  |--------|-----------------|---------|
  | 1      | ~5              | ~400 KB |
  | 100    | ~105            | ~10 MB  |
  | 1,000  | ~1,005          | ~100 MB |
  | 10,000 | ~10,005         | ~1 GB   |

  ## Usage

      # Start an agent under the supervisor
      {:ok, pid} = Jido.Supervisor.start_agent(MyAgent, id: "agent-1")

      # Stop an agent
      :ok = Jido.Supervisor.stop_agent("agent-1")

      # List all running agents
      agents = Jido.Supervisor.list_agents()
  """

  @doc """
  Starts an agent under `Jido.AgentSupervisor`.

  ## Options

  - `:id` - Unique identifier for the agent (auto-generated if not provided)
  - `:initial_state` - Initial state map for the agent
  - `:default_dispatch` - Default dispatch config for Emit directives
  - `:error_policy` - Error handling policy (`:log_only`, `:stop_on_error`, etc.)
  - `:max_queue_size` - Maximum directive queue size (default: 10_000)
  - `:parent` - Parent reference for hierarchical agents

  ## Examples

      {:ok, pid} = Jido.Supervisor.start_agent(MyAgent)
      {:ok, pid} = Jido.Supervisor.start_agent(MyAgent, id: "my-agent", initial_state: %{count: 0})
  """
  @spec start_agent(module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent, opts \\ []) do
    child_spec = {Jido.AgentServer, [{:agent, agent} | opts]}
    DynamicSupervisor.start_child(Jido.AgentSupervisor, child_spec)
  end

  @doc """
  Stops an agent by its ID or PID.

  ## Examples

      :ok = Jido.Supervisor.stop_agent("agent-1")
      :ok = Jido.Supervisor.stop_agent(pid)
  """
  @spec stop_agent(String.t() | pid()) :: :ok | {:error, :not_found}
  def stop_agent(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(Jido.AgentSupervisor, pid)
  end

  def stop_agent(id) when is_binary(id) do
    case whereis(id) do
      nil -> {:error, :not_found}
      pid -> stop_agent(pid)
    end
  end

  @doc """
  Looks up an agent by its ID.

  ## Examples

      pid = Jido.Supervisor.whereis("agent-1")
  """
  @spec whereis(String.t()) :: pid() | nil
  def whereis(id) when is_binary(id) do
    case Registry.lookup(Jido.Registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Lists all running agent processes.

  Returns a list of `{id, pid}` tuples.

  ## Examples

      agents = Jido.Supervisor.list_agents()
      # => [{"agent-1", #PID<0.123.0>}, {"agent-2", #PID<0.456.0>}]
  """
  @spec list_agents() :: [{String.t(), pid()}]
  def list_agents do
    Registry.select(Jido.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Returns the count of running agents.
  """
  @spec agent_count() :: non_neg_integer()
  def agent_count do
    DynamicSupervisor.count_children(Jido.AgentSupervisor)
    |> Map.get(:active, 0)
  end

  @doc """
  Returns the TaskSupervisor for async work.

  Use this for offloading heavy IO operations (LLM calls, HTTP requests, etc.)
  that should not block the agent process.

  ## Examples

      Task.Supervisor.start_child(Jido.Supervisor.task_supervisor(), fn ->
        # Heavy IO work
      end)
  """
  @spec task_supervisor() :: atom()
  def task_supervisor, do: Jido.TaskSupervisor
end
