defmodule JidoCode.Tools.Executor do
  @moduledoc """
  Coordinates tool execution from LLM tool calls.

  This module handles the flow from parsing LLM tool call responses to
  executing tools and formatting results. It validates tool calls against
  the registry, delegates execution to a configurable executor function,
  and handles timeouts gracefully.

  ## Execution Flow

  1. Parse tool calls from LLM response JSON
  2. Validate each tool exists in the Registry
  3. Validate parameters against the tool's schema
  4. Delegate execution to the configured executor function
  5. Handle timeouts and format results for LLM consumption

  ## Session Context

  Tool execution requires a session context that includes:

  - `:session_id` - Session identifier for security boundary enforcement
  - `:project_root` - Project root path (auto-populated from Session.Manager)
  - `:timeout` - Optional timeout override

  Use `build_context/2` to create a context from a session ID:

      {:ok, context} = Executor.build_context(session_id)
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

  ## Usage

      # Build context from session ID
      {:ok, context} = Executor.build_context(session_id)

      # Parse and execute tool calls from LLM response
      {:ok, tool_calls} = Executor.parse_tool_calls(llm_response)
      {:ok, results} = Executor.execute_batch(tool_calls, context: context)

      # Convert results to LLM messages
      messages = Result.to_llm_messages(results)

  ## Executor Function

  The executor function is called to actually run the tool. By default,
  it calls the handler module's `execute/2` function directly. You can
  provide a custom executor to route through a sandbox:

      Executor.execute(tool_call, executor: fn tool, args, context ->
        SandboxManager.execute(tool.name, args, context)
      end)

  ## Options

  - `:executor` - Function `(tool, args, context) -> {:ok, result} | {:error, reason}`
  - `:timeout` - Execution timeout in milliseconds (default: 30_000)
  - `:context` - Execution context with session_id and project_root
  - `:session_id` - (deprecated) Use context.session_id instead

  ## PubSub Events

  When a session_id is provided in context, the executor broadcasts events to the
  `"tui.events.{session_id}"` topic. Without a session_id, events go to
  `"tui.events"`.

  Events broadcast:
  - `{:tool_call, tool_name, params, call_id, session_id}` - When tool execution starts
  - `{:tool_result, result, session_id}` - When tool execution completes (Result struct)

  The session_id in the payload allows consumers on the global topic to identify
  which session the event originated from. The session_id may be nil if no session
  context was provided.
  """

  require Logger

  alias JidoCode.PubSubHelpers
  alias JidoCode.Session
  alias JidoCode.Tools.{Registry, Result, Tool}
  alias JidoCode.Utils.UUID, as: UUIDUtils

  @default_timeout 30_000

  @typedoc """
  A parsed tool call from an LLM response.
  """
  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @typedoc """
  Execution context passed to tool handlers.

  ## Required Fields

  - `:session_id` - Session identifier for security boundary enforcement

  ## Auto-populated Fields

  - `:project_root` - Project root path (fetched from Session.Manager if not provided)

  ## Optional Fields

  - `:timeout` - Execution timeout override in milliseconds

  ## Usage

  Use `build_context/2` to create a context from a session ID:

      {:ok, context} = Executor.build_context(session_id)

  Or create manually:

      context = %{session_id: session_id, project_root: "/path/to/project"}
  """
  @type context :: %{
          required(:session_id) => String.t(),
          optional(:project_root) => String.t(),
          optional(:timeout) => pos_integer()
        }

  @typedoc """
  Options for tool execution.
  """
  @type execute_opts :: [
          executor: (Tool.t(), map(), context() -> {:ok, term()} | {:error, term()}),
          timeout: pos_integer(),
          context: context(),
          session_id: String.t() | nil
        ]

  # ============================================================================
  # Parsing
  # ============================================================================

  @doc """
  Parses tool calls from an LLM response.

  Extracts tool calls from OpenAI-format responses. The response can be:
  - A map with a "tool_calls" key
  - A map with an "assistant" message containing tool_calls
  - A list of tool call objects directly

  ## Returns

  - `{:ok, [tool_call]}` - List of parsed tool calls
  - `{:error, :no_tool_calls}` - No tool calls found in response
  - `{:error, {:invalid_tool_call, reason}}` - Malformed tool call

  ## Examples

      # From assistant message
      response = %{
        "tool_calls" => [
          %{
            "id" => "call_123",
            "type" => "function",
            "function" => %{
              "name" => "read_file",
              "arguments" => "{\\"path\\": \\"/src/main.ex\\"}"
            }
          }
        ]
      }
      {:ok, [%{id: "call_123", name: "read_file", arguments: %{"path" => "/src/main.ex"}}]}
        = Executor.parse_tool_calls(response)
  """
  @spec parse_tool_calls(map() | list()) :: {:ok, [tool_call()]} | {:error, term()}
  def parse_tool_calls(response) when is_map(response) do
    cond do
      # Direct tool_calls key
      Map.has_key?(response, "tool_calls") ->
        parse_tool_call_list(response["tool_calls"])

      # Atom key variant
      Map.has_key?(response, :tool_calls) ->
        parse_tool_call_list(response.tool_calls)

      # Nested in choices (full API response)
      Map.has_key?(response, "choices") ->
        parse_from_choices(response["choices"])

      true ->
        {:error, :no_tool_calls}
    end
  end

  def parse_tool_calls(tool_calls) when is_list(tool_calls) do
    parse_tool_call_list(tool_calls)
  end

  def parse_tool_calls(_), do: {:error, :no_tool_calls}

  # ============================================================================
  # Context Building
  # ============================================================================

  @doc """
  Builds an execution context from a session ID.

  Fetches the project_root from Session.Manager and constructs a complete
  context map suitable for tool execution. Tool handlers use this context
  for security boundary enforcement.

  ## Parameters

  - `session_id` - The session identifier (must be a valid UUID)
  - `opts` - Optional keyword list

  ## Options

  - `:timeout` - Execution timeout in milliseconds (default: #{@default_timeout})

  ## Returns

  - `{:ok, context}` - Complete context with session_id and project_root
  - `{:error, :not_found}` - Session not found in Registry
  - `{:error, :invalid_session_id}` - Invalid session ID format

  ## Examples

      # Build context for a session
      {:ok, context} = Executor.build_context("550e8400-e29b-41d4-a716-446655440000")
      # => {:ok, %{session_id: "550e8400-...", project_root: "/path/to/project", timeout: 30000}}

      # With custom timeout
      {:ok, context} = Executor.build_context(session_id, timeout: 60_000)

      # Invalid session
      {:error, :not_found} = Executor.build_context("unknown-session-id")
  """
  @spec build_context(String.t(), keyword()) ::
          {:ok, context()} | {:error, :not_found | :invalid_session_id}
  def build_context(session_id, opts \\ []) when is_binary(session_id) do
    # Validate UUID format for defense-in-depth
    if valid_uuid?(session_id) do
      timeout = Keyword.get(opts, :timeout, @default_timeout)
      base_context = %{session_id: session_id, timeout: timeout}

      # Delegate to enrich_context to avoid duplication
      enrich_context(base_context)
    else
      {:error, :invalid_session_id}
    end
  end

  @doc """
  Enriches an existing context with project_root from Session.Manager.

  If the context already has a project_root, it is returned unchanged.
  If the context has a session_id but no project_root, the project_root
  is fetched from Session.Manager.

  ## Parameters

  - `context` - Existing context map (may be empty or partial)

  ## Returns

  - `{:ok, enriched_context}` - Context with project_root populated
  - `{:error, :missing_session_id}` - No session_id in context
  - `{:error, :not_found}` - Session not found

  ## Examples

      # Enrich context with just session_id
      {:ok, enriched} = Executor.enrich_context(%{session_id: "abc123"})

      # Context already complete - returned unchanged
      {:ok, same} = Executor.enrich_context(%{session_id: "abc", project_root: "/path"})
  """
  @spec enrich_context(map()) :: {:ok, map()} | {:error, :missing_session_id | :not_found}
  def enrich_context(%{session_id: session_id, project_root: _} = context)
      when is_binary(session_id) do
    {:ok, context}
  end

  def enrich_context(%{session_id: session_id} = context) when is_binary(session_id) do
    case Session.Manager.project_root(session_id) do
      {:ok, project_root} ->
        {:ok, Map.put(context, :project_root, project_root)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def enrich_context(%{} = _context) do
    {:error, :missing_session_id}
  end

  # ============================================================================
  # Single Execution
  # ============================================================================

  @doc """
  Executes a single tool call.

  Validates the tool exists and parameters are valid, then delegates
  execution to the configured executor function.

  ## Parameters

  - `tool_call` - Parsed tool call map with :id, :name, :arguments
  - `opts` - Execution options

  ## Options

  - `:executor` - Custom executor function (default: calls handler directly)
  - `:timeout` - Execution timeout in ms (default: 30000)
  - `:context` - Execution context with session_id and project_root

  ## Context

  The context should include:
  - `:session_id` - Session identifier for security boundaries
  - `:project_root` - Project root path (auto-populated from Session.Manager if not provided)

  Use `build_context/2` to create a context:

      {:ok, context} = Executor.build_context(session_id)
      {:ok, result} = Executor.execute(tool_call, context: context)

  ## Returns

  - `{:ok, %Result{}}` - Execution result
  - `{:error, reason}` - Validation or execution failure

  ## Examples

      # With session context (recommended)
      {:ok, context} = Executor.build_context(session_id)
      {:ok, result} = Executor.execute(tool_call, context: context)

      # Legacy usage (deprecated - will log warning)
      {:ok, result} = Executor.execute(tool_call, session_id: session_id)
  """
  @spec execute(tool_call() | map(), execute_opts()) :: {:ok, Result.t()} | {:error, term()}
  def execute(tool_call, opts \\ [])

  def execute(%{id: id, name: name, arguments: args} = _tool_call, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    context = Keyword.get(opts, :context, %{})
    executor = Keyword.get(opts, :executor, &default_executor/3)

    # Support legacy :session_id option (deprecated)
    legacy_session_id = Keyword.get(opts, :session_id)

    # Determine session_id: prefer context.session_id, fall back to legacy option
    session_id = get_session_id(context, legacy_session_id)

    # Enrich context with project_root if session_id present but project_root missing
    enriched_context = maybe_enrich_context(context, session_id)

    start_time = System.monotonic_time(:millisecond)

    with {:ok, tool} <- validate_tool_exists(name),
         :ok <- validate_arguments(tool, args) do
      # Broadcast tool call start
      broadcast_tool_call(session_id, name, args, id)

      result =
        execute_with_timeout(
          id,
          name,
          tool,
          args,
          enriched_context,
          executor,
          timeout,
          start_time
        )

      # Broadcast tool result
      case result do
        {:ok, tool_result} -> broadcast_tool_result(session_id, tool_result)
        _ -> :ok
      end

      result
    else
      {:error, :not_found} ->
        duration = System.monotonic_time(:millisecond) - start_time
        error_result = Result.error(id, name, "Tool '#{name}' not found", duration)
        broadcast_tool_result(session_id, error_result)
        {:ok, error_result}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        error_result = Result.error(id, name, reason, duration)
        broadcast_tool_result(session_id, error_result)
        {:ok, error_result}
    end
  end

  # Handle string-keyed maps (from JSON parsing)
  def execute(%{"id" => id, "name" => name, "arguments" => args}, opts) do
    execute(%{id: id, name: name, arguments: args}, opts)
  end

  # ============================================================================
  # Batch Execution
  # ============================================================================

  @doc """
  Executes multiple tool calls.

  By default, executes tool calls sequentially. Use `parallel: true` option
  to execute in parallel (when tools don't depend on each other).

  ## Parameters

  - `tool_calls` - List of parsed tool call maps
  - `opts` - Execution options (same as `execute/2` plus `:parallel`)

  ## Options

  - `:parallel` - Execute in parallel (default: false)
  - All options from `execute/2`

  ## Returns

  - `{:ok, [%Result{}]}` - List of results in same order as input
  - `{:error, reason}` - If batch execution fails

  ## Examples

      tool_calls = [
        %{id: "call_1", name: "read_file", arguments: %{"path" => "/a.txt"}},
        %{id: "call_2", name: "read_file", arguments: %{"path" => "/b.txt"}}
      ]
      {:ok, results} = Executor.execute_batch(tool_calls, parallel: true)
  """
  @spec execute_batch([tool_call()], execute_opts()) :: {:ok, [Result.t()]} | {:error, term()}
  def execute_batch(tool_calls, opts \\ []) when is_list(tool_calls) do
    parallel = Keyword.get(opts, :parallel, false)
    exec_opts = Keyword.delete(opts, :parallel)

    results =
      if parallel do
        execute_parallel(tool_calls, exec_opts)
      else
        execute_sequential(tool_calls, exec_opts)
      end

    {:ok, results}
  end

  # ============================================================================
  # Validation Helpers
  # ============================================================================

  @doc """
  Validates that a tool exists in the registry.

  ## Returns

  - `{:ok, tool}` - Tool found
  - `{:error, :not_found}` - Tool not registered
  """
  @spec validate_tool_exists(String.t()) :: {:ok, Tool.t()} | {:error, :not_found}
  def validate_tool_exists(name) do
    Registry.get(name)
  end

  @doc """
  Validates arguments against a tool's parameter schema.

  ## Returns

  - `:ok` - Arguments valid
  - `{:error, reason}` - Validation failure
  """
  @spec validate_arguments(Tool.t(), map()) :: :ok | {:error, String.t()}
  def validate_arguments(tool, args) do
    Tool.validate_args(tool, args)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Validate UUID v4 format
  defp valid_uuid?(session_id) do
    UUIDUtils.valid?(session_id)
  end

  # Extract session_id from context or legacy option
  defp get_session_id(%{session_id: session_id}, _legacy) when is_binary(session_id) do
    session_id
  end

  defp get_session_id(_context, legacy_session_id) when is_binary(legacy_session_id) do
    # Log deprecation warning for legacy usage (suppressible for tests)
    unless Application.get_env(:jido_code, :suppress_executor_deprecation_warnings, false) do
      Logger.warning(
        "Executor: Using :session_id option is deprecated. " <>
          "Use context: %{session_id: id} instead."
      )
    end

    legacy_session_id
  end

  defp get_session_id(_context, _legacy), do: nil

  # Enrich context with project_root if missing but session_id present
  defp maybe_enrich_context(%{project_root: _} = context, _session_id), do: context

  defp maybe_enrich_context(context, session_id) when is_binary(session_id) do
    case Session.Manager.project_root(session_id) do
      {:ok, project_root} ->
        context
        |> Map.put(:session_id, session_id)
        |> Map.put(:project_root, project_root)

      {:error, reason} ->
        # Session not found - return context unchanged (don't add invalid session_id)
        Logger.warning(
          "Executor: Failed to enrich context for session #{session_id}: #{inspect(reason)}"
        )

        context
    end
  end

  defp maybe_enrich_context(context, _session_id), do: context

  defp parse_tool_call_list(nil), do: {:error, :no_tool_calls}
  defp parse_tool_call_list([]), do: {:error, :no_tool_calls}

  defp parse_tool_call_list(tool_calls) when is_list(tool_calls) do
    results = Enum.map(tool_calls, &parse_single_tool_call/1)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil ->
        {:ok, Enum.map(results, fn {:ok, tc} -> tc end)}

      {:error, reason} ->
        {:error, {:invalid_tool_call, reason}}
    end
  end

  defp parse_single_tool_call(%{"id" => id, "type" => "function", "function" => func}) do
    parse_function_call(id, func)
  end

  defp parse_single_tool_call(%{id: id, type: "function", function: func}) do
    parse_function_call(id, func)
  end

  # Handle direct format without type wrapper
  defp parse_single_tool_call(%{"id" => id, "name" => name, "arguments" => args}) do
    parse_arguments(id, name, args)
  end

  defp parse_single_tool_call(%{id: id, name: name, arguments: args}) do
    parse_arguments(id, name, args)
  end

  defp parse_single_tool_call(other) do
    {:error, "invalid tool call format: #{inspect(other)}"}
  end

  defp parse_function_call(id, %{"name" => name, "arguments" => args}) do
    parse_arguments(id, name, args)
  end

  defp parse_function_call(id, %{name: name, arguments: args}) do
    parse_arguments(id, name, args)
  end

  defp parse_function_call(_id, other) do
    {:error, "invalid function format: #{inspect(other)}"}
  end

  defp parse_arguments(id, name, args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> {:ok, %{id: id, name: name, arguments: parsed}}
      {:error, _} -> {:error, "invalid JSON in arguments: #{args}"}
    end
  end

  defp parse_arguments(id, name, args) when is_map(args) do
    {:ok, %{id: id, name: name, arguments: args}}
  end

  defp parse_arguments(_id, _name, args) do
    {:error, "arguments must be a JSON string or map, got: #{inspect(args)}"}
  end

  defp parse_from_choices([%{"message" => message} | _]) do
    parse_tool_calls(message)
  end

  defp parse_from_choices([%{message: message} | _]) do
    parse_tool_calls(message)
  end

  defp parse_from_choices(_), do: {:error, :no_tool_calls}

  defp execute_with_timeout(id, name, tool, args, context, executor, timeout, start_time) do
    task =
      Task.async(fn ->
        executor.(tool, args, context)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, Result.ok(id, name, result, duration)}

      {:ok, {:error, reason}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, Result.error(id, name, reason, duration)}

      nil ->
        {:ok, Result.timeout(id, name, timeout)}
    end
  end

  defp default_executor(tool, args, context) do
    # Call the handler module's execute/2 function directly
    # The handler is expected to implement: execute(args, context) -> {:ok, result} | {:error, reason}
    tool.handler.execute(args, context)
  end

  defp execute_sequential(tool_calls, opts) do
    Enum.map(tool_calls, fn tc ->
      {:ok, result} = execute(tc, opts)
      result
    end)
  end

  defp execute_parallel(tool_calls, opts) do
    tool_calls
    |> Task.async_stream(
      fn tc ->
        {:ok, result} = execute(tc, opts)
        result
      end,
      timeout: Keyword.get(opts, :timeout, @default_timeout) + 1000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> Result.timeout("unknown", "unknown", @default_timeout)
    end)
  end

  # ============================================================================
  # PubSub Broadcasting
  # ============================================================================

  @doc """
  Broadcasts a tool call event via PubSub.

  ## Parameters

  - `session_id` - Optional session ID for topic routing (nil uses global topic)
  - `tool_name` - Name of the tool being called
  - `params` - Parameters being passed to the tool
  - `call_id` - Unique ID for this tool call

  ## Events

  Broadcasts `{:tool_call, tool_name, params, call_id, session_id}` to the topic.
  The session_id is included in the message payload so consumers on the global
  topic can identify which session the event originated from.

  ## ARCH-2 Fix

  When a session_id is provided, broadcasts to BOTH the session-specific topic
  AND the global topic to ensure messages reach both session-specific and global
  subscribers (like PubSubBridge).
  """
  @spec broadcast_tool_call(String.t() | nil, String.t(), map(), String.t()) :: :ok
  def broadcast_tool_call(session_id, tool_name, params, call_id) do
    message = {:tool_call, tool_name, params, call_id, session_id}
    PubSubHelpers.broadcast(session_id, message)
  end

  @doc """
  Broadcasts a tool result event via PubSub.

  ## Parameters

  - `session_id` - Optional session ID for topic routing (nil uses global topic)
  - `result` - The `%Result{}` struct from tool execution

  ## Events

  Broadcasts `{:tool_result, result, session_id}` to the topic.
  The session_id is included in the message payload so consumers on the global
  topic can identify which session the event originated from.

  ## ARCH-2 Fix

  When a session_id is provided, broadcasts to BOTH the session-specific topic
  AND the global topic to ensure messages reach all subscribers.
  """
  @spec broadcast_tool_result(String.t() | nil, Result.t()) :: :ok
  def broadcast_tool_result(session_id, result) do
    message = {:tool_result, result, session_id}
    PubSubHelpers.broadcast(session_id, message)
  end

  @doc """
  Returns the PubSub topic for a given session ID.

  Delegates to `PubSubHelpers.session_topic/1`.

  ## Parameters

  - `session_id` - Session ID or nil

  ## Returns

  - `"tui.events.{session_id}"` if session_id is provided
  - `"tui.events"` if session_id is nil
  """
  @spec pubsub_topic(String.t() | nil) :: String.t()
  def pubsub_topic(session_id), do: PubSubHelpers.session_topic(session_id)
end
