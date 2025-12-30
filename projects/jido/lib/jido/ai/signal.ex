defmodule Jido.AI.Signal do
  @moduledoc """
  Custom signal types for LLM-based agents.

  These signals are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They follow a consistent naming convention: `ai.<event_type>`.

  ## Signal Types

  - `Jido.AI.Signal.LLMResult` - Result from an LLM call
  - `Jido.AI.Signal.ToolResult` - Result from a tool execution

  ## Usage

      alias Jido.AI.Signal

      # Create an LLM result signal
      {:ok, signal} = Signal.LLMResult.new(%{
        call_id: "call_123",
        result: {:ok, %{type: :final_answer, text: "Hello!", tool_calls: []}}
      })

      # Create a tool result signal
      {:ok, signal} = Signal.ToolResult.new(%{
        call_id: "tool_456",
        tool_name: "calculator",
        result: {:ok, %{result: 42}}
      })

      # Bang versions for when you know data is valid
      signal = Signal.LLMResult.new!(%{call_id: "call_123", result: {:ok, response}})
  """

  defmodule LLMResult do
    @moduledoc """
    Signal for LLM streaming/call completion.

    Emitted when an LLM call completes, containing either tool calls to execute
    or a final answer.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original LLMStream directive
    - `:result` (required) - `{:ok, result_map}` or `{:error, reason}` from the LLM call

    The result map (when successful) contains:
    - `:type` - `:tool_calls` or `:final_answer`
    - `:text` - Accumulated text from the response
    - `:tool_calls` - List of tool calls (if type is :tool_calls)
    """

    use Jido.Signal,
      type: "ai.llm_result",
      default_source: "/ai/llm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
      ]
  end

  defmodule ToolResult do
    @moduledoc """
    Signal for tool execution completion.

    Emitted when a tool (Jido.Action) finishes executing.

    ## Data Fields

    - `:call_id` (required) - Tool call ID from the LLM for correlation
    - `:tool_name` (required) - Name of the tool that was executed
    - `:result` (required) - `{:ok, result}` or `{:error, reason}` from tool execution
    """

    use Jido.Signal,
      type: "ai.tool_result",
      default_source: "/ai/tool",
      schema: [
        call_id: [type: :string, required: true, doc: "Tool call ID from the LLM"],
        tool_name: [type: :string, required: true, doc: "Name of the executed tool"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
      ]
  end

  @doc """
  Create an LLM result signal.

  Convenience function that delegates to `Jido.AI.Signal.LLMResult.new/2`.
  """
  @spec llm_result(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, String.t()}
  def llm_result(data, opts \\ []) do
    LLMResult.new(data, opts)
  end

  @doc """
  Create an LLM result signal, raising on error.

  Convenience function that delegates to `Jido.AI.Signal.LLMResult.new!/2`.
  """
  @spec llm_result!(map(), keyword()) :: Jido.Signal.t()
  def llm_result!(data, opts \\ []) do
    LLMResult.new!(data, opts)
  end

  @doc """
  Create a tool result signal.

  Convenience function that delegates to `Jido.AI.Signal.ToolResult.new/2`.
  """
  @spec tool_result(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, String.t()}
  def tool_result(data, opts \\ []) do
    ToolResult.new(data, opts)
  end

  @doc """
  Create a tool result signal, raising on error.

  Convenience function that delegates to `Jido.AI.Signal.ToolResult.new!/2`.
  """
  @spec tool_result!(map(), keyword()) :: Jido.Signal.t()
  def tool_result!(data, opts \\ []) do
    ToolResult.new!(data, opts)
  end
end
