# Jido 2.0 API Plan

## Executive Summary

Jido 2.0 adopts mature OTP patterns: **user-owned, instance-scoped supervisors** instead of auto-started global singletons. This enables test isolation, multi-tenancy, and clean Phoenix integration.

```elixir
# application.ex - User owns the Jido instance
children = [
  {Jido, name: MyApp.Jido}
]
```

---

## Core Architecture

### Supervision Tree

```
Jido.ApplicationSupervisor (started by Jido.Application)
└── Jido.Discovery               # Global component catalog (read-only)

MyApp.Jido (Jido - user-owned instance)
├── MyApp.Jido.TaskSupervisor    # Async work
├── MyApp.Jido.Registry          # Agent lookup by ID
├── MyApp.Jido.AgentSupervisor   # DynamicSupervisor for agents
└── MyApp.Jido.Scheduler         # Quantum scheduler for cron jobs
```

All instance child names are **derived from the instance name** — no global atoms except Discovery.

---

## 1. `Jido` — The Instance Supervisor

The `Jido` module is both the supervisor you add to your tree AND the facade for common operations (like Oban, Finch, Phoenix.PubSub).

```elixir
defmodule Jido do
  @moduledoc """
  自動 (Jido) - Autonomous agent systems for Elixir.

  Jido is both a supervisor and a facade. Add it to your supervision tree,
  then use its functions to manage agents.

  ## Setup

      # application.ex
      children = [
        {Jido, name: MyApp.Jido}
      ]

      # config/config.exs (optional - for convenience functions)
      config :jido, default: MyApp.Jido

  ## Usage

      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "agent-1")
      {:ok, pid} = Jido.start_agent(MyAgent)  # uses configured default

  ## Options

  - `:name` - Required. Atom name for this Jido instance
  - `:max_tasks` - Max children for TaskSupervisor (default: 1000)
  - `:scheduler_jobs` - List of Quantum job specs (default: [])
  """

  use Supervisor

  @type name :: atom() | module()

  # ===========================================================================
  # Supervisor
  # ===========================================================================

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

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
       name: task_supervisor_name(name),
       max_children: Keyword.get(opts, :max_tasks, 1000)},
      {Registry, keys: :unique, name: registry_name(name)},
      {DynamicSupervisor,
       name: agent_supervisor_name(name),
       strategy: :one_for_one,
       max_restarts: 1000,
       max_seconds: 5},
      {Jido.Scheduler, name: scheduler_name(name), jobs: Keyword.get(opts, :scheduler_jobs, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # ===========================================================================
  # Name Derivation
  # ===========================================================================

  @doc "Returns the Registry name for a Jido instance."
  def registry_name(name), do: Module.concat(name, Registry)

  @doc "Returns the AgentSupervisor name for a Jido instance."
  def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

  @doc "Returns the TaskSupervisor name for a Jido instance."
  def task_supervisor_name(name), do: Module.concat(name, TaskSupervisor)

  @doc "Returns the Scheduler name for a Jido instance."
  def scheduler_name(name), do: Module.concat(name, Scheduler)
```

---

## 2. `Jido.Application` — Discovery Only

```elixir
defmodule Jido.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Discovery is global — catalogs all components across the BEAM
      Jido.Discovery
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Jido.ApplicationSupervisor)
  end
end
```

**Why:** Discovery is read-only introspection of loaded modules — it makes sense as a global singleton. Everything else (Registry, AgentSupervisor, Scheduler) is instance-scoped.

---

## 3. `Jido` API Functions

The same `Jido` module that serves as the supervisor also provides the facade API. Continuing the module from above:

