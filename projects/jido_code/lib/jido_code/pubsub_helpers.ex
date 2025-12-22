defmodule JidoCode.PubSubHelpers do
  @moduledoc """
  Shared PubSub broadcasting helpers.

  This module consolidates the ARCH-2 dual-topic broadcasting pattern used
  across the codebase. When a session_id is provided, messages are broadcast
  to BOTH the session-specific topic AND the global topic to ensure all
  subscribers receive the message.

  ## Topics

  - `"tui.events"` - Global topic for all TUI events
  - `"tui.events.{session_id}"` - Session-specific topic

  ## Usage

      alias JidoCode.PubSubHelpers

      # Broadcast to appropriate topic(s)
      PubSubHelpers.broadcast(session_id, {:tool_call, name, params, id, session_id})

      # Get topic name for subscriptions
      topic = PubSubHelpers.session_topic(session_id)

  ## ARCH-2 Pattern

  The dual-topic broadcasting ensures:
  1. Session-specific subscribers receive messages on their topic
  2. Global subscribers (like PubSubBridge) receive ALL messages
  3. Backwards compatibility with code subscribing only to global topic
  """

  @global_topic "tui.events"

  @doc """
  Broadcasts a message to the appropriate PubSub topic(s).

  When `session_id` is `nil`, broadcasts only to the global topic.
  When `session_id` is provided, broadcasts to BOTH the session-specific
  topic and the global topic (ARCH-2 pattern).

  ## Parameters

  - `session_id` - Session identifier or nil
  - `message` - The message to broadcast

  ## Examples

      # Global broadcast only
      PubSubHelpers.broadcast(nil, {:event, :data})

      # Dual broadcast (ARCH-2)
      PubSubHelpers.broadcast("abc-123", {:event, :data})
  """
  @spec broadcast(String.t() | nil, term()) :: :ok
  def broadcast(nil, message) do
    Phoenix.PubSub.broadcast(JidoCode.PubSub, @global_topic, message)
  end

  def broadcast(session_id, message) when is_binary(session_id) do
    # ARCH-2: Broadcast to both session-specific AND global topics
    Phoenix.PubSub.broadcast(JidoCode.PubSub, session_topic(session_id), message)
    Phoenix.PubSub.broadcast(JidoCode.PubSub, @global_topic, message)
  end

  @doc """
  Returns the PubSub topic for a given session ID.

  ## Parameters

  - `session_id` - Session ID or nil

  ## Returns

  - `"tui.events.{session_id}"` if session_id is provided
  - `"tui.events"` if session_id is nil

  ## Examples

      iex> PubSubHelpers.session_topic(nil)
      "tui.events"

      iex> PubSubHelpers.session_topic("abc-123")
      "tui.events.abc-123"
  """
  @spec session_topic(String.t() | nil) :: String.t()
  def session_topic(nil), do: @global_topic
  def session_topic(session_id) when is_binary(session_id), do: "#{@global_topic}.#{session_id}"

  @doc """
  Returns the global topic name.

  ## Examples

      iex> PubSubHelpers.global_topic()
      "tui.events"
  """
  @spec global_topic() :: String.t()
  def global_topic, do: @global_topic
end
