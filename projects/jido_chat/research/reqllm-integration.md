# ReqLLM Integration Research

## Overview

ReqLLM integration is the **brain interface** of JIDO_CHAT_V2 - it transforms conversation context into LLM requests and orchestrates agent responses.

## Core Questions

### 1. How do we optimize context window usage?

**Challenge**: LLMs have token limits (4k-128k depending on model). Long conversations can exceed limits.

**Strategies**:

#### Strategy A: Fixed Message Window

```elixir
defmodule ContextBuilder do
  def build_conversation_history(history, opts \\ []) do
    window_size = opts[:message_window] || 20
    
    history
    |> Enum.take(-window_size)  # Last N messages
    |> Enum.map(&normalize_for_llm/1)
  end
end
```

**Pros**: Simple, predictable
**Cons**: May cut off important context

#### Strategy B: Token-Aware Windowing

```elixir
defmodule ContextBuilder do
  def build_conversation_history(history, opts \\ []) do
    max_tokens = opts[:max_context_tokens] || 4000
    
    history
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0}, fn msg, {acc, token_count} ->
      msg_tokens = estimate_tokens(msg.content.text)
      
      if token_count + msg_tokens <= max_tokens do
        {:cont, {[msg | acc], token_count + msg_tokens}}
      else
        {:halt, {acc, token_count}}
      end
    end)
    |> elem(0)
    |> Enum.map(&normalize_for_llm/1)
  end
  
  defp estimate_tokens(text) do
    # Rough approximation: 1 token ≈ 4 characters
    ceil(String.length(text) / 4)
  end
end
```

**Pros**: Maximizes context usage
**Cons**: Token counting is approximate

#### Strategy C: Semantic Compression

```elixir
defmodule ContextBuilder do
  def build_conversation_history(history, opts \\ []) do
    # Use LLM to summarize old messages
    {recent, old} = Enum.split(history, -10)
    
    summary = if length(old) > 0 do
      compress_old_messages(old)
    else
      nil
    end
    
    messages = if summary do
      [%{role: :system, content: "Previous conversation summary: #{summary}"}] ++
      Enum.map(recent, &normalize_for_llm/1)
    else
      Enum.map(recent, &normalize_for_llm/1)
    end
    
    messages
  end
  
  defp compress_old_messages(messages) do
    # Call LLM with summarization prompt
    text = Enum.map_join(messages, "\n", &"#{&1.from.display_name}: #{&1.content.text}")
    
    req = %ReqLLM.Request{
      messages: [
        %{role: :system, content: "Summarize the following conversation concisely:"},
        %{role: :user, content: text}
      ],
      model: "gpt-3.5-turbo",
      max_tokens: 200
    }
    
    {:ok, response} = ReqLLM.chat(req)
    response.message.content
  end
end
```

**Pros**: Preserves key information
**Cons**: Extra LLM call cost

**Recommended**: Start with Strategy B (token-aware), add Strategy C as opt-in feature.

**Research Tasks**:
- [ ] Benchmark token estimation accuracy
- [ ] Test with different model context windows
- [ ] Evaluate summarization quality
- [ ] Design per-instance windowing configuration

---

### 2. Tool Calling Patterns

**Challenge**: LLMs can call tools (Jido.Actions), which may call other tools, creating complex call graphs.

**Pattern A: Single-Turn Tool Execution**

```elixir
defmodule AgentGateway do
  def process_with_tools(req, room_state) do
    # Submit initial request
    {:ok, response} = ReqLLM.chat(req)
    
    # If LLM calls tools, execute them
    case response.message.tool_calls do
      nil ->
        {:ok, response.message}
      
      tool_calls ->
        # Execute all tools
        tool_results = execute_tools(tool_calls, room_state)
        
        # Submit tool results back to LLM
        follow_up_req = %{req |
          messages: req.messages ++ [
            response.message,
            tool_results
          ]
        }
        
        {:ok, final_response} = ReqLLM.chat(follow_up_req)
        {:ok, final_response.message}
    end
  end
end
```

**Pros**: Simple, predictable
**Cons**: Limited to one round of tool calls

**Pattern B: Multi-Turn Tool Execution Loop**

```elixir
defmodule AgentGateway do
  def process_with_tools(req, room_state, max_turns \\ 5) do
    process_loop(req, room_state, max_turns, [])
  end
  
  defp process_loop(req, room_state, turns_left, history) do
    if turns_left == 0 do
      {:error, :max_tool_turns_exceeded}
    else
      {:ok, response} = ReqLLM.chat(req)
      
      case response.message.tool_calls do
        nil ->
          # No more tools, return final message
          {:ok, response.message, history}
        
        tool_calls ->
          # Execute tools
          tool_results = execute_tools(tool_calls, room_state)
          
          # Build next request with tool results
          next_req = %{req |
            messages: req.messages ++ [
              response.message,
              tool_results
            ]
          }
          
          # Continue loop
          process_loop(
            next_req,
            room_state,
            turns_left - 1,
            [response.message | history]
          )
      end
    end
  end
end
```