```elixir
  # ===========================================================================
  # Configuration
  # ===========================================================================

  @doc "Returns the configured default Jido instance."
  def default do
    Application.get_env(:jido, :default) ||
      raise ArgumentError, "Configure :jido, :default or pass instance name explicitly"
  end

  @doc "Returns the TaskSupervisor for a Jido instance."
  def task_supervisor(name), do: task_supervisor_name(name)
  def task_supervisor, do: task_supervisor(default())

  # ===========================================================================
  # Agent Lifecycle
  # ===========================================================================

  @doc """
  Starts an agent under the instance's AgentSupervisor.

  ## Options

  - `:id` - Unique identifier (auto-generated if omitted)
  - `:initial_state` - Initial state map
  - `:parent` - Parent process for lifecycle linking
  - `:on_parent_death` - `:stop` | `:continue` | `:emit_orphan`

  ## Examples

      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "agent-1")
      {:ok, pid} = Jido.start_agent(MyAgent)  # uses configured default
  """
  def start_agent(name, agent, opts) when is_atom(name) do
    child_spec = {Jido.AgentServer, Keyword.merge(opts, agent: agent, jido: name)}
    DynamicSupervisor.start_child(agent_supervisor_name(name), child_spec)
  end

  def start_agent(agent, opts \\ []), do: start_agent(default(), agent, opts)

  @doc "Stops an agent by PID or ID."
  def stop_agent(name, pid) when is_atom(name) and is_pid(pid) do
    DynamicSupervisor.terminate_child(agent_supervisor_name(name), pid)
  end

  def stop_agent(name, id) when is_atom(name) and is_binary(id) do
    case whereis(name, id) do
      nil -> {:error, :not_found}
      pid -> stop_agent(name, pid)
    end
  end

  def stop_agent(id_or_pid), do: stop_agent(default(), id_or_pid)

  @doc "Looks up an agent PID by ID."
  def whereis(name, id) when is_atom(name) and is_binary(id) do
    case Registry.lookup(registry_name(name), id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def whereis(id), do: whereis(default(), id)

  @doc "Lists all running agents as `{id, pid}` tuples."
  def list_agents(name) when is_atom(name) do
    Registry.select(
      registry_name(name),
      [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}]
    )
  end

  def list_agents, do: list_agents(default())

  @doc "Returns the count of running agents."
  def agent_count(name) when is_atom(name) do
    agent_supervisor_name(name)
    |> DynamicSupervisor.count_children()
    |> Map.get(:active, 0)
  end

  def agent_count, do: agent_count(default())

  # ===========================================================================
  # Agent Communication
  # ===========================================================================

  @doc """
  Sends a signal synchronously and waits for processing.

  ## Examples

      {:ok, agent} = Jido.call(pid, signal)
      {:ok, agent} = Jido.call(MyApp.Jido, "agent-id", signal, timeout: 10_000)
  """
  def call(name, server, signal, opts \\ []) when is_atom(name) do
    Jido.AgentServer.call(name, server, signal, opts)
  end

  def call(server, signal, opts \\ []) do
    Jido.AgentServer.call(server, signal, opts)
  end

  @doc "Sends a signal asynchronously (fire-and-forget)."
  def cast(name, server, signal) when is_atom(name) do
    Jido.AgentServer.cast(name, server, signal)
  end

  def cast(server, signal), do: Jido.AgentServer.cast(server, signal)

  @doc "Gets the full state of an agent."
  defdelegate state(server), to: Jido.AgentServer

  @doc "Gets the runtime status of an agent."
  defdelegate status(server), to: Jido.AgentServer

  # ===========================================================================
  # Multi-Agent Coordination
  # ===========================================================================

  @doc "Waits for an agent to reach terminal status (`:completed` or `:failed`)."
  defdelegate await(server, timeout_ms \\ 10_000, opts \\ []),
    to: Jido.MultiAgent, as: :await_completion

  @doc "Waits for a child agent to complete."
  defdelegate await_child(server, child_tag, timeout_ms \\ 30_000, opts \\ []),
    to: Jido.MultiAgent, as: :await_child_completion

  # ===========================================================================
  # Scheduler
  # ===========================================================================

  @doc "Returns the Scheduler name for a Jido instance."
  def scheduler(name), do: scheduler_name(name)
  def scheduler, do: scheduler(default())

  # ===========================================================================
  # Discovery (global)
  # ===========================================================================

  @doc "Lists discovered actions."
  defdelegate list_actions(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered agents."
  defdelegate list_discovered_agents(opts \\ []), to: Jido.Discovery, as: :list_agents

  @doc "Lists discovered sensors."
  defdelegate list_sensors(opts \\ []), to: Jido.Discovery

  @doc "Lists discovered skills."
  defdelegate list_skills(opts \\ []), to: Jido.Discovery

  # ===========================================================================
  # Utilities
  # ===========================================================================

  @doc "Generates a unique identifier."
  defdelegate generate_id(), to: Jido.Util
end
```

