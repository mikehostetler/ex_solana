defmodule JidoCode.Session.State do
  @moduledoc """
  Session State manages the runtime state for a session.

  This GenServer handles:
  - Conversation history (messages from user, assistant, system, tool)
  - Reasoning steps (chain-of-thought reasoning display)
  - Tool execution tracking (pending, running, completed tool calls)
  - Todo list management (task tracking)
  - UI state (scroll offset, streaming state)

  ## Registry

  Each State process registers in `JidoCode.SessionProcessRegistry` with the key
  `{:state, session_id}` for O(1) lookup.

  ## State Structure

  The state contains:

  - `session` - The Session struct (for backwards compatibility)
  - `session_id` - The unique session identifier
  - `messages` - List of conversation messages
  - `reasoning_steps` - List of chain-of-thought reasoning steps
  - `tool_calls` - List of tool call records
  - `todos` - List of task items
  - `scroll_offset` - Current scroll position in UI
  - `streaming_message` - Content being streamed (nil when not streaming)
  - `is_streaming` - Whether currently receiving streaming response

  ## Usage

  Typically started as a child of Session.Supervisor:

      # In Session.Supervisor.init/1
      children = [
        {JidoCode.Session.State, session: session},
        # ...
      ]

  Direct lookup:

      [{pid, _}] = Registry.lookup(SessionProcessRegistry, {:state, session_id})

  Access via client functions:

      {:ok, state} = Session.State.get_state(session_id)
  """

  use GenServer

  require Logger

  alias JidoCode.Session
  alias JidoCode.Session.ProcessRegistry

  # ============================================================================
  # Configuration
  # ============================================================================

  # Maximum list sizes to prevent unbounded memory growth
  @max_messages 1000
  @max_reasoning_steps 100
  @max_tool_calls 500

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc """
  A conversation message.

  - `id` - Unique message identifier
  - `role` - Who sent the message (:user, :assistant, :system, :tool)
  - `content` - The message content
  - `timestamp` - When the message was created
  """
  @type message :: %{
          id: String.t(),
          role: :user | :assistant | :system | :tool,
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  A reasoning step from chain-of-thought processing.

  - `id` - Unique step identifier
  - `content` - The reasoning content
  - `timestamp` - When the step was generated
  """
  @type reasoning_step :: %{
          id: String.t(),
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc """
  A tool call record.

  - `id` - Unique tool call identifier (from LLM)
  - `name` - Name of the tool being called
  - `arguments` - Arguments passed to the tool
  - `result` - Result of the tool execution (nil if not yet complete)
  - `status` - Current status of the tool call
  - `timestamp` - When the tool call was initiated
  """
  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          result: term() | nil,
          status: :pending | :running | :completed | :error,
          timestamp: DateTime.t()
        }

  @typedoc """
  A todo/task item.

  - `id` - Unique todo identifier
  - `content` - Description of the task
  - `status` - Current status (:pending, :in_progress, :completed)
  """
  @type todo :: %{
          id: String.t(),
          content: String.t(),
          status: :pending | :in_progress | :completed
        }

  @typedoc """
  Session State process state.

  - `session` - The Session struct (for backwards compatibility with get_session/1)
  - `session_id` - The unique session identifier
  - `messages` - List of conversation messages in chronological order
  - `reasoning_steps` - List of reasoning steps from current response
  - `tool_calls` - List of tool calls from current response
  - `todos` - List of task items being tracked
  - `scroll_offset` - Current scroll position in UI (lines from bottom)
  - `streaming_message` - Content being streamed (nil when not streaming)
  - `streaming_message_id` - ID of the message being streamed (nil when not streaming)
  - `is_streaming` - Whether currently receiving a streaming response
  """
  @type state :: %{
          session: Session.t(),
          session_id: String.t(),
          messages: [message()],
          reasoning_steps: [reasoning_step()],
          tool_calls: [tool_call()],
          todos: [todo()],
          scroll_offset: non_neg_integer(),
          streaming_message: String.t() | nil,
          streaming_message_id: String.t() | nil,
          is_streaming: boolean()
        }

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Session State process.

  ## Options

  - `:session` - (required) The `Session` struct for this session

  ## Returns

  - `{:ok, pid}` - State process started successfully
  - `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session, name: ProcessRegistry.via(:state, session.id))
  end

  @doc """
  Returns the child specification for this GenServer.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    session = Keyword.fetch!(opts, :session)

    %{
      id: {:session_state, session.id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Gets the session struct for this state process.

  ## Examples

      iex> {:ok, session} = State.get_session(pid)
  """
  @spec get_session(GenServer.server()) :: {:ok, Session.t()}
  def get_session(server) do
    GenServer.call(server, :get_session)
  end

  @doc """
  Gets the full state for a session by session_id.

  ## Examples

      iex> {:ok, state} = State.get_state("session-123")
      iex> {:error, :not_found} = State.get_state("unknown")
  """
  @spec get_state(String.t()) :: {:ok, state()} | {:error, :not_found}
  def get_state(session_id) do
    call_state(session_id, :get_state)
  end

  @doc """
  Gets the messages list for a session by session_id.

  Returns all messages in chronological order (oldest first).

  ## Examples

      iex> {:ok, messages} = State.get_messages("session-123")
      iex> {:error, :not_found} = State.get_messages("unknown")
  """
  @spec get_messages(String.t()) :: {:ok, [message()]} | {:error, :not_found}
  def get_messages(session_id) do
    call_state(session_id, :get_messages)
  end

  @doc """
  Gets a paginated slice of messages for a session by session_id.

  This is more efficient than `get_messages/1` for large conversation histories,
  as it only reverses the requested slice instead of the entire list.

  ## Parameters

  - `session_id` - The session identifier
  - `offset` - Number of messages to skip from the start (oldest messages)
  - `limit` - Maximum number of messages to return (or `:all` for no limit)

  ## Returns

  - `{:ok, messages, metadata}` - Successfully retrieved messages with pagination info
  - `{:error, :not_found}` - Session not found

  The metadata map contains:
  - `total` - Total number of messages in the session
  - `offset` - The offset used for this query
  - `limit` - The limit used for this query
  - `returned` - Number of messages actually returned
  - `has_more` - Whether there are more messages beyond this page

  ## Examples

      # Get first 10 messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 0, 10)
      iex> meta.total
      100
      iex> meta.has_more
      true

      # Get next 10 messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 10, 10)
      iex> length(messages)
      10

      # Get all remaining messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 20, :all)
      iex> meta.has_more
      false

      # Offset beyond available messages
      iex> {:ok, messages, meta} = State.get_messages("session-123", 1000, 10)
      iex> messages
      []
      iex> meta.has_more
      false
  """
  @spec get_messages(String.t(), non_neg_integer(), pos_integer() | :all) ::
          {:ok, [message()], map()} | {:error, :not_found}
  def get_messages(session_id, offset, limit)
      when is_binary(session_id) and is_integer(offset) and offset >= 0 and
             ((is_integer(limit) and limit > 0) or limit == :all) do
    call_state(session_id, {:get_messages_paginated, offset, limit})
  end

  @doc """
  Gets the reasoning steps list for a session by session_id.

  ## Examples

      iex> {:ok, steps} = State.get_reasoning_steps("session-123")
      iex> {:error, :not_found} = State.get_reasoning_steps("unknown")
  """
  @spec get_reasoning_steps(String.t()) :: {:ok, [reasoning_step()]} | {:error, :not_found}
  def get_reasoning_steps(session_id) do
    call_state(session_id, :get_reasoning_steps)
  end

  @doc """
  Gets the todos list for a session by session_id.

  ## Examples

      iex> {:ok, todos} = State.get_todos("session-123")
      iex> {:error, :not_found} = State.get_todos("unknown")
  """
  @spec get_todos(String.t()) :: {:ok, [todo()]} | {:error, :not_found}
  def get_todos(session_id) do
    call_state(session_id, :get_todos)
  end

  @doc """
  Gets the tool calls list for a session by session_id.

  ## Examples

      iex> {:ok, tool_calls} = State.get_tool_calls("session-123")
      iex> {:error, :not_found} = State.get_tool_calls("unknown")
  """
  @spec get_tool_calls(String.t()) :: {:ok, [tool_call()]} | {:error, :not_found}
  def get_tool_calls(session_id) do
    call_state(session_id, :get_tool_calls)
  end

  @doc """
  Appends a message to the conversation history.

  ## Examples

      iex> message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.append_message("session-123", message)
      iex> {:error, :not_found} = State.append_message("unknown", message)
  """
  @spec append_message(String.t(), message()) :: {:ok, state()} | {:error, :not_found}
  def append_message(session_id, message)
      when is_binary(session_id) and is_map(message) do
    call_state(session_id, {:append_message, message})
  end

  @doc """
  Clears all messages from the conversation history.

  ## Examples

      iex> {:ok, []} = State.clear_messages("session-123")
      iex> {:error, :not_found} = State.clear_messages("unknown")
  """
  @spec clear_messages(String.t()) :: {:ok, []} | {:error, :not_found}
  def clear_messages(session_id) do
    call_state(session_id, :clear_messages)
  end

  @doc """
  Starts streaming mode for a new message.

  Sets `is_streaming: true`, `streaming_message: ""`, and stores the message_id.

  ## Examples

      iex> {:ok, state} = State.start_streaming("session-123", "msg-1")
      iex> state.is_streaming
      true
      iex> {:error, :not_found} = State.start_streaming("unknown", "msg-1")
  """
  @spec start_streaming(String.t(), String.t()) :: {:ok, state()} | {:error, :not_found}
  def start_streaming(session_id, message_id)
      when is_binary(session_id) and is_binary(message_id) do
    call_state(session_id, {:start_streaming, message_id})
  end

  @doc """
  Appends a chunk to the streaming message.

  This is an async operation (cast) for performance during high-frequency updates.
  If the session is not found or not streaming, the chunk is silently ignored.

  ## Race Condition Note

  Because `start_streaming/2` uses `call` (synchronous) and `update_streaming/2`
  uses `cast` (asynchronous), there is a potential race condition where chunks
  could arrive before `start_streaming/2` completes. In this case, chunks are
  safely ignored. Callers should ensure `start_streaming/2` has returned before
  sending chunks to avoid lost data.

  ## Examples

      iex> :ok = State.update_streaming("session-123", "Hello ")
      iex> :ok = State.update_streaming("session-123", "world!")
  """
  @spec update_streaming(String.t(), String.t()) :: :ok
  def update_streaming(session_id, chunk)
      when is_binary(session_id) and is_binary(chunk) do
    cast_state(session_id, {:streaming_chunk, chunk})
  end

  @doc """
  Ends streaming and finalizes the message.

  Creates a message from the streamed content and appends it to the messages list.
  Resets streaming state to nil/false.

  ## Examples

      iex> {:ok, message} = State.end_streaming("session-123")
      iex> message.role
      :assistant
      iex> {:error, :not_streaming} = State.end_streaming("session-123")
      iex> {:error, :not_found} = State.end_streaming("unknown")
  """
  @spec end_streaming(String.t()) :: {:ok, message()} | {:error, :not_found | :not_streaming}
  def end_streaming(session_id) do
    call_state(session_id, :end_streaming)
  end

  @doc """
  Sets the scroll offset for the UI.

  ## Examples

      iex> {:ok, state} = State.set_scroll_offset("session-123", 10)
      iex> state.scroll_offset
      10
      iex> {:error, :not_found} = State.set_scroll_offset("unknown", 10)
  """
  @spec set_scroll_offset(String.t(), non_neg_integer()) :: {:ok, state()} | {:error, :not_found}
  def set_scroll_offset(session_id, offset)
      when is_binary(session_id) and is_integer(offset) and offset >= 0 do
    call_state(session_id, {:set_scroll_offset, offset})
  end

  @doc """
  Updates the entire todo list.

  ## Examples

      iex> todos = [%{id: "t-1", content: "Task 1", status: :pending}]
      iex> {:ok, state} = State.update_todos("session-123", todos)
      iex> {:error, :not_found} = State.update_todos("unknown", todos)
  """
  @spec update_todos(String.t(), [todo()]) :: {:ok, state()} | {:error, :not_found}
  def update_todos(session_id, todos)
      when is_binary(session_id) and is_list(todos) do
    call_state(session_id, {:update_todos, todos})
  end

  @doc """
  Adds a reasoning step to the list.

  ## Examples

      iex> step = %{id: "r-1", content: "Thinking...", timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.add_reasoning_step("session-123", step)
      iex> {:error, :not_found} = State.add_reasoning_step("unknown", step)
  """
  @spec add_reasoning_step(String.t(), reasoning_step()) :: {:ok, state()} | {:error, :not_found}
  def add_reasoning_step(session_id, step)
      when is_binary(session_id) and is_map(step) do
    call_state(session_id, {:add_reasoning_step, step})
  end

  @doc """
  Clears all reasoning steps.

  ## Examples

      iex> {:ok, []} = State.clear_reasoning_steps("session-123")
      iex> {:error, :not_found} = State.clear_reasoning_steps("unknown")
  """
  @spec clear_reasoning_steps(String.t()) :: {:ok, []} | {:error, :not_found}
  def clear_reasoning_steps(session_id) do
    call_state(session_id, :clear_reasoning_steps)
  end

  @doc """
  Adds a tool call to the list.

  ## Examples

      iex> tool_call = %{id: "tc-1", name: "read_file", arguments: %{}, result: nil, status: :pending, timestamp: DateTime.utc_now()}
      iex> {:ok, state} = State.add_tool_call("session-123", tool_call)
      iex> {:error, :not_found} = State.add_tool_call("unknown", tool_call)
  """
  @spec add_tool_call(String.t(), tool_call()) :: {:ok, state()} | {:error, :not_found}
  def add_tool_call(session_id, tool_call)
      when is_binary(session_id) and is_map(tool_call) do
    call_state(session_id, {:add_tool_call, tool_call})
  end

  @doc """
  Updates the session's LLM configuration.

  This merges the provided config with the existing session config using
  `Session.update_config/2`, which validates the config and updates the
  `updated_at` timestamp.

  ## Parameters

  - `session_id` - The session identifier
  - `config` - Map of config options to merge (provider, model, temperature, max_tokens)

  ## Returns

  - `{:ok, session}` - Successfully updated session
  - `{:error, :not_found}` - Session not found
  - `{:error, [reasons]}` - Config validation errors

  ## Examples

      iex> {:ok, session} = State.update_session_config("session-123", %{temperature: 0.5})
      iex> session.config.temperature
      0.5

      iex> {:error, :not_found} = State.update_session_config("unknown", %{temperature: 0.5})
  """
  @spec update_session_config(String.t(), map()) ::
          {:ok, Session.t()} | {:error, :not_found | [atom()]}
  def update_session_config(session_id, config)
      when is_binary(session_id) and is_map(config) do
    call_state(session_id, {:update_session_config, config})
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec call_state(String.t(), atom() | tuple()) :: {:ok, term()} | {:error, :not_found}
  defp call_state(session_id, message) do
    ProcessRegistry.call(:state, session_id, message)
  end

  @spec cast_state(String.t(), term()) :: :ok
  defp cast_state(session_id, message) do
    ProcessRegistry.cast(:state, session_id, message)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(%Session{} = session) do
    Logger.info("Starting Session.State for session #{session.id}")

    state = %{
      session: session,
      session_id: session.id,
      messages: [],
      reasoning_steps: [],
      tool_calls: [],
      todos: [],
      scroll_offset: 0,
      streaming_message: nil,
      streaming_message_id: nil,
      is_streaming: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_session, _from, state) do
    {:reply, {:ok, state.session}, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    # Messages stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.messages)}, state}
  end

  @impl true
  def handle_call({:get_messages_paginated, offset, limit}, _from, state) do
    # Performance optimization: only reverse the requested slice
    # Messages stored in reverse chronological order: [newest, ..., oldest]
    # We want to return in chronological order: [oldest, ..., newest]

    total = length(state.messages)

    # Calculate actual limit (handle :all)
    actual_limit = if limit == :all, do: total, else: limit

    # Calculate slice indices in the reverse-stored list
    # For offset=0, limit=10 with 100 messages:
    #   We want chronological indices 0-9 (msg_1 to msg_10)
    #   In reverse list, these are at indices 90-99
    #   start_index = 100 - 0 - 10 = 90
    start_index = max(0, total - offset - actual_limit)

    # Calculate how many messages we can actually return
    # If offset >= total, this will be 0 (no messages available)
    slice_length = min(actual_limit, max(0, total - offset))

    # Take the slice and reverse it to chronological order
    # This is O(slice_length) instead of O(total)
    messages =
      if slice_length > 0 do
        state.messages
        |> Enum.slice(start_index, slice_length)
        |> Enum.reverse()
      else
        []
      end

    # Build pagination metadata
    metadata = %{
      total: total,
      offset: offset,
      limit: actual_limit,
      returned: length(messages),
      has_more: offset + length(messages) < total
    }

    {:reply, {:ok, messages, metadata}, state}
  end

  @impl true
  def handle_call(:get_reasoning_steps, _from, state) do
    # Reasoning steps stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.reasoning_steps)}, state}
  end

  @impl true
  def handle_call(:get_todos, _from, state) do
    {:reply, {:ok, state.todos}, state}
  end

  @impl true
  def handle_call({:append_message, message}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    messages = [message | state.messages] |> Enum.take(@max_messages)
    new_state = %{state | messages: messages}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:clear_messages, _from, state) do
    new_state = %{state | messages: []}
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:start_streaming, message_id}, _from, state) do
    new_state = %{
      state
      | is_streaming: true,
        streaming_message: "",
        streaming_message_id: message_id
    }

    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:end_streaming, _from, state) do
    if state.is_streaming do
      message = %{
        id: state.streaming_message_id,
        role: :assistant,
        content: state.streaming_message,
        timestamp: DateTime.utc_now()
      }

      # Prepend for O(1), will be reversed on read
      new_state = %{
        state
        | messages: [message | state.messages],
          is_streaming: false,
          streaming_message: nil,
          streaming_message_id: nil
      }

      {:reply, {:ok, message}, new_state}
    else
      {:reply, {:error, :not_streaming}, state}
    end
  end

  @impl true
  def handle_call({:set_scroll_offset, offset}, _from, state) do
    new_state = %{state | scroll_offset: offset}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:update_todos, todos}, _from, state) do
    new_state = %{state | todos: todos}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call({:add_reasoning_step, step}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    reasoning_steps = [step | state.reasoning_steps] |> Enum.take(@max_reasoning_steps)
    new_state = %{state | reasoning_steps: reasoning_steps}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:clear_reasoning_steps, _from, state) do
    new_state = %{state | reasoning_steps: []}
    {:reply, {:ok, []}, new_state}
  end

  @impl true
  def handle_call({:add_tool_call, tool_call}, _from, state) do
    # Prepend for O(1), will be reversed on read
    # Enforce max size limit, evicting oldest items (at end of reversed list)
    tool_calls = [tool_call | state.tool_calls] |> Enum.take(@max_tool_calls)
    new_state = %{state | tool_calls: tool_calls}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:get_tool_calls, _from, state) do
    # Tool calls stored in reverse order for O(1) prepend, reverse on read
    {:reply, {:ok, Enum.reverse(state.tool_calls)}, state}
  end

  @impl true
  def handle_call({:update_session_config, config}, _from, state) do
    case Session.update_config(state.session, config) do
      {:ok, updated_session} ->
        new_state = %{state | session: updated_session}
        {:reply, {:ok, updated_session}, new_state}

      {:error, reasons} ->
        {:reply, {:error, reasons}, state}
    end
  end

  # ============================================================================
  # handle_cast Callbacks
  # ============================================================================

  @impl true
  def handle_cast({:streaming_chunk, chunk}, state) do
    if state.is_streaming do
      new_state = %{state | streaming_message: state.streaming_message <> chunk}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # ============================================================================
  # handle_info Callbacks
  # ============================================================================

  @impl true
  def handle_info(msg, state) do
    Logger.warning(
      "Session.State #{state.session_id} received unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  # ============================================================================
  # terminate Callback
  # ============================================================================

  @impl true
  def terminate(reason, state) do
    Logger.debug("Session.State #{state.session_id} terminating: #{inspect(reason)}")
    :ok
  end
end
