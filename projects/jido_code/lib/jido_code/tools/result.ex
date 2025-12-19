defmodule JidoCode.Tools.Result do
  @moduledoc """
  Represents the result of a tool execution.

  This struct captures the outcome of executing a tool, including success/failure
  status, the result content, and execution metadata. It can be converted to
  LLM-compatible format for inclusion in conversation context.

  ## Structure

  - `:tool_call_id` - Unique ID from the original tool call (for correlation)
  - `:tool_name` - Name of the tool that was executed
  - `:status` - Execution status: `:ok`, `:error`, or `:timeout`
  - `:content` - Result content (success) or error message (failure)
  - `:duration_ms` - Execution time in milliseconds

  ## Examples

      # Successful result
      %Result{
        tool_call_id: "call_abc123",
        tool_name: "read_file",
        status: :ok,
        content: "file contents here...",
        duration_ms: 45
      }

      # Error result
      %Result{
        tool_call_id: "call_abc123",
        tool_name: "read_file",
        status: :error,
        content: "File not found: /nonexistent.txt",
        duration_ms: 12
      }

      # Timeout result
      %Result{
        tool_call_id: "call_abc123",
        tool_name: "slow_operation",
        status: :timeout,
        content: "Tool execution timed out after 30000ms",
        duration_ms: 30000
      }
  """

  @type status :: :ok | :error | :timeout

  @type t :: %__MODULE__{
          tool_call_id: String.t(),
          tool_name: String.t(),
          status: status(),
          content: String.t(),
          duration_ms: non_neg_integer()
        }

  @enforce_keys [:tool_call_id, :tool_name, :status, :content]
  defstruct [
    :tool_call_id,
    :tool_name,
    :status,
    :content,
    duration_ms: 0
  ]

  @doc """
  Creates a successful result.

  ## Parameters

  - `tool_call_id` - The ID from the original tool call
  - `tool_name` - Name of the executed tool
  - `content` - The result content
  - `duration_ms` - Execution time (optional, default 0)

  ## Examples

      Result.ok("call_123", "read_file", "file contents", 45)
      # => %Result{status: :ok, content: "file contents", ...}
  """
  @spec ok(String.t(), String.t(), term(), non_neg_integer()) :: t()
  def ok(tool_call_id, tool_name, content, duration_ms \\ 0) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      status: :ok,
      content: format_content(content),
      duration_ms: duration_ms
    }
  end

  @doc """
  Creates an error result.

  ## Parameters

  - `tool_call_id` - The ID from the original tool call
  - `tool_name` - Name of the executed tool
  - `reason` - Error reason (will be formatted as string)
  - `duration_ms` - Execution time (optional, default 0)

  ## Examples

      Result.error("call_123", "read_file", :file_not_found, 12)
      # => %Result{status: :error, content: "file_not_found", ...}
  """
  @spec error(String.t(), String.t(), term(), non_neg_integer()) :: t()
  def error(tool_call_id, tool_name, reason, duration_ms \\ 0) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      status: :error,
      content: format_error(reason),
      duration_ms: duration_ms
    }
  end

  @doc """
  Creates a timeout result.

  ## Parameters

  - `tool_call_id` - The ID from the original tool call
  - `tool_name` - Name of the executed tool
  - `timeout_ms` - The timeout value that was exceeded

  ## Examples

      Result.timeout("call_123", "slow_tool", 30000)
      # => %Result{status: :timeout, content: "Tool execution timed out...", ...}
  """
  @spec timeout(String.t(), String.t(), non_neg_integer()) :: t()
  def timeout(tool_call_id, tool_name, timeout_ms) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      status: :timeout,
      content: "Tool execution timed out after #{timeout_ms}ms",
      duration_ms: timeout_ms
    }
  end

  @doc """
  Checks if the result represents a successful execution.
  """
  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{status: :ok}), do: true
  def ok?(%__MODULE__{}), do: false

  @doc """
  Checks if the result represents an error.
  """
  @spec error?(t()) :: boolean()
  def error?(%__MODULE__{status: :error}), do: true
  def error?(%__MODULE__{status: :timeout}), do: true
  def error?(%__MODULE__{}), do: false

  @doc """
  Converts the result to LLM-compatible message format.

  Returns a map suitable for inclusion in an OpenAI-style chat completion
  request as a tool response message.

  ## Returns

  A map with:
  - `:role` - "tool"
  - `:tool_call_id` - The original tool call ID
  - `:content` - The result content (prefixed with error info if failed)

  ## Examples

      result = %Result{tool_call_id: "call_123", status: :ok, content: "data"}
      Result.to_llm_message(result)
      # => %{role: "tool", tool_call_id: "call_123", content: "data"}

      result = %Result{tool_call_id: "call_123", status: :error, content: "failed"}
      Result.to_llm_message(result)
      # => %{role: "tool", tool_call_id: "call_123", content: "Error: failed"}
  """
  @spec to_llm_message(t()) :: map()
  def to_llm_message(%__MODULE__{} = result) do
    content =
      case result.status do
        :ok -> result.content
        :error -> "Error: #{result.content}"
        :timeout -> "Error: #{result.content}"
      end

    %{
      role: "tool",
      tool_call_id: result.tool_call_id,
      content: content
    }
  end

  @doc """
  Converts a list of results to LLM messages.

  ## Examples

      results = [result1, result2]
      Result.to_llm_messages(results)
      # => [%{role: "tool", ...}, %{role: "tool", ...}]
  """
  @spec to_llm_messages([t()]) :: [map()]
  def to_llm_messages(results) when is_list(results) do
    Enum.map(results, &to_llm_message/1)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp format_content(content) when is_binary(content), do: content
  defp format_content(content) when is_map(content), do: Jason.encode!(content)
  defp format_content(content) when is_list(content), do: Jason.encode!(content)
  defp format_content(content), do: inspect(content)

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp format_error({:error, reason}), do: format_error(reason)

  defp format_error(%{message: message}) when is_binary(message), do: message

  defp format_error(reason), do: inspect(reason)
end