---

## 4. Agent Spawning Patterns

### 4.1 Singleton Agents in Supervision Trees

For long-lived, named agents that should always be running:

```elixir
defmodule MyApp.AgentsSupervisor do
  use Supervisor

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    children = [
      # Singleton agent with deterministic ID
      {Jido.AgentServer,
       agent: MyApp.PlannerAgent,
       id: "planner",
       jido: MyApp.Jido}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

# Access it anywhere:
pid = Jido.whereis(MyApp.Jido, "planner")
```

### 4.2 Dynamic Per-Request Agents

For short-lived agents spawned on demand:

```elixir
def handle_request(conn, params) do
  {:ok, pid} = Jido.start_agent(MyApp.Jido, MyApp.RequestAgent, [])
  
  signal = MyApp.Signals.process_request(params)
  {:ok, _agent} = Jido.call(pid, signal, timeout: 30_000)
  
  {:ok, state} = Jido.state(pid)
  :ok = Jido.stop_agent(MyApp.Jido, pid)
  
  json(conn, state.agent.state.result)
end
```

### 4.3 `Jido.AgentPool` — Reusable Agent Pools

For expensive-to-start agents that can handle multiple requests:

```elixir
defmodule Jido.AgentPool do
  @moduledoc """
  Fixed-size pool of long-lived agents.

  Use when agents are expensive to start (LLM context, loaded models)
  but can handle many independent tasks over their lifetime.

  ## Usage

      # Supervision tree
      children = [
        {Jido, name: MyApp.Jido},
        {Jido.AgentPool,
         name: MyApp.LLMPool,
         jido: MyApp.Jido,
         agent: MyApp.LLMAgent,
         size: 10}
      ]

      # Usage
      Jido.AgentPool.with_agent(MyApp.LLMPool, fn pid ->
        Jido.call(pid, my_signal)
      end)
  """

  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.fetch!(opts, :name),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl true
  def init(opts) do
    jido = Keyword.fetch!(opts, :jido)
    agent = Keyword.fetch!(opts, :agent)
    size = Keyword.get(opts, :size, 5)
    strategy = Keyword.get(opts, :strategy, :round_robin)

    pids =
      for i <- 1..size do
        {:ok, pid} = Jido.start_agent(jido, agent, id: "pool_#{i}_#{System.unique_integer()}")
        pid
      end

    {:ok, %{pids: pids, idx: 0, strategy: strategy}}
  end

  @doc "Get next available agent from pool."
  def checkout(pool), do: GenServer.call(pool, :checkout)

  @doc "Execute function with pooled agent."
  def with_agent(pool, fun) do
    {:ok, pid} = checkout(pool)
    fun.(pid)
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    idx = rem(state.idx, length(state.pids))
    pid = Enum.at(state.pids, idx)
    {:reply, {:ok, pid}, %{state | idx: idx + 1}}
  end
end
```

### 4.4 Dynamic Per-User/Session Agents

For agents tied to user sessions with automatic cleanup:

```elixir
# Spawn with parent-death semantics
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyApp.SessionAgent,
  id: "session:#{user_id}",
  parent: self(),              # Link to current process
  on_parent_death: :stop       # Auto-cleanup when parent dies
)
```

---

## 5. Phoenix Integration Patterns

### 5.1 LiveView — Agent Per User Session

