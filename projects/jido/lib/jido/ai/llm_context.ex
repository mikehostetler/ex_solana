defmodule Jido.AI.LLMContext do
  @moduledoc """
  ReqLLM-specific helpers for building messages and tool-calls.

  This module provides a clean interface for constructing LLM conversation
  messages and tool calls, hiding ReqLLM.Context and ReqLLM.ToolCall internals
  from consuming code.

  Designed for tight integration with ReqLLM - no adapters or indirection.
  This module will eventually move to the `jido_ai` package.
  """

  alias ReqLLM.Context
  alias ReqLLM.ToolCall

  @doc "Create a system message."
  @spec system_message(String.t()) :: ReqLLM.Message.t()
  def system_message(prompt), do: Context.system(prompt)

  @doc "Create a user message."
  @spec user_message(String.t()) :: ReqLLM.Message.t()
  def user_message(text), do: Context.user(text)

  @doc "Create an assistant message with optional text."
  @spec assistant_message(String.t()) :: ReqLLM.Message.t()
  def assistant_message(text), do: Context.assistant(text)

  @doc """
  Create an assistant message containing tool calls.

  Takes a list of tool call maps with :id, :name, :arguments keys.
  """
  @spec assistant_tool_calls([%{id: String.t(), name: String.t(), arguments: map()}]) ::
          ReqLLM.Message.t()
  def assistant_tool_calls(tool_calls) do
    tool_call_structs =
      Enum.map(tool_calls, fn tc ->
        ToolCall.new(tc.id, tc.name, Jason.encode!(tc.arguments))
      end)

    Context.assistant("", tool_calls: tool_call_structs)
  end

  @doc """
  Create a tool result message.

  Takes a pending tool call map with :id, :name, :result keys.
  Result should be {:ok, value} or {:error, reason}.
  """
  @spec tool_result_message(%{
          id: String.t(),
          name: String.t(),
          result: {:ok, term()} | {:error, term()}
        }) ::
          ReqLLM.Message.t()
  def tool_result_message(%{id: id, name: name, result: result}) do
    content =
      case result do
        {:ok, res} -> Jason.encode!(res)
        {:error, reason} -> "Error: #{inspect(reason)}"
      end

    Context.tool_result(id, name, content)
  end

  @doc "Create tool result messages from a list of pending tool calls."
  @spec tool_result_messages([%{id: String.t(), name: String.t(), result: term()}]) ::
          [ReqLLM.Message.t()]
  def tool_result_messages(pending_tool_calls) do
    Enum.map(pending_tool_calls, &tool_result_message/1)
  end
end
