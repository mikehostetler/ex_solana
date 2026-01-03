defmodule Karo do
  @moduledoc """
  Karo - A persistent AI agent for Elixir applications.

  Karo maintains conversation memory across sessions, integrates with the Jido
  ecosystem for character definitions and LLM interactions, and can be accessed
  via Discord or a local TUI.

  ## Quick Start

      # Send a message to a conversation
      {:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!")

  ## Architecture

  Karo uses a Governor pattern to manage chat sessions:

  - **Governor**: Routes messages to ChatSessions, manages lifecycle
  - **ChatSession**: One GenServer per conversation, handles LLM calls
  - **Registry**: O(1) lookup for active sessions
  - **DynamicSupervisor**: Fault isolation for chat processes

  ## Configuration

      config :karo,
        llm: [
          provider: :openai,
          model: "gpt-4o-mini",
          api_key: System.fetch_env!("OPENAI_API_KEY")
        ],
        chat_session: [
          idle_timeout_ms: :timer.minutes(15),
          max_context_messages: 50
        ]
  """

  @doc """
  Sends a message to a conversation and returns the assistant's response.

  ## Parameters

    * `channel_id` - The channel/conversation identifier
    * `user_id` - The user sending the message
    * `content` - The message content
    * `opts` - Optional parameters
      * `:guild_id` - Discord guild ID (nil for DMs)
      * `:thread_id` - Discord thread ID (nil for main channel)

  ## Examples

      # Simple message
      {:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!")

      # Discord guild message
      {:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!",
        guild_id: "guild_789")

      # Discord thread message
      {:ok, response} = Karo.send_message("channel_123", "user_456", "Hello!",
        guild_id: "guild_789",
        thread_id: "thread_012")

  """
  @spec send_message(String.t(), String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def send_message(channel_id, user_id, content, opts \\ []) do
    guild_id = Keyword.get(opts, :guild_id)
    thread_id = Keyword.get(opts, :thread_id)
    conversation_key = {guild_id, channel_id, thread_id}

    Karo.Governor.send_message(conversation_key, user_id, content)
  end
end