**Pros**: Supports complex multi-step workflows
**Cons**: Can be slow, expensive

**Pattern C: Parallel Tool Execution**

```elixir
defmodule AgentGateway do
  defp execute_tools(tool_calls, room_state) do
    # Execute all tool calls in parallel
    tasks = Enum.map(tool_calls, fn tool_call ->
      Task.async(fn ->
        execute_single_tool(tool_call, room_state)
      end)
    end)
    
    # Wait for all results
    results = Task.await_many(tasks, :timer.seconds(30))
    
    # Format as tool messages
    Enum.map(results, fn {tool_call_id, result} ->
      %{
        role: :tool,
        tool_call_id: tool_call_id,
        content: Jason.encode!(result)
      }
    end)
  end
end
```

**Pros**: Faster for independent tools
**Cons**: Tools can't depend on each other's results

**Recommended**: Start with Pattern B (multi-turn loop), add Pattern C for parallel execution.

**Research Tasks**:
- [ ] Design tool dependency detection
- [ ] Build tool execution timeout handling
- [ ] Handle tool errors gracefully
- [ ] Measure tool call latency

---

### 3. Streaming Across Platforms

**Challenge**: Some platforms support streaming (web chat), others don't (WhatsApp).

**Strategy**: Stream internally, buffer for platforms that don't support it.

```elixir
defmodule AgentGateway do
  def process_streaming(req, room_id, opts \\ []) do
    # Always stream from LLM
    {:ok, stream} = ReqLLM.chat_stream(req)
    
    # Check if platform supports streaming
    room_state = RoomServer.get_state(room_id)
    instance = Instance.get(room_state.instance_id)
    
    if supports_streaming?(instance.channel_type) do
      stream_to_room(stream, room_id)
    else
      buffer_and_send(stream, room_id)
    end
  end
  
  defp supports_streaming?(channel_type) do
    channel_type in [:web, :slack_app]  # Only some channels support streaming
  end
  
  defp stream_to_room(stream, room_id) do
    Stream.each(stream, fn chunk ->
      RoomServer.stream_chunk(room_id, chunk.content)
      emit_signal("chat.agent.chunk", %{room_id: room_id, chunk: chunk})
    end)
    |> Stream.run()
    
    {:ok, :streaming_complete}
  end
  
  defp buffer_and_send(stream, room_id) do
    # Collect all chunks
    full_text = stream
    |> Enum.map(& &1.content)
    |> Enum.join("")
    
    # Send as single message
    message = %{role: :assistant, content: full_text}
    RoomServer.add_message(room_id, message)
    
    {:ok, message}
  end
end
```

**For platforms with partial streaming support (Slack)**:

```elixir
defp stream_to_slack(stream, room_id, channel_id, token) do
  # Post initial message
  {:ok, %{ts: message_ts}} = Slack.Web.Chat.post_message(
    channel_id,
    "Thinking...",
    token
  )
  
  # Update message as chunks arrive
  buffer = ""
  last_update = System.monotonic_time(:millisecond)
  
  Stream.each(stream, fn chunk ->
    buffer = buffer <> chunk.content
    now = System.monotonic_time(:millisecond)
    
    # Update every 500ms to avoid rate limits
    if now - last_update > 500 do
      Slack.Web.Chat.update(channel_id, message_ts, buffer, token)
      last_update = now
    end
  end)
  |> Stream.run()
  
  # Final update with complete text
  Slack.Web.Chat.update(channel_id, message_ts, buffer, token)
end
```

**Research Tasks**:
- [ ] Test streaming on different channels
- [ ] Design buffer strategies for non-streaming channels
- [ ] Handle streaming errors (network interruption)
- [ ] Optimize update frequency for Slack

---

### 4. Prompt Governance

**Challenge**: Need to control what prompts reach the LLM (safety, compliance, cost).

**Governance Layers**:

```elixir
defmodule PromptGovernance do
  @moduledoc """
  Enforces policies on ReqLLM requests before submission.
  """
  
  def validate_and_transform(req, room_state) do
    req
    |> check_safety_rules()
    |> check_token_limits()
    |> check_tenant_policies(room_state)
    |> inject_guardrails()
  end
  
  defp check_safety_rules(req) do
    # Scan for prohibited content
    content = Enum.map_join(req.messages, " ", & &1.content)
    
    case ContentModerator.check(content) do
      :safe -> {:ok, req}
      {:unsafe, reason} -> {:error, {:unsafe_content, reason}}
    end
  end
  
  defp check_token_limits(req) do
    total_tokens = estimate_request_tokens(req)
    
    if total_tokens > req.max_tokens * 2 do
      {:error, :request_too_large}
    else
      {:ok, req}
    end
  end
  
  defp check_tenant_policies(req, room_state) do
    instance = Instance.get(room_state.instance_id)
    
    # Check if tenant has budget remaining
    if Billing.has_budget?(instance.tenant_id) do
      {:ok, req}
    else
      {:error, :budget_exceeded}
    end
  end
  
  defp inject_guardrails(req) do
    # Add safety instructions to system prompt
    safety_prompt = """
    You must follow these guidelines:
    - Never share personal information
    - Refuse harmful requests
    - Stay within your role
    """
    
    updated_messages = [
      %{role: :system, content: safety_prompt} | req.messages
    ]
    
    {:ok, %{req | messages: updated_messages}}
  end
end
```

