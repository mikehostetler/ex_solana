defmodule Karo.ChatSession do
  @moduledoc """
  Per-conversation GenServer that manages chat state and LLM interactions.

  Each ChatSession is responsible for:
  - Maintaining in-memory recent messages buffer
  - Persisting messages via Ash
  - Calling the LLM to generate responses
  - Self-terminating after idle timeout

  ## Lifecycle

  ChatSessions are started by the Governor when a message arrives for a new conversation.
  They register themselves in the `Karo.ChatRegistry` and automatically terminate after
  a configurable idle period (default: 15 minutes).
  """

  use GenServer

  require Logger

  @default_idle_timeout :timer.minutes(15)

  def start_link(opts) do
    conversation_key = Keyword.fetch!(opts, :conversation_key)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(conversation_key))
  end

  @doc """
  Sends a user message and returns the assistant's response.
  """
  @spec send_message(pid() | tuple(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def send_message(pid_or_key, user_id, content) when is_pid(pid_or_key) do
    GenServer.call(pid_or_key, {:send_message, user_id, content}, :infinity)
  end

  def send_message(conversation_key, user_id, content) when is_tuple(conversation_key) do
    GenServer.call(via_tuple(conversation_key), {:send_message, user_id, content}, :infinity)
  end

  defp via_tuple(conversation_key) do
    {:via, Registry, {Karo.ChatRegistry, conversation_key}}
  end

  @impl true
  def init(opts) do
    conversation_key = Keyword.fetch!(opts, :conversation_key)
    idle_timeout = get_idle_timeout()

    {conversation_id, messages} = load_conversation(conversation_key)

    state = %{
      conversation_key: conversation_key,
      conversation_id: conversation_id,
      messages: messages,
      idle_timeout: idle_timeout,
      timer_ref: nil
    }

    {:ok, schedule_idle_timeout(state)}
  end

  defp load_conversation(conversation_key) do
    case Karo.ChatDomain.get_or_create_conversation(conversation_key, %{}) do
      {:ok, conversation} ->
        messages = load_messages(conversation.id)
        {conversation.id, messages}

      {:error, reason} ->
        Logger.warning("Failed to load conversation: #{inspect(reason)}, continuing with in-memory only")
        {nil, []}
    end
  end

  defp load_messages(conversation_id) do
    case Karo.ChatDomain.list_recent_messages(conversation_id, limit: max_context_messages()) do
      {:ok, db_messages} ->
        Enum.map(db_messages, fn msg ->
          %{role: msg.role, content: msg.content, user_id: msg.discord_user_id}
        end)

      {:error, reason} ->
        Logger.warning("Failed to load messages: #{inspect(reason)}, continuing with empty messages")
        []
    end
  end

  @impl true
  def handle_call({:send_message, user_id, content}, _from, state) do
    state = cancel_idle_timeout(state)

    user_message = %{role: :user, content: content, user_id: user_id}
    persist_message(state.conversation_id, :user, content, %{discord_user_id: user_id})

    messages = state.messages ++ [user_message]

    {:ok, response} = generate_response(messages)

    persist_message(state.conversation_id, :assistant, response, %{})
    touch_conversation(state.conversation_id)

    assistant_message = %{role: :assistant, content: response, user_id: nil}
    new_messages = truncate_messages(messages ++ [assistant_message])
    new_state = %{state | messages: new_messages}
    {:reply, {:ok, response}, schedule_idle_timeout(new_state)}
  end

  defp persist_message(nil, _role, _content, _meta), do: :ok

  defp persist_message(conversation_id, role, content, meta) do
    case Karo.ChatDomain.create_message(conversation_id, role, content, meta) do
      {:ok, _message} -> :ok
      {:error, reason} -> Logger.warning("Failed to persist message: #{inspect(reason)}")
    end
  end

  defp touch_conversation(nil), do: :ok

  defp touch_conversation(conversation_id) do
    case Karo.ChatDomain.touch_conversation(conversation_id) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("Failed to touch conversation: #{inspect(reason)}")
    end
  end

  defp truncate_messages(messages) do
    max = max_context_messages()

    if length(messages) > max do
      Enum.take(messages, -max)
    else
      messages
    end
  end

  @impl true
  def handle_info(:idle_timeout, state) do
    Logger.debug("ChatSession idle timeout for #{inspect(state.conversation_key)}")
    {:stop, :normal, state}
  end

  @spec generate_response(list()) :: {:ok, String.t()} | {:error, term()}
  defp generate_response(messages) do
    system_message = %{role: :system, content: Karo.Character.system_prompt()}

    llm_messages =
      [system_message | messages]
      |> Enum.map(fn msg -> %{role: msg.role, content: msg.content} end)

    Karo.LLM.chat(llm_messages)
  end

  defp get_idle_timeout do
    Application.get_env(:karo, :chat_session, [])
    |> Keyword.get(:idle_timeout_ms, @default_idle_timeout)
  end

  defp max_context_messages do
    Application.get_env(:karo, :chat_session, [])
    |> Keyword.get(:max_context_messages, 50)
  end

  defp schedule_idle_timeout(state) do
    timer_ref = Process.send_after(self(), :idle_timeout, state.idle_timeout)
    %{state | timer_ref: timer_ref}
  end

  defp cancel_idle_timeout(%{timer_ref: nil} = state), do: state

  defp cancel_idle_timeout(%{timer_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end
end
