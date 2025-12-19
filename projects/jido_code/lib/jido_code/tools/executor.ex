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

  ## Usage

      # Parse and execute tool calls from LLM response
      {:ok, tool_calls} = Executor.parse_tool_calls(llm_response)
      {:ok, results} = Executor.execute_batch(tool_calls)

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
  - `:context` - Additional context passed to the executor
  - `:session_id` - Optional session ID for PubSub topic routing

  ## PubSub Events

  When a session_id is provided, the executor broadcasts events to the
  `"tui.events.{session_id}"` topic. Without a session_id, events go to
  `"tui.events"`.

  Events broadcast:
  - `{:tool_call, tool_name, params, call_id}` - When tool execution starts
  - `{:tool_result, result}` - When tool execution completes (Result struct)
  """

  alias JidoCode.Tools.{Registry, Result, Tool}

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
  Options for tool execution.
  """
  @type execute_opts :: [
          executor: (Tool.t(), map(), map() -> {:ok, term()} | {:error, term()}),
          timeout: pos_integer(),
          context: map(),
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
  - `:context` - Additional context for the executor

  ## Returns

  - `{:ok, %Result{}}` - Execution result
  - `{:error, reason}` - Validation or execution failure

  ## Examples

      tool_call = %{id: "call_123", name: "read_file", arguments: %{"path" => "/tmp/test.txt"}}
      {:ok, result} = Executor.execute(tool_call)
  """
  @spec execute(tool_call() | map(), execute_opts()) :: {:ok, Result.t()} | {:error, term()}
  def execute(tool_call, opts \\ [])

  def execute(%{id: id, name: name, arguments: args} = _tool_call, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    context = Keyword.get(opts, :context, %{})
    executor = Keyword.get(opts, :executor, &default_executor/3)
    session_id = Keyword.get(opts, :session_id)

    start_time = System.monotonic_time(:millisecond)

    with {:ok, tool} <- validate_tool_exists(name),
         :ok <- validate_arguments(tool, args) do
      # Broadcast tool call start
      broadcast_tool_call(session_id, name, args, id)

      result = execute_with_timeout(id, name, tool, args, context, executor, timeout, start_time)

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

  Broadcasts `{:tool_call, tool_name, params, call_id}` to the topic.

  ## ARCH-2 Fix

  When a session_id is provided, broadcasts to BOTH the session-specific topic
  AND the global topic to ensure messages reach both session-specific and global
  subscribers (like PubSubBridge).
  """
  @spec broadcast_tool_call(String.t() | nil, String.t(), map(), String.t()) :: :ok
  def broadcast_tool_call(session_id, tool_name, params, call_id) do
    message = {:tool_call, tool_name, params, call_id}
    broadcast_to_topics(session_id, message)
  end

  @doc """
  Broadcasts a tool result event via PubSub.

  ## Parameters

  - `session_id` - Optional session ID for topic routing (nil uses global topic)
  - `result` - The `%Result{}` struct from tool execution

  ## Events

  Broadcasts `{:tool_result, result}` to the topic.

  ## ARCH-2 Fix

  When a session_id is provided, broadcasts to BOTH the session-specific topic
  AND the global topic to ensure messages reach all subscribers.
  """
  @spec broadcast_tool_result(String.t() | nil, Result.t()) :: :ok
  def broadcast_tool_result(session_id, result) do
    message = {:tool_result, result}
    broadcast_to_topics(session_id, message)
  end

  # ARCH-2 Fix: Broadcast to both session-specific and global topics
  defp broadcast_to_topics(nil, message) do
    # No session ID - just broadcast to global topic
    Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", message)
  end

  defp broadcast_to_topics(session_id, message) when is_binary(session_id) do
    # Session ID provided - broadcast to both session-specific AND global topics
    # This ensures PubSubBridge (global subscriber) receives the message
    Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events.#{session_id}", message)
    Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", message)
  end

  @doc """
  Returns the PubSub topic for a given session ID.

  ## Parameters

  - `session_id` - Session ID or nil

  ## Returns

  - `"tui.events.{session_id}"` if session_id is provided
  - `"tui.events"` if session_id is nil
  """
  @spec pubsub_topic(String.t() | nil) :: String.t()
  def pubsub_topic(nil), do: "tui.events"
  def pubsub_topic(session_id) when is_binary(session_id), do: "tui.events.#{session_id}"
end
