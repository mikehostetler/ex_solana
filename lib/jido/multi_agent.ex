defmodule Jido.MultiAgent do
  @moduledoc """
  Helpers for multi-agent coordination from external callers.

  These are convenience functions for non-agent code (HTTP controllers, CLI, tests)
  that needs to synchronously wait for agents or their children to complete.

  ## Completion Convention

  Agents signal completion via **state**, not process death. The standard pattern is:

      # In your agent, set terminal status:
      agent = put_in(agent.state.status, :completed)
      agent = put_in(agent.state.last_answer, answer)

  This module polls for these status values using configurable paths.

  ## Examples

      # Wait for an agent to complete
      {:ok, pid} = AgentServer.start(agent: MyAgent)
      AgentServer.cast(pid, some_signal)
      {:ok, result} = MultiAgent.await_completion(pid, 10_000)

      # Wait for a specific child of a parent agent
      {:ok, coordinator} = AgentServer.start(agent: CoordinatorAgent)
      AgentServer.cast(coordinator, spawn_worker_signal)
      {:ok, result} = MultiAgent.await_child_completion(coordinator, :worker_1, 30_000)
  """

  alias Jido.AgentServer

  @doc """
  Wait for an agent to reach a terminal status.

  Polls the agent state until `status` is `:completed` or `:failed`,
  or until the timeout is reached.

  ## Options

  - `:status_path` - Path to status field (default: `[:status]`)
  - `:result_path` - Path to result field (default: `[:last_answer]`)
  - `:error_path` - Path to error field (default: `[:error]`)
  - `:poll_interval` - Milliseconds between polls (default: 50)

  ## Returns

  - `{:ok, %{status: :completed, result: any()}}` - Agent completed successfully
  - `{:ok, %{status: :failed, result: any()}}` - Agent failed
  - `{:error, :timeout}` - Timeout reached before completion
  - `{:error, :not_found}` - Agent process not found

  ## Examples

      {:ok, result} = MultiAgent.await_completion(agent_pid, 10_000)

      # With custom paths for strategy state
      {:ok, result} = MultiAgent.await_completion(agent_pid, 10_000,
        status_path: [:__strategy__, :status],
        result_path: [:__strategy__, :result]
      )
  """
  @spec await_completion(AgentServer.server(), non_neg_integer(), Keyword.t()) ::
          {:ok, %{status: atom(), result: any()}} | {:error, term()}
  def await_completion(server, timeout_ms \\ 10_000, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_interval = Keyword.get(opts, :poll_interval, 50)
    status_path = Keyword.get(opts, :status_path, [:status])
    result_path = Keyword.get(opts, :result_path, [:last_answer])
    error_path = Keyword.get(opts, :error_path, [:error])

    do_await_completion(server, deadline, poll_interval, status_path, result_path, error_path)
  end

  defp do_await_completion(server, deadline, poll_interval, status_path, result_path, error_path) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case AgentServer.state(server) do
        {:ok, %{agent: %{state: state}}} ->
          status = get_in(state, status_path)

          case status do
            :completed ->
              {:ok, %{status: :completed, result: get_in(state, result_path)}}

            :failed ->
              {:ok, %{status: :failed, result: get_in(state, error_path)}}

            _ ->
              Process.sleep(poll_interval)

              do_await_completion(
                server,
                deadline,
                poll_interval,
                status_path,
                result_path,
                error_path
              )
          end

        {:error, :not_found} ->
          {:error, :not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Wait for a specific child of a parent agent to complete.

  First looks up the child by tag in the parent's `children` map,
  then polls the child for completion.

  ## Options

  Same as `await_completion/3`.

  ## Returns

  - `{:ok, %{status: atom(), result: any()}}` - Child completed
  - `{:error, :child_not_found}` - Child with given tag not found
  - `{:error, :timeout}` - Timeout reached
  - `{:error, term()}` - Other error

  ## Examples

      {:ok, coordinator} = AgentServer.start(agent: CoordinatorAgent)
      AgentServer.cast(coordinator, %Signal{type: "spawn_worker"})
      {:ok, result} = MultiAgent.await_child_completion(coordinator, :worker_1, 30_000)
  """
  @spec await_child_completion(AgentServer.server(), term(), non_neg_integer(), Keyword.t()) ::
          {:ok, %{status: atom(), result: any()}} | {:error, term()}
  def await_child_completion(parent_server, child_tag, timeout_ms \\ 10_000, opts \\ []) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_interval = Keyword.get(opts, :poll_interval, 50)

    case wait_for_child_pid(parent_server, child_tag, deadline, poll_interval) do
      {:ok, child_pid} ->
        remaining = max(0, deadline - System.monotonic_time(:millisecond))
        await_completion(child_pid, remaining, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_child_pid(parent_server, child_tag, deadline, poll_interval) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case AgentServer.state(parent_server) do
        {:ok, %{children: children}} ->
          case Map.get(children, child_tag) do
            %{pid: child_pid} when is_pid(child_pid) ->
              {:ok, child_pid}

            nil ->
              Process.sleep(poll_interval)
              wait_for_child_pid(parent_server, child_tag, deadline, poll_interval)
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Get the PIDs of all children of a parent agent.

  ## Returns

  - `{:ok, %{tag => pid}}` - Map of child tags to PIDs
  - `{:error, term()}` - Error getting parent state

  ## Examples

      {:ok, children} = MultiAgent.get_children(coordinator)
      # => {:ok, %{worker_1: #PID<0.123.0>, worker_2: #PID<0.124.0>}}
  """
  @spec get_children(AgentServer.server()) :: {:ok, %{term() => pid()}} | {:error, term()}
  def get_children(parent_server) do
    case AgentServer.state(parent_server) do
      {:ok, %{children: children}} ->
        pids = Map.new(children, fn {tag, info} -> {tag, info.pid} end)
        {:ok, pids}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
