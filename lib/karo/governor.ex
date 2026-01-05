defmodule Karo.Governor do
  @moduledoc """
  Central router and lifecycle manager for Karo chat sessions.

  The Governor is responsible for:
  - Routing incoming messages to the appropriate ChatSession
  - Managing the lifecycle of ChatSession processes
  - Handling CRON scheduled events
  - Cleanup coordination when conversations are closed

  ## Architecture

  The Governor maintains the invariant: **one ChatSession per conversation_key**.
  It uses a Registry for O(1) lookup and a DynamicSupervisor for fault isolation.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a message to the appropriate chat session, starting one if needed.

  ## Parameters

    * `conversation_key` - Tuple identifying the conversation `{guild_id, channel_id, thread_id}`
    * `user_id` - The user sending the message
    * `content` - The message content

  ## Returns

    * `{:ok, response}` - The assistant's response
    * `{:error, reason}` - If the message could not be processed
  """
  @spec send_message(tuple(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def send_message(conversation_key, user_id, content) do
    GenServer.call(__MODULE__, {:send_message, conversation_key, user_id, content}, :infinity)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:send_message, conversation_key, user_id, content}, _from, state) do
    case get_or_start_session(conversation_key) do
      {:ok, session_pid} ->
        response = Karo.ChatSession.send_message(session_pid, user_id, content)
        {:reply, response, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp get_or_start_session(conversation_key) do
    case Registry.lookup(Karo.ChatRegistry, conversation_key) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        start_session(conversation_key)
    end
  end

  defp start_session(conversation_key) do
    child_spec = {Karo.ChatSession, conversation_key: conversation_key}

    case DynamicSupervisor.start_child(Karo.ChatSupervisor, child_spec) do
      {:ok, pid} ->
        Logger.debug("Started ChatSession for #{inspect(conversation_key)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start ChatSession: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
