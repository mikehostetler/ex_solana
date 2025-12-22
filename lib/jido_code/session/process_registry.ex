defmodule JidoCode.Session.ProcessRegistry do
  @moduledoc """
  Shared helpers for session process registry operations.

  This module consolidates registry via tuple patterns that were previously
  duplicated across Session.Manager, Session.State, and Session.Supervisor.

  ## Registry Keys

  Session processes register with the following key patterns:

  - `{:session, session_id}` - Session.Supervisor
  - `{:manager, session_id}` - Session.Manager
  - `{:state, session_id}` - Session.State
  - `{:agent, session_id}` - LLMAgent (future)

  ## Usage

      # In a GenServer start_link
      def start_link(opts) do
        session = Keyword.fetch!(opts, :session)
        GenServer.start_link(__MODULE__, session,
          name: ProcessRegistry.via(:manager, session.id))
      end

      # Looking up a process
      {:ok, pid} = ProcessRegistry.lookup(:manager, session_id)
  """

  @registry JidoCode.SessionProcessRegistry

  @type process_type :: :session | :manager | :state | :agent

  @doc """
  Returns a via tuple for registering a process in the session registry.

  ## Parameters

  - `process_type` - The type of process (`:session`, `:manager`, `:state`, `:agent`)
  - `session_id` - The session's unique identifier

  ## Returns

  A via tuple suitable for use as the `name` option in GenServer/Supervisor start functions.

  ## Examples

      iex> ProcessRegistry.via(:manager, "session_123")
      {:via, Registry, {JidoCode.SessionProcessRegistry, {:manager, "session_123"}}}
  """
  @spec via(process_type(), String.t()) ::
          {:via, Registry, {atom(), {process_type(), String.t()}}}
  def via(process_type, session_id)
      when process_type in [:session, :manager, :state, :agent] and is_binary(session_id) do
    {:via, Registry, {@registry, {process_type, session_id}}}
  end

  @doc """
  Looks up a process in the session registry.

  ## Parameters

  - `process_type` - The type of process to look up
  - `session_id` - The session's unique identifier

  ## Returns

  - `{:ok, pid}` - Process found
  - `{:error, :not_found}` - No process registered with this key

  ## Examples

      iex> {:ok, pid} = ProcessRegistry.lookup(:manager, session_id)
      iex> is_pid(pid)
      true

      iex> ProcessRegistry.lookup(:manager, "unknown")
      {:error, :not_found}
  """
  @spec lookup(process_type(), String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(process_type, session_id)
      when process_type in [:session, :manager, :state, :agent] and is_binary(session_id) do
    case Registry.lookup(@registry, {process_type, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns the registry name used for session processes.

  Useful when you need to work with the registry directly.

  ## Examples

      iex> ProcessRegistry.registry_name()
      JidoCode.SessionProcessRegistry
  """
  @spec registry_name() :: atom()
  def registry_name, do: @registry

  @doc """
  Makes a synchronous call to a registered process.

  Combines lookup and GenServer.call into a single operation.
  Returns `{:error, :not_found}` if the process is not registered.

  ## Parameters

  - `process_type` - The type of process to call
  - `session_id` - The session's unique identifier
  - `message` - The message to send to the process

  ## Returns

  - The result from `GenServer.call/2` if the process is found
  - `{:error, :not_found}` if no process is registered

  ## Examples

      iex> ProcessRegistry.call(:state, session_id, :get_state)
      {:ok, %{...}}

      iex> ProcessRegistry.call(:state, "unknown", :get_state)
      {:error, :not_found}
  """
  @spec call(process_type(), String.t(), term()) :: term()
  def call(process_type, session_id, message)
      when process_type in [:session, :manager, :state, :agent] and is_binary(session_id) do
    case lookup(process_type, session_id) do
      {:ok, pid} -> GenServer.call(pid, message)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Makes an asynchronous cast to a registered process.

  Combines lookup and GenServer.cast into a single operation.
  Silently returns `:ok` if the process is not registered.

  ## Parameters

  - `process_type` - The type of process to cast to
  - `session_id` - The session's unique identifier
  - `message` - The message to send to the process

  ## Returns

  - `:ok` always (fire-and-forget semantics)

  ## Examples

      iex> ProcessRegistry.cast(:state, session_id, {:streaming_chunk, "hello"})
      :ok
  """
  @spec cast(process_type(), String.t(), term()) :: :ok
  def cast(process_type, session_id, message)
      when process_type in [:session, :manager, :state, :agent] and is_binary(session_id) do
    case lookup(process_type, session_id) do
      {:ok, pid} -> GenServer.cast(pid, message)
      {:error, :not_found} -> :ok
    end
  end
end