```elixir
defmodule MyAppWeb.DashboardLive do
  use Phoenix.LiveView

  @runtime MyApp.Jido

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      user_id = session["user_id"]
      agent_id = "dashboard:#{user_id}"

      {:ok, pid} = Jido.start_agent(@runtime, MyApp.DashboardAgent,
        id: agent_id,
        initial_state: %{user_id: user_id},
        parent: self(),
        on_parent_death: :stop
      )

      {:ok, assign(socket, agent_pid: pid, agent_id: agent_id)}
    else
      {:ok, assign(socket, agent_pid: nil, agent_id: nil)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    signal = MyApp.Signals.refresh_dashboard()
    {:ok, _agent} = Jido.call(socket.assigns.agent_pid, signal)
    {:noreply, socket}
  end

  # Agent auto-stops when LiveView process terminates
end
```

### 5.2 Channels — Agent Per Socket

```elixir
defmodule MyAppWeb.RoomChannel do
  use Phoenix.Channel

  @runtime MyApp.Jido

  def join("room:" <> room_id, _payload, socket) do
    agent_id = "room:#{room_id}:#{socket.assigns.user_id}"

    {:ok, pid} = Jido.start_agent(@runtime, MyApp.RoomAgent,
      id: agent_id,
      initial_state: %{room_id: room_id},
      parent: self(),
      on_parent_death: :stop
    )

    {:ok, assign(socket, agent_pid: pid)}
  end

  def handle_in("message", payload, socket) do
    signal = MyApp.Signals.chat_message(payload)
    :ok = Jido.cast(socket.assigns.agent_pid, signal)
    {:noreply, socket}
  end

  # Agent auto-stops when channel process terminates
end
```

### 5.3 PubSub Event Consumer

```elixir
defmodule MyApp.WorkflowConsumer do
  use GenServer

  @runtime MyApp.Jido

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "workflows")
    {:ok, %{}}
  end

  @impl true
  def handle_info(%{event: "workflow.start", payload: payload}, state) do
    {:ok, pid} = Jido.start_agent(@runtime, MyApp.WorkflowAgent,
      id: "workflow:#{payload.id}",
      initial_state: payload
    )

    # Agent runs independently; no parent linking
    {:noreply, Map.put(state, payload.id, pid)}
  end
end
```

### 5.4 Shared Agent Pool for HTTP Requests

```elixir
# application.ex
children = [
  {Jido, name: MyApp.Jido},
  {Jido.AgentPool,
   name: MyApp.RequestPool,
   jido: MyApp.Jido,
   agent: MyApp.RequestAgent,
   size: 20}
]

# Controller
def create(conn, params) do
  result = Jido.AgentPool.with_agent(MyApp.RequestPool, fn pid ->
    signal = MyApp.Signals.process_order(params)
    {:ok, agent} = Jido.call(pid, signal, timeout: 30_000)
    agent.state.result
  end)

  json(conn, result)
end
```

---

## 6. Testing Patterns

### 6.1 Isolated Jido Instance Per Test (Recommended)

```elixir
defmodule MyAgentTest do
  use ExUnit.Case, async: true

  setup do
    # Unique Jido instance per test — fully isolated
    jido = :"test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({Jido, name: jido})
    %{jido: jido}
  end

  test "agent lifecycle", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, MyAgent, id: "test-agent")
    
    assert is_pid(pid)
    assert Jido.whereis(jido, "test-agent") == pid
    
    :ok = Jido.stop_agent(jido, pid)
    assert Jido.whereis(jido, "test-agent") == nil
  end

  test "agent processes signal", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, CounterAgent, initial_state: %{count: 0})
    
    signal = CounterSignals.increment(5)
    {:ok, agent} = Jido.call(pid, signal)
    
    assert agent.state.count == 5
  end
end
```

### 6.2 Test Helper Module

```elixir
defmodule Jido.TestHelpers do
  @moduledoc "Test utilities for Jido."

  import ExUnit.Callbacks, only: [start_supervised: 1]

  @doc "Starts an isolated Jido instance for the test."
  def start_test_jido(context \\ %{}) do
    jido = :"test_jido_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({Jido, name: jido})
    Map.put(context, :jido, jido)
  end

  @doc "Starts a test Jido instance and agent."
  def start_test_agent(agent_module, opts \\ []) do
    jido = :"test_jido_#{System.unique_integer([:positive])}"
    {:ok, _} = start_supervised({Jido, name: jido})
    {:ok, pid} = Jido.start_agent(jido, agent_module, opts)
    %{jido: jido, agent_pid: pid}
  end
end
```