**Research Tasks**:
- [ ] Design safety rule engine
- [ ] Build content moderation integration
- [ ] Implement tenant policy framework
- [ ] Create prompt injection detection

---

## Implementation Examples

### Context Builder

```elixir
defmodule Jido.Chat.V2.ContextBuilder do
  alias Jido.Chat.V2.{Room, Message, Participant}
  alias Jido.Character
  
  def build_context(room_state, current_message, opts \\ []) do
    # 1. Resolve character
    character = resolve_character(room_state)
    
    # 2. Build system messages
    system_messages = [
      %{role: :system, content: character.system_prompt},
      %{role: :system, content: character.behavioral_guidelines},
      %{role: :system, content: build_context_info(room_state)}
    ]
    
    # 3. Build conversation history (token-aware)
    conversation_messages = build_conversation_history(
      room_state.history,
      max_context_tokens: opts[:max_context_tokens] || 4000
    )
    
    # 4. Add current message
    user_message = normalize_message_for_llm(current_message)
    
    # 5. Build tool definitions
    tools = build_tool_definitions(character)
    
    # 6. Assemble request
    %ReqLLM.Request{
      messages: system_messages ++ conversation_messages ++ [user_message],
      tools: tools,
      model: room_state.config.model || character.model_preferences.model,
      temperature: character.temperature || 0.7,
      max_tokens: room_state.config.max_tokens || 1000,
      metadata: %{
        tenant_id: room_state.tenant_id,
        instance_id: room_state.instance_id,
        room_id: room_state.id,
        character_id: character.id,
        trace_id: Jido.Signal.current_trace_id()
      }
    }
  end
  
  defp build_context_info(room_state) do
    participants = Enum.map_join(room_state.participants, ", ", & &1.display_name)
    
    """
    Current conversation context:
    - Room: #{room_state.id}
    - Participants: #{participants}
    - Conversation started: #{room_state.created_at}
    """
  end
  
  defp normalize_message_for_llm(message) do
    %{
      role: message.role,  # :user | :assistant | :tool
      content: format_content(message.content),
      name: message.from.display_name
    }
  end
  
  defp format_content(%{type: :text, text: text}), do: text
  defp format_content(%{type: :rich, text: text, attachments: atts}) do
    # Include attachment info in text
    att_info = Enum.map_join(atts, "\n", fn att ->
      "[Attachment: #{att.type} - #{att.filename || att.url}]"
    end)
    
    "#{text}\n\n#{att_info}"
  end
  
  defp build_tool_definitions(character) do
    character.available_actions
    |> Enum.map(&action_to_tool_definition/1)
  end
  
  defp action_to_tool_definition(action_module) do
    %{
      type: "function",
      function: %{
        name: action_module.__action__(:name),
        description: action_module.__action__(:description),
        parameters: schema_to_json_schema(action_module.__action__(:schema))
      }
    }
  end
end
```

---

## Testing Strategy

### Mocking LLM Responses

```elixir
defmodule ReqLLM.MockAdapter do
  @moduledoc """
  Mock adapter for testing LLM interactions without API calls.
  """
  
  def chat(%{messages: messages} = req) do
    # Pattern match on last user message
    last_user_message = Enum.find(Enum.reverse(messages), & &1.role == :user)
    
    response = case last_user_message.content do
      "What's my order status?" ->
        %{
          role: :assistant,
          content: nil,
          tool_calls: [
            %{
              id: "call_123",
              type: "function",
              function: %{
                name: "lookup_order",
                arguments: "{\"order_id\": \"12345\"}"
              }
            }
          ]
        }
      
      _ ->
        %{role: :assistant, content: "I can help with that!"}
    end
    
    {:ok, %{message: response, usage: %{total_tokens: 50}}}
  end
end

# In tests
config :req_llm, adapter: ReqLLM.MockAdapter

test "agent calls tool when appropriate" do
  room = create_test_room()
  message = build_message("What's my order status?")
  
  {:ok, response} = AgentGateway.process_message(room.id, message)
  
  assert response.tool_calls != nil
  assert hd(response.tool_calls).function.name == "lookup_order"
end
```

---

## Next Steps

1. **Implement** token-aware context windowing
2. **Build** multi-turn tool execution loop
3. **Test** streaming across different channels
4. **Design** prompt governance framework
5. **Benchmark** context building performance
