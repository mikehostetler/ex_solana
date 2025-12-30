defmodule Jido.AI.LLMBackend do
  @moduledoc """
  ReqLLM-specific streaming and tool-call extraction for LLM agents.

  This module encapsulates all ReqLLM streaming API calls and the
  chunk parsing logic that classifies responses as tool calls or final answers.

  Designed for tight integration with ReqLLM - no adapters or indirection.
  This module will eventually move to the `jido_ai` package.

  Note: The tool call extraction logic here is temporary. Once ReqLLM adds
  `stream_text_and_classify/3` (see JIDO_REQ_LLM_PR.md), this module will
  simplify significantly.
  """

  @doc """
  Generate a unique call ID for LLM request correlation.

  This is an impure function (uses unique_integer). Call sites should
  treat this as an effect and use the returned ID for correlation.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "call_#{:erlang.unique_integer([:positive])}"
  end

  @type stream_result :: %{
          type: :tool_calls | :final_answer,
          text: String.t(),
          tool_calls: [%{id: String.t(), name: String.t(), arguments: map()}]
        }

  @doc """
  Stream an LLM response and classify the result.

  Returns {:ok, result} where result contains:
  - type: :tool_calls or :final_answer
  - text: accumulated text from the response
  - tool_calls: list of tool calls (empty if type is :final_answer)
  """
  @spec stream(String.t(), term(), [ReqLLM.Tool.t()]) ::
          {:ok, stream_result()} | {:error, term()}
  def stream(model, context, tools) do
    opts = if tools != [], do: [tools: tools], else: []

    messages = normalize_messages(context)

    case ReqLLM.stream_text(model, messages, opts) do
      {:ok, stream_response} ->
        chunks = Enum.to_list(stream_response.stream)
        {:ok, classify_chunks(chunks)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_messages(context) do
    case context do
      %{messages: msgs} -> msgs
      msgs when is_list(msgs) -> msgs
      _ -> context
    end
  end

  defp classify_chunks(chunks) do
    tool_calls = extract_tool_calls(chunks)
    text = chunks |> Enum.map_join("", & &1.text)

    if tool_calls != [] do
      %{type: :tool_calls, text: text, tool_calls: tool_calls}
    else
      %{type: :final_answer, text: text, tool_calls: []}
    end
  end

  defp extract_tool_calls(chunks) do
    tool_calls =
      chunks
      |> Enum.filter(&(&1.type == :tool_call))
      |> Enum.map(fn chunk ->
        %{
          id:
            Map.get(chunk.metadata || %{}, :id) || "call_#{:erlang.unique_integer([:positive])}",
          name: chunk.name,
          arguments: chunk.arguments || %{},
          index: Map.get(chunk.metadata || %{}, :index, 0)
        }
      end)

    arg_fragments =
      chunks
      |> Enum.filter(fn
        %{type: :meta, metadata: %{tool_call_args: _}} -> true
        _ -> false
      end)
      |> Enum.group_by(& &1.metadata.tool_call_args.index)
      |> Map.new(fn {index, fragments} ->
        json = fragments |> Enum.map_join("", & &1.metadata.tool_call_args.fragment)
        {index, json}
      end)

    tool_calls
    |> Enum.map(fn call ->
      case Map.get(arg_fragments, call.index) do
        nil ->
          Map.delete(call, :index)

        json ->
          case Jason.decode(json) do
            {:ok, args} -> call |> Map.put(:arguments, args) |> Map.delete(:index)
            {:error, _} -> Map.delete(call, :index)
          end
      end
    end)
  end
end
