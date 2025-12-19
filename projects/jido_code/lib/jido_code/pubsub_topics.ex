defmodule JidoCode.PubSubTopics do
  @moduledoc """
  Centralized PubSub topic definitions for JidoCode.

  This module ensures consistent topic naming across all components:
  - TUI subscribes to the correct topics
  - LLMAgent broadcasts to the correct topics
  - Commands broadcast to the correct topics

  ## Topics

  - `tui_events/0` - General TUI events topic
  - `llm_stream/1` - Session-specific streaming topic
  - `config_changes/0` - Configuration change notifications
  """

  @doc """
  Returns the general TUI events topic.

  Used for:
  - Agent status updates
  - Configuration changes
  - General notifications
  """
  @spec tui_events() :: String.t()
  def tui_events, do: "tui.events"

  @doc """
  Returns the session-specific streaming topic.

  Used for:
  - Stream chunks during LLM responses
  - Stream end notifications
  - Stream error notifications

  ## Parameters

  - `session_id` - The unique session identifier
  """
  @spec llm_stream(String.t()) :: String.t()
  def llm_stream(session_id), do: "tui.events.#{session_id}"

  @doc """
  Returns the configuration changes topic.

  Used for broadcasting configuration updates that should
  be received by multiple subscribers.
  """
  @spec config_changes() :: String.t()
  def config_changes, do: "config.changes"
end
