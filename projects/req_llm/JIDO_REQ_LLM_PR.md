# ReqLLM: Improved Tool Call Extraction from Streams

## Problem Statement

Consumers of `ReqLLM.stream_text/3` who want to use tools must implement complex chunk parsing logic to extract tool calls. This includes:

1. **Fragment accumulation**: Tool call arguments arrive as JSON fragments across multiple `:meta` chunks with `tool_call_args` metadata
2. **Index correlation**: Fragments must be grouped by `index` to handle parallel tool calls
3. **JSON reconstruction**: Fragments must be joined and decoded
4. **Result classification**: Determining if the response is "tool calls" vs "final answer" requires scanning chunks

Example of the current pain (from Jido's ReAct implementation):

```elixir
defp extract_tool_calls(chunks) do
  tool_calls =
    chunks
    |> Enum.filter(&(&1.type == :tool_call))
    |> Enum.map(fn chunk ->
      %{
        id: Map.get(chunk.metadata || %{}, :id) || "call_#{:erlang.unique_integer([:positive])}",
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
      nil -> Map.delete(call, :index)
      json ->
        case Jason.decode(json) do
          {:ok, args} -> call |> Map.put(:arguments, args) |> Map.delete(:index)
          {:error, _} -> Map.delete(call, :index)
        end
    end
  end)
end
```

This is ~40 lines of brittle, provider-specific logic that every consumer must duplicate.

---

## Proposed Changes

### 1. Add `ReqLLM.Stream.ToolCalls` Helper Module

A new module that handles all the complexity internally:

```elixir
defmodule ReqLLM.Stream.ToolCalls do
  @moduledoc """
  Helpers for extracting tool calls from streaming responses.
  
  Handles fragment accumulation, JSON reconstruction, and result classification
  so consumers don't need to understand the internal chunk format.
  """
  
  @type stream_result :: %{
    type: :tool_calls | :final_answer,
    text: String.t(),
    tool_calls: [ReqLLM.ToolCall.t()]
  }
  
  @doc """
  Classify a stream of chunks into a structured result.
  
  Returns a map with:
  - `type` - `:tool_calls` if the model requested tool execution, `:final_answer` otherwise
  - `text` - Accumulated text content from the response
  - `tool_calls` - List of complete `ReqLLM.ToolCall` structs with parsed arguments
  
  ## Example
  
      {:ok, response} = ReqLLM.stream_text(model, messages, tools: tools)
      chunks = Enum.to_list(response.stream)
      
      case ReqLLM.Stream.ToolCalls.classify(chunks) do
        %{type: :tool_calls, tool_calls: calls} ->
          # Execute tools and continue conversation
          
        %{type: :final_answer, text: answer} ->
          # Done - return answer to user
      end
  """
  @spec classify(Enumerable.t()) :: stream_result()
  def classify(chunks) do
    chunks_list = Enum.to_list(chunks)
    tool_calls = extract_tool_calls(chunks_list)
    text = extract_text(chunks_list)
    
    type = if tool_calls != [], do: :tool_calls, else: :final_answer
    
    %{type: type, text: text, tool_calls: tool_calls}
  end
  
  @doc """
  Extract just the tool calls from a stream.
  
  Returns a list of complete `ReqLLM.ToolCall` structs with parsed arguments.
  """
  @spec extract(Enumerable.t()) :: [ReqLLM.ToolCall.t()]
  def extract(chunks) do
    chunks
    |> Enum.to_list()
    |> extract_tool_calls()
  end
  
  # Private implementation moves the complex logic here
  defp extract_tool_calls(chunks) do
    # ... existing logic, but returns ReqLLM.ToolCall structs
  end
  
  defp extract_text(chunks) do
    chunks
    |> Enum.map_join("", & &1.text)
  end
end
```

### 2. Add `finish_reason` to Stream Response

Expose the model's finish reason so consumers can make decisions based on it rather than heuristics:

```elixir
defmodule ReqLLM.StreamResponse do
  @type t :: %__MODULE__{
    stream: Enumerable.t(),
    finish_reason: :tool_calls | :stop | :length | :content_filter | nil,
    model: String.t() | nil,
    usage: map() | nil
  }
  
  defstruct [:stream, :finish_reason, :model, :usage]
end
```

The `finish_reason` can be:
- `:tool_calls` - Model wants to call tools (OpenAI: `"tool_calls"`, Anthropic: `"tool_use"`)
- `:stop` - Normal completion (OpenAI: `"stop"`, Anthropic: `"end_turn"`)
- `:length` - Hit max tokens
- `:content_filter` - Blocked by safety filter
- `nil` - Not yet known (streaming in progress) or provider doesn't support it

### 3. Convenience Function: `stream_text_and_classify/3`

For the common ReAct pattern, provide a single function that does everything:

```elixir
@doc """
Stream a response and classify it for tool use.

Combines `stream_text/3` with `Stream.ToolCalls.classify/1` for the common
ReAct/agent pattern where you need to determine if the model wants to call
tools or has provided a final answer.

## Example

    case ReqLLM.stream_text_and_classify(model, messages, tools: tools) do
      {:ok, %{type: :tool_calls, tool_calls: calls}} ->
        # Execute tools
        
      {:ok, %{type: :final_answer, text: answer}} ->
        # Return answer
        
      {:error, reason} ->
        # Handle error
    end
"""
@spec stream_text_and_classify(String.t(), [Message.t()], keyword()) ::
  {:ok, Stream.ToolCalls.stream_result()} | {:error, term()}
def stream_text_and_classify(model, messages, opts \\ []) do
  case stream_text(model, messages, opts) do
    {:ok, response} ->
      chunks = Enum.to_list(response.stream)
      {:ok, Stream.ToolCalls.classify(chunks)}
      
    {:error, reason} ->
      {:error, reason}
  end
end
```

### 4. (Optional) Normalized Chunk Format

For a cleaner long-term API, consider normalizing chunks so tool calls are always complete:

**Current format** (leaky):
```elixir
# Chunk 1: Tool call header
%{type: :tool_call, name: "calculator", metadata: %{id: "call_123", index: 0}}

# Chunks 2-N: Argument fragments (ugly)
%{type: :meta, metadata: %{tool_call_args: %{index: 0, fragment: "{\""}}}
%{type: :meta, metadata: %{tool_call_args: %{index: 0, fragment: "a\": 1}"}}}
```

**Proposed format** (clean):
```elixir
# Option A: Emit complete tool call at end of stream
%{type: :tool_call_complete, tool_call: %ReqLLM.ToolCall{id: "call_123", name: "calculator", arguments: %{"a" => 1}}}

# Option B: Buffer internally, only expose text chunks during streaming, 
# then provide tool_calls via StreamResponse or classify/1
```

This is a larger change but would eliminate the need for `Stream.ToolCalls` entirely for simple cases.

---

## Migration Path

### Phase 1: Add Helpers (Non-Breaking)
- Add `ReqLLM.Stream.ToolCalls` module
- Add `stream_text_and_classify/3` convenience function
- Document the new pattern

### Phase 2: Enhance StreamResponse (Minor)
- Add `finish_reason` field to `StreamResponse`
- Populate from provider responses where available

### Phase 3: Normalize Chunks (Future, Breaking)
- Evaluate whether to change chunk format
- If yes, deprecate `:meta` chunks with `tool_call_args`
- Provide migration guide

---

## Impact on Jido

After this PR, Jido's `ReqLLMBackend` simplifies from:

```elixir
# Before: 50+ lines
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

defp classify_chunks(chunks) do
  tool_calls = extract_tool_calls(chunks)
  text = chunks |> Enum.map_join("", & &1.text)
  # ... 40 more lines of extract_tool_calls
end
```

To:

```elixir
# After: ~10 lines
def stream(model, context, tools) do
  opts = if tools != [], do: [tools: tools], else: []
  messages = normalize_messages(context)
  
  ReqLLM.stream_text_and_classify(model, messages, opts)
end
```

---

## Open Questions

1. **Should `ToolCall.new/3` accept maps for arguments?**
   Currently requires JSON string. Accepting maps and encoding internally would be cleaner.

2. **Should tool callbacks return plain terms instead of JSON strings?**
   Let ReqLLM handle encoding. Reduces coupling for consumers.

3. **Should we add a full "agent runner" helper?**
   A `ReqLLM.Agent.run/4` that loops until final answer. Probably out of scope for this PR but worth considering for the future.
