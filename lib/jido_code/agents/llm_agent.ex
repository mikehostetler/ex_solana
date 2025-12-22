defmodule JidoCode.Agents.LLMAgent do
  @moduledoc """
  LLM Agent for handling chat interactions in JidoCode.

  This agent wraps JidoAI's Agent system to provide a coding assistant
  that can be configured with different LLM providers and models at runtime.

  ## Usage

      # Start with default config from JidoCode.Config
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link()

      # Start with custom options
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link(
        provider: :openai,
        model: "gpt-4o",
        temperature: 0.5
      )

      # Send a chat message
      {:ok, response} = JidoCode.Agents.LLMAgent.chat(pid, "How do I reverse a list in Elixir?")

  ## PubSub Integration

  Responses are broadcast to the session-specific PubSub topic with the event type
  `{:agent_response, response}` for TUI consumption.

  ## Supervision

  This agent can be started under the AgentSupervisor for lifecycle management:

      JidoCode.AgentSupervisor.start_agent(%{
        name: :llm_agent,
        module: JidoCode.Agents.LLMAgent,
        args: []
      })
  """

  use GenServer
  require Logger

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Agent, as: AIAgent
  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter
  alias Jido.AI.Prompt
  alias JidoCode.Config
  alias JidoCode.PubSubTopics
  alias JidoCode.Session.ProcessRegistry
  alias JidoCode.Session.State, as: SessionState
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Result

  @pubsub JidoCode.PubSub
  @default_timeout 60_000
  @max_message_length 10_000

  # System prompt should NOT include user input to prevent prompt injection attacks.
  # User messages are passed separately to the AI agent via chat_response/3.
  @system_prompt """
  You are JidoCode, an expert coding assistant running in a terminal interface.

  Your capabilities:
  - Answer programming questions across all languages
  - Explain code, algorithms, and concepts
  - Help debug issues and suggest fixes
  - Provide code examples and best practices
  - Assist with architecture and design decisions

  Guidelines:
  - Be concise but thorough - terminal space is limited
  - Use markdown code blocks with language hints
  - When showing code changes, be specific about file locations
  - Ask clarifying questions when requirements are ambiguous
  - Acknowledge limitations when you're uncertain
  """

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the LLM agent.

  ## Options

  - `:provider` - Override the provider from config (e.g., `:anthropic`, `:openai`)
  - `:model` - Override the model name from config
  - `:temperature` - Override temperature (0.0-1.0)
  - `:max_tokens` - Override max tokens
  - `:name` - GenServer name for registration (optional)
  - `:session_id` - Session ID for PubSub topic isolation (optional, defaults to agent PID string)

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, reason}` - Failed to start (e.g., invalid config)

  ## Examples

      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link()
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link(session_id: "user-123")
      {:ok, pid} = JidoCode.Agents.LLMAgent.start_link(name: {:via, Registry, {MyRegistry, :llm}})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Returns a via tuple for registering an LLMAgent with a session.

  Use this when you want to register an agent in the session registry
  and look it up by session_id later using `Session.Supervisor.get_agent/1`.

  ## Parameters

  - `session_id` - The session's unique identifier (must be a valid UUID)

  ## Returns

  A via tuple suitable for use as the `name` option in `start_link/1`.

  ## Examples

      # Start an agent registered to a session
      {:ok, pid} = LLMAgent.start_link(
        session_id: "550e8400-e29b-41d4-a716-446655440000",
        name: LLMAgent.via("550e8400-e29b-41d4-a716-446655440000")
      )

      # Later, look up by session_id
      {:ok, pid} = Session.Supervisor.get_agent("550e8400-e29b-41d4-a716-446655440000")
  """
  @spec via(String.t()) :: {:via, Registry, {atom(), {atom(), String.t()}}}
  def via(session_id) when is_binary(session_id) do
    ProcessRegistry.via(:agent, session_id)
  end

  @doc """
  Sends a chat message to the agent and returns the response.

  The response is also broadcast to the PubSub `"tui.events"` topic.

  ## Parameters

  - `pid` - The agent process
  - `message` - The user's message string (max #{@max_message_length} characters)
  - `opts` - Options (`:timeout` defaults to 60 seconds)

  ## Returns

  - `{:ok, response}` - Response string from the LLM
  - `{:error, reason}` - Failed to get response

  ## Examples

      {:ok, response} = JidoCode.Agents.LLMAgent.chat(pid, "Explain pattern matching")
  """
  @spec chat(GenServer.server(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def chat(pid, message, opts \\ []) when is_binary(message) do
    case validate_message(message) do
      :ok ->
        timeout = Keyword.get(opts, :timeout, @default_timeout)
        GenServer.call(pid, {:chat, message}, timeout + 5_000)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Sends a chat message to the agent with streaming response.

  Unlike `chat/3`, this function broadcasts response chunks via PubSub as they arrive,
  providing real-time streaming feedback. The function returns immediately after
  starting the stream.

  ## PubSub Events

  The following events are broadcast to the session's PubSub topic:

  - `{:stream_chunk, text}` - Partial response text as it arrives
  - `{:stream_end, full_content}` - Stream completed with full response
  - `{:stream_error, reason}` - Stream failed with error

  ## Parameters

  - `pid` - The agent process
  - `message` - The user's message string (max #{@max_message_length} characters)
  - `opts` - Options (`:timeout` defaults to 60 seconds)

  ## Returns

  - `:ok` - Stream started successfully (responses come via PubSub)
  - `{:error, reason}` - Failed to start stream

  ## Examples

      :ok = JidoCode.Agents.LLMAgent.chat_stream(pid, "Explain pattern matching")
      # Subscribe to PubSub to receive {:stream_chunk, text} events
  """
  @spec chat_stream(GenServer.server(), String.t(), keyword()) :: :ok | {:error, term()}
  def chat_stream(pid, message, opts \\ []) when is_binary(message) do
    case validate_message(message) do
      :ok ->
        timeout = Keyword.get(opts, :timeout, @default_timeout)
        GenServer.cast(pid, {:chat_stream, message, timeout})

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the current model configuration.
  """
  @spec get_config(GenServer.server()) :: map()
  def get_config(pid) do
    GenServer.call(pid, :get_config)
  end

  @doc """
  Returns the session ID and PubSub topic for this agent.

  Use the topic to subscribe to events from this specific agent instance.

  ## Example

      {:ok, session_id, topic} = JidoCode.Agents.LLMAgent.get_session_info(pid)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  """
  @spec get_session_info(GenServer.server()) :: {:ok, String.t(), String.t()}
  def get_session_info(pid) do
    GenServer.call(pid, :get_session_info)
  end

  @doc """
  Returns the current status of the agent.

  ## Returns

  `{:ok, status}` where status is a map containing:
  - `:ready` - Boolean indicating if the agent is ready to process messages
  - `:config` - Current LLM configuration
  - `:session_id` - Session identifier
  - `:topic` - PubSub topic for this agent

  ## Example

      {:ok, status} = LLMAgent.get_status(pid)
      if status.ready do
        LLMAgent.chat(pid, "Hello!")
      end
  """
  @spec get_status(GenServer.server()) :: {:ok, map()}
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Builds a PubSub topic for a given session ID.

  This is useful for subscribing to events before the agent is started.

  ## Example

      topic = JidoCode.Agents.LLMAgent.topic_for_session("user-123")
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
  """
  @spec topic_for_session(String.t()) :: String.t()
  def topic_for_session(session_id) when is_binary(session_id) do
    PubSubTopics.llm_stream(session_id)
  end

  @doc """
  Returns the tool execution context for this agent's session.

  The context is built from the agent's session_id and includes:
  - `session_id` - The session identifier
  - `project_root` - The session's project root path
  - `timeout` - Default tool execution timeout

  This is useful for external code that needs to execute tools
  in the same session context as the agent.

  ## Returns

  - `{:ok, context}` - Context map with session_id, project_root, timeout
  - `{:error, :no_session_id}` - Agent was started without session_id
  - `{:error, :not_found}` - Session not found in registry

  ## Examples

      {:ok, context} = LLMAgent.get_tool_context(pid)
      Tools.Executor.execute(tool_call, context: context)
  """
  @spec get_tool_context(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_tool_context(pid) do
    GenServer.call(pid, :get_tool_context)
  end

  @doc """
  Builds a tool execution context from a session_id.

  This is a convenience function that delegates to `Tools.Executor.build_context/1`.
  Use this when you have a session_id but not a running agent.

  ## Parameters

  - `session_id` - The session's unique identifier

  ## Returns

  - `{:ok, context}` - Context map with session_id, project_root, timeout
  - `{:error, :not_found}` - Session not found
  - `{:error, :invalid_session_id}` - Invalid session_id format

  ## Examples

      {:ok, context} = LLMAgent.build_tool_context("550e8400-e29b-41d4-a716-446655440000")
      Tools.Executor.execute(tool_call, context: context)
  """
  @spec build_tool_context(String.t()) :: {:ok, map()} | {:error, term()}
  def build_tool_context(session_id) when is_binary(session_id) do
    Executor.build_context(session_id)
  end

  def build_tool_context(nil), do: {:error, :no_session_id}

  @doc """
  Executes a tool call using the agent's session context.

  The tool call is executed through the session-scoped executor,
  which validates paths and enforces security boundaries.

  ## Parameters

  - `pid` - The agent process
  - `tool_call` - Map with `:id`, `:name`, `:arguments` keys

  ## Returns

  - `{:ok, %Result{}}` - Tool execution result
  - `{:error, :no_session_id}` - Agent was started without proper session_id
  - `{:error, :not_found}` - Session not found in registry
  - `{:error, term()}` - Other execution failures

  ## Examples

      tool_call = %{id: "call_1", name: "read_file", arguments: %{"path" => "/src/main.ex"}}
      {:ok, result} = LLMAgent.execute_tool(pid, tool_call)
      result.status  # => :ok or :error
      result.content # => file contents or error message
  """
  @spec execute_tool(GenServer.server(), map()) ::
          {:ok, Result.t()} | {:error, term()}
  def execute_tool(pid, tool_call) do
    GenServer.call(pid, {:execute_tool, tool_call})
  end

  @doc """
  Executes multiple tool calls using the agent's session context.

  ## Parameters

  - `pid` - The agent process
  - `tool_calls` - List of tool call maps with `:id`, `:name`, `:arguments` keys
  - `opts` - Options

  ## Options

  - `:parallel` - Execute tools in parallel (default: `false`)
  - `:timeout` - Override timeout per tool (default: executor's default)

  ## Returns

  - `{:ok, [%Result{}]}` - List of results in same order as input
  - `{:error, :no_session_id}` - Agent was started without proper session_id
  - `{:error, :not_found}` - Session not found in registry

  ## Examples

      tool_calls = [
        %{id: "call_1", name: "read_file", arguments: %{"path" => "/a.txt"}},
        %{id: "call_2", name: "read_file", arguments: %{"path" => "/b.txt"}}
      ]
      {:ok, results} = LLMAgent.execute_tool_batch(pid, tool_calls, parallel: true)
  """
  @spec execute_tool_batch(GenServer.server(), [map()], keyword()) ::
          {:ok, [Result.t()]} | {:error, term()}
  def execute_tool_batch(pid, tool_calls, opts \\ []) do
    GenServer.call(pid, {:execute_tool_batch, tool_calls, opts})
  end

  @doc """
  Reconfigures the agent with new provider/model settings at runtime.

  This performs hot-swapping of the underlying AI agent without restarting
  the LLMAgent GenServer. The new configuration is validated before being
  applied.

  ## Options

  - `:provider` - New provider atom (e.g., `:anthropic`, `:openai`)
  - `:model` - New model name string
  - `:temperature` - New temperature (0.0-1.0)
  - `:max_tokens` - New max tokens

  ## Validation

  The following validations are performed:
  1. Provider must exist in the ReqLLM registry
  2. Model must exist for the specified provider
  3. API key must be available for the provider

  ## Returns

  - `:ok` - Configuration updated successfully
  - `{:error, reason}` - Validation failed or reconfiguration failed

  ## Examples

      # Switch to OpenAI
      :ok = JidoCode.Agents.LLMAgent.configure(pid, provider: :openai, model: "gpt-4o")

      # Invalid provider
      {:error, "Provider :invalid not found..."} = JidoCode.Agents.LLMAgent.configure(pid, provider: :invalid)
  """
  @spec configure(GenServer.server(), keyword()) :: :ok | {:error, String.t()}
  def configure(pid, opts) when is_list(opts) do
    GenServer.call(pid, {:configure, opts})
  end

  @doc """
  Lists available LLM providers from the ReqLLM registry.

  ## Returns

  - `{:ok, providers}` - List of provider atoms
  - `{:error, reason}` - Registry unavailable

  ## Examples

      {:ok, providers} = JidoCode.Agents.LLMAgent.list_providers()
      # => {:ok, [:anthropic, :openai, :google, ...]}
  """
  @spec list_providers() :: {:ok, [atom()]} | {:error, term()}
  def list_providers do
    RegistryAdapter.list_providers()
  end

  @doc """
  Lists available models for a provider.

  ## Returns

  - `{:ok, models}` - List of model name strings
  - `{:error, reason}` - Provider not found or registry unavailable

  ## Examples

      {:ok, models} = JidoCode.Agents.LLMAgent.list_models(:anthropic)
      # => {:ok, ["claude-3-5-sonnet-20241022", "claude-3-opus-20240229", ...]}
  """
  @spec list_models(atom()) :: {:ok, [String.t()]} | {:error, term()}
  def list_models(provider) when is_atom(provider) do
    case RegistryAdapter.list_models(provider) do
      {:ok, models} -> {:ok, extract_model_names(models)}
      {:error, _} = error -> error
    end
  end

  defp extract_model_names(models) do
    models
    |> Enum.map(&get_model_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp get_model_name(%{model: name}) when is_binary(name), do: name
  defp get_model_name(_), do: nil

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    # Trap exits so we can handle AI agent crashes gracefully
    Process.flag(:trap_exit, true)

    # Extract session_id before building config
    {session_id, config_opts} = Keyword.pop(opts, :session_id)

    case build_config(config_opts) do
      {:ok, config} ->
        case start_ai_agent(config) do
          {:ok, ai_pid} ->
            # Use provided session_id or generate one based on agent PID
            actual_session_id = session_id || inspect(self())

            state = %{
              ai_pid: ai_pid,
              config: config,
              session_id: actual_session_id,
              topic: build_topic(actual_session_id)
            }

            {:ok, state}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, reason}, %{ai_pid: ai_pid} = state) when pid == ai_pid do
    Logger.warning("AI agent exited: #{inspect(reason)}")
    # Attempt to restart the AI agent
    case start_ai_agent(state.config) do
      {:ok, new_ai_pid} ->
        {:noreply, %{state | ai_pid: new_ai_pid}}

      {:error, _} ->
        {:stop, {:ai_agent_died, reason}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore other exits
    {:noreply, state}
  end

  @impl true
  def handle_call({:chat, message}, from, state) do
    # ARCH-1 Fix: Use Task.Supervisor for monitored async tasks
    # This prevents silent failures and hanging callers
    ai_pid = state.ai_pid
    topic = state.topic

    Task.Supervisor.start_child(JidoCode.TaskSupervisor, fn ->
      result = do_chat(ai_pid, message)

      # Broadcast to session-specific PubSub topic for TUI
      case result do
        {:ok, response} ->
          broadcast_response(topic, response)

        _ ->
          :ok
      end

      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call(:get_session_info, _from, state) do
    {:reply, {:ok, state.session_id, state.topic}, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      ready: is_pid(state.ai_pid) and Process.alive?(state.ai_pid),
      config: state.config,
      session_id: state.session_id,
      topic: state.topic
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:get_tool_context, _from, state) do
    result = do_build_tool_context(state.session_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:execute_tool, tool_call}, _from, state) do
    result = do_execute_tool(tool_call, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:execute_tool_batch, tool_calls, opts}, _from, state) do
    result = do_execute_tool_batch(tool_calls, opts, state)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:configure, opts}, _from, state) do
    # Build new config, merging with current config
    new_config = %{
      provider: Keyword.get(opts, :provider, state.config.provider),
      model: Keyword.get(opts, :model, state.config.model),
      temperature: Keyword.get(opts, :temperature, state.config.temperature),
      max_tokens: Keyword.get(opts, :max_tokens, state.config.max_tokens)
    }

    # Skip validation and restart if config unchanged
    if new_config == state.config do
      {:reply, :ok, state}
    else
      apply_config_change(new_config, state)
    end
  end

  @impl true
  def handle_cast({:chat_stream, message, timeout}, state) do
    topic = state.topic
    config = state.config
    session_id = state.session_id

    # ARCH-1 Fix: Use Task.Supervisor for monitored async streaming
    Task.Supervisor.start_child(JidoCode.TaskSupervisor, fn ->
      try do
        do_chat_stream_with_timeout(config, message, topic, timeout, session_id)
      catch
        :exit, {:timeout, _} ->
          Logger.warning("Stream timed out after #{timeout}ms")
          broadcast_stream_error(topic, :timeout)

        kind, reason ->
          Logger.error("Stream failed: #{kind} - #{inspect(reason)}")
          broadcast_stream_error(topic, {kind, reason})
      end
    end)

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Stop the AI agent if running - catch any errors silently
    if state[:ai_pid] && Process.alive?(state.ai_pid) do
      try do
        GenServer.stop(state.ai_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_config(opts) do
    config_result =
      case Config.get_llm_config() do
        {:ok, base_config} ->
          config = %{
            provider: Keyword.get(opts, :provider, base_config.provider),
            model: Keyword.get(opts, :model, base_config.model),
            temperature: Keyword.get(opts, :temperature, base_config.temperature),
            max_tokens: Keyword.get(opts, :max_tokens, base_config.max_tokens)
          }

          {:ok, config}

        {:error, _reason} = error ->
          # Allow starting with explicit opts even without base config
          if Keyword.has_key?(opts, :provider) and Keyword.has_key?(opts, :model) do
            config = %{
              provider: Keyword.fetch!(opts, :provider),
              model: Keyword.fetch!(opts, :model),
              temperature: Keyword.get(opts, :temperature, 0.7),
              max_tokens: Keyword.get(opts, :max_tokens, 4096)
            }

            {:ok, config}
          else
            error
          end
      end

    # Validate config before returning to ensure agents cannot start in invalid state
    case config_result do
      {:ok, config} ->
        case validate_config(config) do
          :ok -> {:ok, config}
          {:error, reason} -> {:error, reason}
        end

      error ->
        error
    end
  end

  defp start_ai_agent(config) do
    model_tuple =
      {config.provider,
       [
         model: config.model,
         temperature: config.temperature,
         max_tokens: config.max_tokens
       ]}

    case Model.from(model_tuple) do
      {:ok, model} ->
        AIAgent.start_link(
          ai: [
            model: model,
            prompt: @system_prompt
          ]
        )

      {:error, reason} ->
        {:error, {:model_error, reason}}
    end
  end

  defp do_chat(ai_pid, message) do
    case AIAgent.chat_response(ai_pid, message, timeout: @default_timeout) do
      {:ok, %{response: response}} when is_binary(response) ->
        {:ok, response}

      {:ok, response} when is_binary(response) ->
        {:ok, response}

      {:ok, %{} = result} ->
        # Handle other response formats
        response = Map.get(result, :response) || Map.get(result, :content) || inspect(result)
        {:ok, response}

      {:error, reason} ->
        Logger.error("LLM chat error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_topic(session_id) do
    PubSubTopics.llm_stream(session_id)
  end

  # Build tool execution context from session_id
  # Returns {:ok, context} or {:error, reason}
  defp do_build_tool_context(nil), do: {:error, :no_session_id}

  defp do_build_tool_context(session_id) when is_binary(session_id) do
    # Check if session_id looks like a PID string (e.g., "#PID<0.123.0>")
    # In that case, the agent was started without a proper session_id
    if String.starts_with?(session_id, "#PID<") do
      {:error, :no_session_id}
    else
      Executor.build_context(session_id)
    end
  end

  # Execute a single tool using the session context
  defp do_execute_tool(tool_call, %{session_id: session_id} = _state) do
    with {:ok, context} <- do_build_tool_context(session_id) do
      Executor.execute(tool_call, context: context)
    end
  end

  # Execute multiple tools using the session context
  defp do_execute_tool_batch(tool_calls, opts, %{session_id: session_id} = _state) do
    with {:ok, context} <- do_build_tool_context(session_id) do
      # Merge context into opts for execute_batch
      batch_opts = Keyword.put(opts, :context, context)
      Executor.execute_batch(tool_calls, batch_opts)
    end
  end

  defp broadcast_response(topic, response) do
    Phoenix.PubSub.broadcast(@pubsub, topic, {:agent_response, response})
  end

  # CQ-2 Fix: Standardize config_changed to 2-tuple format
  # Previously used 3-tuple {:config_changed, old_config, new_config}
  # Now uses 2-tuple {:config_changed, new_config} for consistency with commands.ex
  defp broadcast_config_change(topic, _old_config, new_config) do
    Phoenix.PubSub.broadcast(@pubsub, topic, {:config_changed, new_config})
  end

  defp broadcast_stream_chunk(topic, chunk, session_id) do
    # Update Session.State with chunk (skip if session_id is PID string)
    update_session_streaming(session_id, chunk)
    # Also broadcast for TUI (include session_id for routing)
    Phoenix.PubSub.broadcast(@pubsub, topic, {:stream_chunk, session_id, chunk})
  end

  defp broadcast_stream_end(topic, full_content, session_id) do
    # Finalize message in Session.State (skip if session_id is PID string)
    end_session_streaming(session_id)
    # Also broadcast for TUI (include session_id for routing)
    Phoenix.PubSub.broadcast(@pubsub, topic, {:stream_end, session_id, full_content})
  end

  defp broadcast_stream_error(topic, reason) do
    Phoenix.PubSub.broadcast(@pubsub, topic, {:stream_error, reason})
  end

  # Wrapper that enforces timeout on stream operations
  defp do_chat_stream_with_timeout(config, message, topic, timeout, session_id) do
    # Use a Task to enforce timeout on the entire streaming operation
    task =
      Task.async(fn ->
        do_chat_stream(config, message, topic, session_id)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, _result} ->
        :ok

      nil ->
        # Task was killed due to timeout
        Logger.warning("Streaming operation timed out after #{timeout}ms")
        broadcast_stream_error(topic, :timeout)
    end
  end

  defp do_chat_stream(config, message, topic, session_id) do
    # Build model from config
    model_tuple =
      {config.provider,
       [
         model: config.model,
         temperature: config.temperature,
         max_tokens: config.max_tokens
       ]}

    case Model.from(model_tuple) do
      {:ok, model} ->
        execute_stream(model, message, topic, session_id)

      {:error, reason} ->
        Logger.error("Failed to create model for streaming: #{inspect(reason)}")
        broadcast_stream_error(topic, {:model_error, reason})
    end
  end

  defp execute_stream(model, message, topic, session_id) do
    # Build prompt with system message and user message
    prompt =
      Prompt.new(%{
        messages: [
          %{role: :system, content: @system_prompt, engine: :none},
          %{role: :user, content: message, engine: :none}
        ]
      })

    # Generate a unique message ID for this streaming response
    message_id = "msg_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    # Start streaming in Session.State (skip if session_id is PID string)
    start_session_streaming(session_id, message_id)

    # Execute streaming chat completion
    case ChatCompletion.run(
           %{
             model: model,
             prompt: prompt,
             stream: true
           },
           %{}
         ) do
      {:ok, stream} ->
        process_stream(stream, topic, session_id)

      {:error, reason} ->
        Logger.error("Failed to start stream: #{inspect(reason)}")
        broadcast_stream_error(topic, reason)
    end
  end

  defp process_stream(stream, topic, session_id) do
    # Accumulate full content while streaming chunks
    full_content =
      Enum.reduce_while(stream, "", fn chunk, acc ->
        case extract_chunk_content(chunk) do
          {:ok, content} ->
            broadcast_stream_chunk(topic, content, session_id)
            {:cont, acc <> content}

          {:finish, content} ->
            # Last chunk with finish_reason
            if content != "" do
              broadcast_stream_chunk(topic, content, session_id)
            end

            {:halt, acc <> content}
        end
      end)

    # Broadcast stream completion and finalize in Session.State
    broadcast_stream_end(topic, full_content, session_id)
  rescue
    error ->
      Logger.error("Stream processing error: #{inspect(error)}")
      broadcast_stream_error(topic, error)
  end

  defp extract_chunk_content(%{content: content, finish_reason: nil}) do
    {:ok, content || ""}
  end

  defp extract_chunk_content(%{content: content, finish_reason: _reason}) do
    {:finish, content || ""}
  end

  defp extract_chunk_content(%{delta: %{content: content}} = chunk) do
    finish_reason = Map.get(chunk, :finish_reason)

    if finish_reason do
      {:finish, content || ""}
    else
      {:ok, content || ""}
    end
  end

  defp extract_chunk_content(chunk) when is_binary(chunk) do
    {:ok, chunk}
  end

  defp extract_chunk_content(chunk) do
    # Unknown chunk format - try to extract content
    content = Map.get(chunk, :content) || Map.get(chunk, "content") || ""
    {:ok, content}
  end

  defp stop_ai_agent(ai_pid) when is_pid(ai_pid) do
    if Process.alive?(ai_pid) do
      try do
        GenServer.stop(ai_pid, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end
  end

  defp stop_ai_agent(_), do: :ok

  defp apply_config_change(new_config, state) do
    case validate_config(new_config) do
      :ok ->
        stop_ai_agent(state.ai_pid)
        do_apply_config(new_config, state)

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  defp do_apply_config(new_config, state) do
    case start_ai_agent(new_config) do
      {:ok, new_ai_pid} ->
        old_config = state.config
        new_state = %{state | ai_pid: new_ai_pid, config: new_config}
        broadcast_config_change(state.topic, old_config, new_config)
        {:reply, :ok, new_state}

      {:error, reason} ->
        restore_old_config(reason, state)
    end
  end

  defp restore_old_config(reason, state) do
    case start_ai_agent(state.config) do
      {:ok, restored_pid} ->
        {:reply, {:error, "Failed to apply new config: #{inspect(reason)}"},
         %{state | ai_pid: restored_pid}}

      {:error, _} ->
        {:stop, {:error, :cannot_restore_agent}, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Session.State Streaming Helpers
  # ============================================================================

  # Start streaming in Session.State (skip if session_id is PID string)
  defp start_session_streaming(session_id, message_id) when is_binary(session_id) do
    if is_valid_session_id?(session_id) do
      SessionState.start_streaming(session_id, message_id)
    else
      :ok
    end
  end

  # Update streaming content in Session.State (skip if session_id is PID string)
  defp update_session_streaming(session_id, chunk) when is_binary(session_id) do
    if is_valid_session_id?(session_id) do
      SessionState.update_streaming(session_id, chunk)
    else
      :ok
    end
  end

  # End streaming in Session.State (skip if session_id is PID string)
  defp end_session_streaming(session_id) when is_binary(session_id) do
    if is_valid_session_id?(session_id) do
      SessionState.end_streaming(session_id)
    else
      :ok
    end
  end

  # Check if session_id is a valid session ID (not a PID string)
  defp is_valid_session_id?(session_id) when is_binary(session_id) do
    not String.starts_with?(session_id, "#PID<")
  end

  # ============================================================================
  # Validation Functions
  # ============================================================================

  defp validate_message(message) when byte_size(message) > @max_message_length do
    {:error,
     {:message_too_long,
      "Message exceeds maximum length of #{@max_message_length} characters (received #{byte_size(message)})"}}
  end

  defp validate_message(message) when byte_size(message) == 0 do
    {:error, {:empty_message, "Message cannot be empty"}}
  end

  defp validate_message(_message), do: :ok

  defp validate_config(config) do
    with :ok <- validate_provider(config.provider),
         :ok <- validate_model(config.provider, config.model) do
      validate_api_key(config.provider)
    end
  end

  defp validate_provider(provider) do
    case RegistryAdapter.list_providers() do
      {:ok, providers} ->
        if provider in providers do
          :ok
        else
          available =
            providers
            |> Enum.take(10)
            |> Enum.map_join(", ", &Atom.to_string/1)

          {:error,
           "Provider '#{provider}' not found. Available providers include: #{available}... (#{length(providers)} total)"}
        end

      {:error, :registry_unavailable} ->
        # Fall back to allowing any provider if registry unavailable
        Logger.warning("Provider registry unavailable, skipping provider validation")
        :ok

      {:error, reason} ->
        {:error, "Failed to validate provider: #{inspect(reason)}"}
    end
  end

  defp validate_model(provider, model) do
    if RegistryAdapter.model_exists?(provider, model) do
      :ok
    else
      {:error, model_not_found_error(provider, model)}
    end
  end

  defp model_not_found_error(provider, model) do
    case RegistryAdapter.list_models(provider) do
      {:ok, models} ->
        available =
          models
          |> Enum.take(5)
          |> Enum.map_join(", ", fn m -> Map.get(m, :model, "unknown") end)

        "Model '#{model}' not found for provider '#{provider}'. Available models include: #{available}..."

      {:error, _} ->
        "Model '#{model}' not found for provider '#{provider}'"
    end
  end

  defp validate_api_key(provider) do
    api_key_name = :"#{provider}_api_key"
    env_key = api_key_name |> Atom.to_string() |> String.upcase()

    # Check environment variable directly
    case System.get_env(env_key) do
      nil ->
        # Try Keyring as fallback
        try_keyring_validation(provider, api_key_name, env_key)

      "" ->
        {:error,
         "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

      _key ->
        :ok
    end
  end

  defp try_keyring_validation(provider, api_key_name, env_key) do
    case Keyring.get(api_key_name, nil) do
      nil ->
        {:error,
         "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}

      "" ->
        {:error,
         "API key for provider '#{provider}' is empty. Set #{env_key} environment variable."}

      _key ->
        :ok
    end
  rescue
    _ ->
      {:error,
       "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
  catch
    :exit, _ ->
      {:error,
       "No API key found for provider '#{provider}'. Set #{env_key} environment variable."}
  end
end