### 6.3 Per-Module Jido Instance (Faster for Heavy Suites)

```elixir
defmodule MyIntegrationTest do
  use ExUnit.Case, async: false

  @jido __MODULE__.Jido

  setup_all do
    {:ok, _} = start_supervised({Jido, name: @jido})
    :ok
  end

  test "complex workflow" do
    {:ok, pid} = Jido.start_agent(@jido, WorkflowAgent, [])
    # ...
  end
end
```

---

## 7. Discovery — Global Component Catalog

Discovery is a **global singleton** started by `Jido.Application`. It catalogs all Actions, Agents, Sensors, and Skills loaded in the BEAM for introspection.

```elixir
defmodule Jido.Discovery do
  @moduledoc """
  Global catalog of Jido components (Actions, Agents, Sensors, Skills).

  Discovery scans all loaded modules and indexes those with Jido metadata.
  It's read-only and shared across all Jido instances.

  ## Usage

      # List all available actions
      Jido.Discovery.list_actions()
      Jido.Discovery.list_actions(category: :utility, limit: 10)

      # List agents, sensors, skills
      Jido.Discovery.list_agents()
      Jido.Discovery.list_sensors()
      Jido.Discovery.list_skills()

      # Get by slug
      Jido.Discovery.get_action_by_slug("abc123")

      # Refresh catalog (after loading new modules)
      Jido.Discovery.refresh()
  """

  use GenServer

  @catalog_key :jido_discovery_catalog

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      type: :worker,
      restart: :permanent
    }
  end

  @impl true
  def init(:ok) do
    catalog = build_catalog()
    :persistent_term.put(@catalog_key, catalog)
    {:ok, %{}}
  end

  # Public API
  def list_actions(opts \\ []), do: list(:actions, opts)
  def list_agents(opts \\ []), do: list(:agents, opts)
  def list_sensors(opts \\ []), do: list(:sensors, opts)
  def list_skills(opts \\ []), do: list(:skills, opts)

  def get_action_by_slug(slug), do: get_by_slug(:actions, slug)
  def get_agent_by_slug(slug), do: get_by_slug(:agents, slug)

  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    catalog = build_catalog()
    :persistent_term.put(@catalog_key, catalog)
    {:reply, :ok, state}
  end

  defp list(type, opts) do
    catalog = :persistent_term.get(@catalog_key)
    filter_components(Map.get(catalog, type, []), opts)
  end

  defp get_by_slug(type, slug) do
    catalog = :persistent_term.get(@catalog_key)
    Enum.find(Map.get(catalog, type, []), &(&1.slug == slug))
  end

  defp build_catalog do
    # Scan all loaded modules for Jido metadata
    # ... implementation
  end

  defp filter_components(components, opts) do
    # Apply filters: category, tag, name, limit, offset
    # ... implementation
  end
end
```

**Key points:**
- Started once by `Jido.Application`, not per-instance
- Uses `:persistent_term` for fast reads (no GenServer call for queries)
- `refresh/0` rescans after loading new modules at runtime

---

## 8. Scheduler — Built-in Per Instance

Each Jido instance includes a Quantum-based scheduler for agent cron functionality. Jobs can be configured at startup or added dynamically.

```elixir
defmodule Jido.Scheduler do
  @moduledoc """
  Per-instance Quantum scheduler for cron jobs.

  Each Jido instance has its own scheduler, named `MyApp.Jido.Scheduler`.
  Used internally by agent cron directives and available for user jobs.
  """

  use Quantum, otp_app: :jido

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    jobs = Keyword.get(opts, :jobs, [])

    %{
      id: name,
      start: {__MODULE__, :start_link, [[name: name, jobs: jobs]]},
      type: :supervisor,
      restart: :permanent
    }
  end
end
```

### Usage

