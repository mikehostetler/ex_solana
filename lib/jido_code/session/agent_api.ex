defmodule JidoCode.Session.AgentAPI do
  @moduledoc """
  High-level API for interacting with session agents.

  This module provides a clean abstraction for the TUI to communicate
  with session agents without needing to handle agent lookups directly.

  ## Usage

      # Send a synchronous message
      {:ok, response} = AgentAPI.send_message(session_id, "Hello!")

      # Send a streaming message (response via PubSub)
      :ok = AgentAPI.send_message_stream(session_id, "Tell me about Elixir")

  ## Error Handling

  All functions return tagged tuples:
  - `{:ok, result}` - Success
  - `{:error, :agent_not_found}` - Session has no agent
  - `{:error, reason}` - Other errors (validation, agent errors)

  ### Error Atom Convention

  This module uses `:agent_not_found` rather than `:not_found` (used by
  lower-level modules like `Session.State` and `Session.Supervisor`).
  This is intentional API-level semantics:

  - `:not_found` - Generic "resource not found" (used internally)
  - `:agent_not_found` - Specific "session has no agent" (API-level)

  This semantic distinction helps callers understand exactly what was
  not found without needing to know the internal lookup hierarchy.

  ## PubSub Integration

  Streaming responses are broadcast to the session topic.
  Subscribe to `JidoCode.PubSubTopics.llm_stream(session_id)` to receive:
  - `{:stream_chunk, content}` - Content chunks as they arrive
  - `{:stream_end, full_content}` - Stream completion with full content
  - `{:stream_error, reason}` - Stream error occurred

  ## Related Modules

  - `JidoCode.Agents.LLMAgent` - The underlying agent implementation
  - `JidoCode.Session.State` - Session state management
  - `JidoCode.Session.Supervisor` - Per-session process supervision
  """

  alias JidoCode.Agents.LLMAgent
  alias JidoCode.Session.State
  alias JidoCode.Session.Supervisor, as: SessionSupervisor

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc """
  Agent status information returned by `get_status/1`.
  """
  @type status :: %{
          required(:ready) => boolean(),
          required(:config) => config(),
          required(:session_id) => String.t(),
          required(:topic) => String.t()
        }

  @typedoc """
  Agent configuration map.
  """
  @type config :: %{
          optional(:provider) => atom(),
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer()
        }

  @typedoc """
  Configuration update options (map or keyword list).
  """
  @type config_opts :: map() | keyword()

  # ============================================================================
  # Message API
  # ============================================================================

  @doc """
  Sends a message to the session's agent and waits for a response.

  This is a synchronous call that blocks until the agent responds or times out.

  ## Parameters

  - `session_id` - The session identifier
  - `message` - The message to send (must be non-empty string)
  - `opts` - Options passed to `LLMAgent.chat/3`
    - `:timeout` - Request timeout in milliseconds (default: 60000)

  ## Returns

  - `{:ok, response}` - Success with agent response
  - `{:error, :agent_not_found}` - Session has no agent
  - `{:error, {:empty_message, _}}` - Message was empty
  - `{:error, {:message_too_long, _}}` - Message exceeded max length
  - `{:error, reason}` - Other error from agent

  ## Examples

      iex> AgentAPI.send_message("session-123", "Hello!")
      {:ok, "Hello! How can I help you today?"}

      iex> AgentAPI.send_message("unknown-session", "Hello!")
      {:error, :agent_not_found}

      iex> AgentAPI.send_message("session-123", "")
      {:error, {:empty_message, "Message cannot be empty"}}
  """
  @spec send_message(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def send_message(session_id, message, opts \\ [])
      when is_binary(session_id) and is_binary(message) do
    with {:ok, agent_pid} <- get_agent(session_id) do
      LLMAgent.chat(agent_pid, message, opts)
    end
  end

  @doc """
  Sends a message to the session's agent for streaming response.

  This is an asynchronous call that returns immediately. The response is
  streamed via PubSub to the session topic.

  ## Parameters

  - `session_id` - The session identifier
  - `message` - The message to send (must be non-empty string)
  - `opts` - Options passed to `LLMAgent.chat_stream/3`
    - `:timeout` - Streaming timeout in milliseconds (default: 60000)

  ## Returns

  - `:ok` - Message sent for streaming
  - `{:error, :agent_not_found}` - Session has no agent
  - `{:error, {:empty_message, _}}` - Message was empty
  - `{:error, {:message_too_long, _}}` - Message exceeded max length

  ## PubSub Events

  Subscribe to `JidoCode.PubSubTopics.llm_stream(session_id)` to receive:

  - `{:stream_chunk, content}` - Content chunk as string
  - `{:stream_end, full_content}` - Full response when complete
  - `{:stream_error, reason}` - Error during streaming

  ## Examples

      iex> AgentAPI.send_message_stream("session-123", "Tell me about Elixir")
      :ok

      iex> AgentAPI.send_message_stream("unknown-session", "Hello!")
      {:error, :agent_not_found}
  """
  @spec send_message_stream(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def send_message_stream(session_id, message, opts \\ [])
      when is_binary(session_id) and is_binary(message) do
    with {:ok, agent_pid} <- get_agent(session_id) do
      LLMAgent.chat_stream(agent_pid, message, opts)
    end
  end

  # ============================================================================
  # Status API
  # ============================================================================

  @doc """
  Gets the status of the session's agent.

  Returns information about whether the agent is ready and its configuration.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  `{:ok, status}` where status is a map containing:
  - `:ready` - Boolean indicating if the agent is ready to process messages
  - `:config` - Current LLM configuration (provider, model, etc.)
  - `:session_id` - Session identifier
  - `:topic` - PubSub topic for this agent

  `{:error, :agent_not_found}` if the session has no agent.

  ## Examples

      iex> AgentAPI.get_status("session-123")
      {:ok, %{ready: true, config: %{provider: :anthropic, ...}, ...}}

      iex> AgentAPI.get_status("unknown-session")
      {:error, :agent_not_found}
  """
  @spec get_status(String.t()) :: {:ok, status()} | {:error, :agent_not_found | term()}
  def get_status(session_id) when is_binary(session_id) do
    with {:ok, agent_pid} <- get_agent(session_id) do
      LLMAgent.get_status(agent_pid)
    end
  end

  @doc """
  Checks if the session's agent is currently processing a request.

  This is a quick check to determine if the agent is busy. Currently,
  this returns `false` when the agent is ready (i.e., `ready: true` in status).

  Note: LLMAgent handles requests asynchronously through Task.Supervisor,
  so "processing" state detection is based on whether the underlying
  AI agent is alive and ready.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, true}` - Agent is processing (not ready)
  - `{:ok, false}` - Agent is idle (ready)
  - `{:error, :agent_not_found}` - Session has no agent

  ## Examples

      iex> AgentAPI.is_processing?("session-123")
      {:ok, false}

      iex> AgentAPI.is_processing?("unknown-session")
      {:error, :agent_not_found}
  """
  @spec is_processing?(String.t()) :: {:ok, boolean()} | {:error, term()}
  def is_processing?(session_id) when is_binary(session_id) do
    with {:ok, agent_pid} <- get_agent(session_id),
         {:ok, status} <- LLMAgent.get_status(agent_pid) do
      # Processing is the inverse of ready
      # When the AI agent is not alive/ready, we consider it "processing"
      {:ok, not status.ready}
    end
  end

  # ============================================================================
  # Configuration API
  # ============================================================================

  @doc """
  Updates the session's agent configuration.

  This updates both the agent's runtime configuration and the session's
  stored configuration, keeping them in sync.

  ## Parameters

  - `session_id` - The session identifier
  - `config` - Map or keyword list of configuration options:
    - `:provider` - LLM provider (e.g., :anthropic, :openai)
    - `:model` - Model name
    - `:temperature` - Temperature (0.0-2.0)
    - `:max_tokens` - Maximum tokens

  ## Returns

  - `:ok` - Configuration updated successfully
  - `{:error, :agent_not_found}` - Session has no agent
  - `{:error, reason}` - Validation or other error

  ## Examples

      iex> AgentAPI.update_config("session-123", %{temperature: 0.5})
      :ok

      iex> AgentAPI.update_config("session-123", provider: :openai, model: "gpt-4")
      :ok

      iex> AgentAPI.update_config("unknown-session", %{temperature: 0.5})
      {:error, :agent_not_found}
  """
  @spec update_config(String.t(), map() | keyword()) :: :ok | {:error, term()}
  def update_config(session_id, config) when is_binary(session_id) do
    opts = if is_map(config), do: Map.to_list(config), else: config

    with {:ok, agent_pid} <- get_agent(session_id),
         :ok <- LLMAgent.configure(agent_pid, opts) do
      # Also update session's stored config
      config_map = Map.new(opts)
      State.update_session_config(session_id, config_map)
      :ok
    end
  end

  @doc """
  Gets the current configuration for the session's agent.

  ## Parameters

  - `session_id` - The session identifier

  ## Returns

  - `{:ok, config}` - Current configuration map
  - `{:error, :agent_not_found}` - Session has no agent

  ## Examples

      iex> AgentAPI.get_config("session-123")
      {:ok, %{provider: :anthropic, model: "claude-3-5-sonnet-20241022", ...}}

      iex> AgentAPI.get_config("unknown-session")
      {:error, :agent_not_found}
  """
  @spec get_config(String.t()) :: {:ok, map()} | {:error, term()}
  def get_config(session_id) when is_binary(session_id) do
    with {:ok, agent_pid} <- get_agent(session_id) do
      {:ok, LLMAgent.get_config(agent_pid)}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  # Looks up the agent for a session with consistent error handling.
  # Translates :not_found to :agent_not_found for clearer API semantics.
  @spec get_agent(String.t()) :: {:ok, pid()} | {:error, :agent_not_found | term()}
  defp get_agent(session_id) do
    case SessionSupervisor.get_agent(session_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> {:error, :agent_not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
