defmodule Jido do
  use Supervisor

  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  ## Architecture

  Jido 2.0 uses **instance-scoped supervisors** instead of global singletons. Each Jido instance
  manages its own Registry, TaskSupervisor, and AgentSupervisor, providing complete isolation
  between different parts of your application.

  ## Getting Started

  Add a Jido instance to your application's supervision tree:

      # In your application.ex
      children = [
        {Jido, name: MyApp.Jido}
      ]

  Then use the instance to manage agents:

      # Start an agent
      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "agent-1")

      # Look up an agent by ID
      pid = Jido.whereis(MyApp.Jido, "agent-1")

      # List all agents
      agents = Jido.list_agents(MyApp.Jido)

      # Stop an agent
      :ok = Jido.stop_agent(MyApp.Jido, "agent-1")

  ## Test Isolation

  For tests, use `JidoTest.Case` which automatically creates an isolated Jido instance:

      defmodule MyAgentTest do
        use JidoTest.Case, async: true

        test "my agent works", %{jido: jido} do
          {:ok, pid} = Jido.start_agent(jido, MyAgent)
          # Test in isolation...
        end
      end

  ## Core Concepts

  Jido is built around a purely functional Agent design:

  - **Agent** - An immutable data structure that holds state and can be updated via commands
  - **Actions** - Pure functions that transform agent state
  - **Directives** - Descriptions of external effects (emit signals, spawn processes, etc.)
  - **Strategies** - Pluggable execution patterns for actions

  ## Agent API

  The core operation is `cmd/2`:

      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

  Key invariants:
  - The returned `agent` is always complete — no "apply directives" step needed
  - `directives` are external effects only — they never modify agent state
  - `cmd/2` is a pure function — given same inputs, always same outputs

  ## Defining Agents

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            status: [type: :atom, default: :idle],
            counter: [type: :integer, default: 0]
          ]
      end
  """

  @type agent_id :: String.t() | atom()

  @doc """
  Starts a Jido instance supervisor.

  ## Options
    - `:name` - Required. The name of this Jido instance (e.g., `MyApp.Jido`)

  ## Example

      {:ok, pid} = Jido.start_link(name: MyApp.Jido)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 10_000
    }
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    children = [
      {Task.Supervisor,
       name: task_supervisor_name(name), max_children: Keyword.get(opts, :max_tasks, 1000)},
      {Registry, keys: :unique, name: registry_name(name)},
      {DynamicSupervisor,
       name: agent_supervisor_name(name),
       strategy: :one_for_one,
       max_restarts: 1000,
       max_seconds: 5}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Generate a unique identifier.

  Delegates to `Jido.Util.generate_id/0`.
  """
  defdelegate generate_id(), to: Jido.Util

  @doc "Returns the Registry name for a Jido instance."
  @spec registry_name(atom()) :: atom()
  def registry_name(name), do: Module.concat(name, Registry)

  @doc "Returns the AgentSupervisor name for a Jido instance."
  @spec agent_supervisor_name(atom()) :: atom()
  def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

  @doc "Returns the TaskSupervisor name for a Jido instance."
  @spec task_supervisor_name(atom()) :: atom()
  def task_supervisor_name(name), do: Module.concat(name, TaskSupervisor)

  @doc "Returns the Scheduler name for a Jido instance."
  @spec scheduler_name(atom()) :: atom()
  def scheduler_name(name), do: Module.concat(name, Scheduler)

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts an agent under a specific Jido instance.

  ## Examples

      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent)
      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "custom-id")
  """
  @spec start_agent(atom(), module() | struct(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(jido_instance, agent, opts \\ []) when is_atom(jido_instance) do
    child_spec = {Jido.AgentServer, Keyword.merge(opts, agent: agent, jido: jido_instance)}
    DynamicSupervisor.start_child(agent_supervisor_name(jido_instance), child_spec)
  end

  @doc """
  Stops an agent by pid or id.

  ## Examples

      :ok = Jido.stop_agent(MyApp.Jido, pid)
      :ok = Jido.stop_agent(MyApp.Jido, "agent-id")
  """
  @spec stop_agent(atom(), pid() | String.t()) :: :ok | {:error, :not_found}
  def stop_agent(jido_instance, pid) when is_atom(jido_instance) and is_pid(pid) do
    DynamicSupervisor.terminate_child(agent_supervisor_name(jido_instance), pid)
  end

  def stop_agent(jido_instance, id) when is_atom(jido_instance) and is_binary(id) do
    case whereis(jido_instance, id) do
      nil -> {:error, :not_found}
      pid -> stop_agent(jido_instance, pid)
    end
  end

  @doc """
  Looks up an agent by ID in a Jido instance's registry.

  Returns the pid if found, nil otherwise.

  ## Examples

      pid = Jido.whereis(MyApp.Jido, "agent-123")
  """
  @spec whereis(atom(), String.t()) :: pid() | nil
  def whereis(jido_instance, id) when is_atom(jido_instance) and is_binary(id) do
    case Registry.lookup(registry_name(jido_instance), id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Lists all agents running in a Jido instance.

  Returns a list of `{id, pid}` tuples.

  ## Examples

      agents = Jido.list_agents(MyApp.Jido)
      # => [{"agent-1", #PID<0.123.0>}, {"agent-2", #PID<0.124.0>}]
  """
  @spec list_agents(atom()) :: [{String.t(), pid()}]
  def list_agents(jido_instance) when is_atom(jido_instance) do
    registry_name(jido_instance)
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Returns the count of running agents in a Jido instance.

  ## Examples

      count = Jido.agent_count(MyApp.Jido)
      # => 5
  """
  @spec agent_count(atom()) :: non_neg_integer()
  def agent_count(jido_instance) when is_atom(jido_instance) do
    agent_supervisor_name(jido_instance)
    |> DynamicSupervisor.count_children()
    |> Map.get(:active, 0)
  end

  # ---------------------------------------------------------------------------
  # Discovery
  # ---------------------------------------------------------------------------

  @doc "Lists discovered Actions with optional filtering."
  defdelegate list_actions(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Sensors with optional filtering."
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Skills with optional filtering."
  defdelegate list_skills(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered Demos with optional filtering."
  defdelegate list_demos(opts \\ []), to: Jido.Discovery

  @doc "Gets an Action by its slug."
  defdelegate get_action_by_slug(slug), to: Jido.Discovery

  @doc "Gets a Sensor by its slug."
  defdelegate get_sensor_by_slug(slug), to: Jido.Discovery

  @doc "Gets a Skill by its slug."
  defdelegate get_skill_by_slug(slug), to: Jido.Discovery

  @doc "Refreshes the Discovery catalog."
  defdelegate refresh_discovery(), to: Jido.Discovery, as: :refresh

  # ---------------------------------------------------------------------------
  # Agent Coordination
  # ---------------------------------------------------------------------------

  @doc """
  Wait for an agent to reach a terminal status.

  See `Jido.Await.completion/3` for details.
  """
  defdelegate await(server, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :completion

  @doc """
  Wait for a child agent to reach a terminal status.

  See `Jido.Await.child/4` for details.
  """
  defdelegate await_child(server, child_tag, timeout_ms \\ 30_000, opts \\ []),
    to: Jido.Await,
    as: :child

  @doc """
  Wait for all agents to reach terminal status.

  See `Jido.Await.all/3` for details.
  """
  defdelegate await_all(servers, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :all

  @doc """
  Wait for any agent to reach terminal status.

  See `Jido.Await.any/3` for details.
  """
  defdelegate await_any(servers, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.Await,
    as: :any

  @doc """
  Get the PIDs of all children of a parent agent.

  See `Jido.Await.get_children/1` for details.
  """
  defdelegate get_children(parent_server), to: Jido.Await

  @doc """
  Get a specific child's PID by tag.

  See `Jido.Await.get_child/2` for details.
  """
  defdelegate get_child(parent_server, child_tag), to: Jido.Await

  @doc """
  Check if an agent process is alive and responding.

  See `Jido.Await.alive?/1` for details.
  """
  defdelegate alive?(server), to: Jido.Await

  @doc """
  Request graceful cancellation of an agent.

  See `Jido.Await.cancel/2` for details.
  """
  defdelegate cancel(server, opts \\ []), to: Jido.Await
end