```elixir
# Configure jobs at startup
children = [
  {Jido, name: MyApp.Jido, scheduler_jobs: [
    {"*/5 * * * *", {MyApp.Jobs, :cleanup_stale_agents, []}},
    {"0 * * * *", {MyApp.Jobs, :hourly_report, []}}
  ]}
]

# Add jobs dynamically
Jido.Scheduler.add_job(Jido.scheduler_name(MyApp.Jido), %Quantum.Job{
  name: :my_job,
  schedule: ~e[*/10 * * * *],
  task: {MyModule, :my_function, []}
})

# Agent cron directives use the instance scheduler automatically
%Directive.Cron{
  schedule: "0 9 * * *",
  signal: my_daily_signal
}
```

---

## 9. AgentServer Updates

Add `:jido` (instance name) awareness:

```elixir
defmodule Jido.AgentServer do
  # Store jido instance in state for Registry operations
  def init(opts) do
    jido = Keyword.fetch!(opts, :jido)
    id = Keyword.get(opts, :id, Jido.generate_id())
    
    # Register with instance-scoped registry
    Registry.register(Jido.registry_name(jido), id, %{})
    
    # ... rest of init
  end

  # Instance-aware call for string IDs
  def call(jido, id, signal, opts) when is_atom(jido) and is_binary(id) do
    case Registry.lookup(Jido.registry_name(jido), id) do
      [{pid, _}] -> call(pid, signal, opts)
      [] -> {:error, :not_found}
    end
  end

  # Direct PID call (instance not needed)
  def call(pid, signal, opts) when is_pid(pid) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(pid, {:signal, signal}, timeout)
  end
end
```

---

## 10. Summary: What Changes

| Before (1.x) | After (2.0) |
|--------------|-------------|
| Auto-start in `Jido.Application` | User adds `{Jido, name: MyApp.Jido}` |
| `Jido.Registry` (global) | `MyApp.Jido.Registry` (per-instance) |
| `Jido.AgentSupervisor` (global) | `MyApp.Jido.AgentSupervisor` (per-instance) |
| `Jido.TaskSupervisor` (global) | `MyApp.Jido.TaskSupervisor` (per-instance) |
| `Jido.Scheduler` (global) | `MyApp.Jido.Scheduler` (per-instance) |
| `Jido.Discovery` (async Task) | `Jido.Discovery` (supervised GenServer, global) |
| `Jido.start_agent(agent)` | Still works via `config :jido, default: X` |
| No test isolation | Unique Jido instance per test |

---

## 11. Effort Estimate

| Task | Effort |
|------|--------|
| Implement `Jido` supervisor (with Scheduler) | M (4-6 hrs) |
| Refactor `AgentServer` for instance awareness | M (4-6 hrs) |
| Refactor `Jido.Scheduler` for per-instance | M (4-6 hrs) |
| Implement `Jido.AgentPool` | M (4-6 hrs) |
| Refactor `Jido.Discovery` to global GenServer | S (2-3 hrs) |
| Update `Jido.Application` | S (1-2 hrs) |
| Update all tests | L (8-12 hrs) |
| Update examples | M (4-6 hrs) |
| Documentation | M (4-6 hrs) |
| **Total** | **~3-4 days** |

---

## 12. Migration Notes

### Breaking Changes from 1.x
- **No auto-start** — Must add `{Jido, name: MyApp.Jido}` to supervision tree
- **Instance-scoped infrastructure** — Registry, AgentSupervisor, TaskSupervisor, Scheduler are per-instance
- **`:jido` option replaces `:runtime`** — All APIs use `:jido` to specify instance
- **Examples need updating** — Update all examples to use new pattern

### Updating Existing Code

```elixir
# Before (1.x)
{:ok, pid} = Jido.start_agent(MyAgent)

# After (2.0) - Option 1: Configure default
# config/config.exs
config :jido, default: MyApp.Jido

# application.ex
children = [{Jido, name: MyApp.Jido}]

# Code unchanged
{:ok, pid} = Jido.start_agent(MyAgent)

# After (2.0) - Option 2: Explicit instance
{:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, [])
```
