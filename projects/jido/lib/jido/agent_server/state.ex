defmodule Jido.AgentServer.State do
  @moduledoc """
  Internal state for AgentServer GenServer.

  > #### Internal Module {: .warning}
  > This module is internal to the AgentServer implementation. Its API may
  > change without notice. Use `Jido.AgentServer.state/1` to retrieve state.

  This struct holds all runtime state for an agent instance including
  the agent itself, directive queue, hierarchy tracking, and configuration.
  """

  alias Jido.AgentServer.{ChildInfo, Options}

  @type status :: :initializing | :idle | :processing | :stopping

  @schema Zoi.struct(
            __MODULE__,
            %{
              # Core identity
              id: Zoi.string(description: "Instance ID"),
              agent_module: Zoi.atom(description: "Agent module"),
              agent: Zoi.any(description: "The Jido.Agent struct"),

              # Status and processing
              status:
                Zoi.atom(description: "Current server status") |> Zoi.default(:initializing),
              processing:
                Zoi.boolean(description: "Whether currently processing directives")
                |> Zoi.default(false),
              queue:
                Zoi.any(description: "Directive queue (:queue.queue())")
                |> Zoi.default(:queue.new()),

              # Hierarchy
              parent: Zoi.any(description: "Parent reference") |> Zoi.optional(),
              children: Zoi.map(description: "Map of tag => ChildInfo") |> Zoi.default(%{}),
              on_parent_death:
                Zoi.atom(description: "Behavior on parent death") |> Zoi.default(:stop),

              # Cron jobs
              cron_jobs:
                Zoi.map(description: "Map of job_id => scheduler job name") |> Zoi.default(%{}),

              # Configuration
              jido: Zoi.atom(description: "Jido instance name (required)"),
              default_dispatch: Zoi.any(description: "Default dispatch config") |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Error handling policy") |> Zoi.default(:log_only),
              max_queue_size: Zoi.integer(description: "Max queue size") |> Zoi.default(10_000),
              registry: Zoi.atom(description: "Registry module"),
              spawn_fun: Zoi.any(description: "Custom spawn function") |> Zoi.optional(),

              # Routing
              signal_router:
                Zoi.any(description: "Jido.Signal.Router for signal routing")
                |> Zoi.optional(),

              # Observability
              error_count:
                Zoi.integer(description: "Count of errors for max_errors policy")
                |> Zoi.default(0),
              metrics: Zoi.map(description: "Runtime metrics") |> Zoi.default(%{}),
              completion_waiters:
                Zoi.map(description: "Map of ref => waiter for completion notifications")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc """
  Creates a new State from validated Options, agent module, and agent struct.

  If a parent reference is provided, it's injected into the agent's state
  as `agent.state.__parent__` so agents can use `Directive.emit_to_parent/3`.
  """
  @spec from_options(Options.t(), module(), struct()) :: {:ok, t()} | {:error, term()}
  def from_options(%Options{} = opts, agent_module, agent) do
    agent = inject_parent_into_agent(agent, opts.parent)

    attrs = %{
      id: opts.id,
      agent_module: agent_module,
      agent: agent,
      status: :initializing,
      processing: false,
      queue: :queue.new(),
      parent: opts.parent,
      children: %{},
      on_parent_death: opts.on_parent_death,
      jido: opts.jido,
      default_dispatch: opts.default_dispatch,
      error_policy: opts.error_policy,
      max_queue_size: opts.max_queue_size,
      registry: opts.registry,
      spawn_fun: opts.spawn_fun,
      cron_jobs: %{},
      error_count: 0,
      metrics: %{},
      completion_waiters: %{}
    }

    Zoi.parse(@schema, attrs)
  end

  defp inject_parent_into_agent(agent, nil), do: agent

  defp inject_parent_into_agent(agent, parent) do
    updated_state = Map.put(agent.state, :__parent__, parent)
    %{agent | state: updated_state}
  end

  @doc """
  Updates the agent in state.
  """
  @spec update_agent(t(), struct()) :: t()
  def update_agent(%__MODULE__{} = state, agent) do
    %{state | agent: agent}
  end

  @doc """
  Sets the status.
  """
  @spec set_status(t(), status()) :: t()
  def set_status(%__MODULE__{} = state, status)
      when status in [:initializing, :idle, :processing, :stopping] do
    %{state | status: status}
  end

  @doc """
  Enqueues a directive with its triggering signal for later execution.
  """
  @spec enqueue(t(), Jido.Signal.t(), struct()) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue(%__MODULE__{queue: queue, max_queue_size: max} = state, signal, directive) do
    if :queue.len(queue) >= max do
      {:error, :queue_overflow}
    else
      {:ok, %{state | queue: :queue.in({signal, directive}, queue)}}
    end
  end

  @doc """
  Enqueues multiple directives from a single signal.
  """
  @spec enqueue_all(t(), Jido.Signal.t(), [struct()]) :: {:ok, t()} | {:error, :queue_overflow}
  def enqueue_all(state, _signal, []), do: {:ok, state}

  def enqueue_all(%__MODULE__{} = state, signal, [directive | rest]) do
    case enqueue(state, signal, directive) do
      {:ok, new_state} -> enqueue_all(new_state, signal, rest)
      error -> error
    end
  end

  @doc """
  Dequeues the next directive for processing.
  """
  @spec dequeue(t()) :: {{:value, {Jido.Signal.t(), struct()}}, t()} | {:empty, t()}
  def dequeue(%__MODULE__{queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        {{:value, item}, %{state | queue: new_queue}}

      {:empty, _} ->
        {:empty, state}
    end
  end

  @doc """
  Returns the current queue length.
  """
  @spec queue_length(t()) :: non_neg_integer()
  def queue_length(%__MODULE__{queue: queue}) do
    :queue.len(queue)
  end

  @doc """
  Checks if the queue is empty.
  """
  @spec queue_empty?(t()) :: boolean()
  def queue_empty?(%__MODULE__{queue: queue}) do
    :queue.is_empty(queue)
  end

  @doc """
  Adds a child to the children map.
  """
  @spec add_child(t(), term(), ChildInfo.t()) :: t()
  def add_child(%__MODULE__{children: children} = state, tag, %ChildInfo{} = child) do
    %{state | children: Map.put(children, tag, child)}
  end

  @doc """
  Removes a child by tag.
  """
  @spec remove_child(t(), term()) :: t()
  def remove_child(%__MODULE__{children: children} = state, tag) do
    %{state | children: Map.delete(children, tag)}
  end

  @doc """
  Removes a child by PID.
  """
  @spec remove_child_by_pid(t(), pid()) :: {term() | nil, t()}
  def remove_child_by_pid(%__MODULE__{children: children} = state, pid) do
    case Enum.find(children, fn {_tag, child} -> child.pid == pid end) do
      {tag, _child} ->
        {tag, %{state | children: Map.delete(children, tag)}}

      nil ->
        {nil, state}
    end
  end

  @doc """
  Gets a child by tag.
  """
  @spec get_child(t(), term()) :: ChildInfo.t() | nil
  def get_child(%__MODULE__{children: children}, tag) do
    Map.get(children, tag)
  end

  @doc """
  Increments the error count.
  """
  @spec increment_error_count(t()) :: t()
  def increment_error_count(%__MODULE__{error_count: count} = state) do
    %{state | error_count: count + 1}
  end
end
