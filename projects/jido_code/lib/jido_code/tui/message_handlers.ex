defmodule JidoCode.TUI.MessageHandlers do
  @moduledoc """
  Message handlers for TUI PubSub events.

  This module extracts the PubSub message handling logic from the main TUI module
  to improve maintainability. Handlers receive agent events, tool calls, and
  configuration updates.

  ## Message Types

  - Agent responses: `{:agent_response, content}`, streaming chunks
  - Status updates: `{:status_update, status}`, `{:agent_status, status}`
  - Configuration: `{:config_change, config}`, `{:config_changed, config}`
  - Reasoning: `{:reasoning_step, step}`, `:clear_reasoning_steps`
  - Tools: `{:tool_call, ...}`, `{:tool_result, ...}`
  """

  alias JidoCode.Tools.Result
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias JidoCode.TUI.Widgets.ConversationView

  # Maximum number of messages to keep in the debug queue
  @max_queue_size 100

  # ============================================================================
  # Agent Response Handlers
  # ============================================================================

  @doc """
  Handles a complete agent response.
  """
  @spec handle_agent_response(String.t(), Model.t()) :: {Model.t(), list()}
  def handle_agent_response(content, state) do
    message = TUI.assistant_message(content)
    queue = queue_message(state.message_queue, {:agent_response, content})

    new_state = %{
      state
      | messages: [message | state.messages],
        message_queue: queue,
        agent_status: :idle
    }

    {new_state, []}
  end

  @doc """
  Handles a streaming chunk from the agent.
  """
  @spec handle_stream_chunk(String.t(), Model.t()) :: {Model.t(), list()}
  def handle_stream_chunk(chunk, state) do
    new_streaming_message = (state.streaming_message || "") <> chunk
    queue = queue_message(state.message_queue, {:stream_chunk, chunk})

    # Sync with ConversationView if available
    new_conversation_view =
      if state.conversation_view do
        # Start streaming if this is the first chunk
        cv_state =
          if state.streaming_message == nil or state.streaming_message == "" do
            {cv, _id} = ConversationView.start_streaming(state.conversation_view, :assistant)
            cv
          else
            state.conversation_view
          end

        # Append the chunk
        ConversationView.append_chunk(cv_state, chunk)
      else
        state.conversation_view
      end

    new_state = %{
      state
      | streaming_message: new_streaming_message,
        is_streaming: true,
        message_queue: queue,
        conversation_view: new_conversation_view
    }

    {new_state, []}
  end

  @doc """
  Handles the end of a streaming response.
  """
  @spec handle_stream_end(String.t(), Model.t()) :: {Model.t(), list()}
  def handle_stream_end(_full_content, state) do
    message = TUI.assistant_message(state.streaming_message || "")
    queue = queue_message(state.message_queue, {:stream_end, state.streaming_message})

    # Sync with ConversationView if available
    new_conversation_view =
      if state.conversation_view do
        ConversationView.end_streaming(state.conversation_view)
      else
        state.conversation_view
      end

    new_state = %{
      state
      | messages: [message | state.messages],
        streaming_message: nil,
        is_streaming: false,
        agent_status: :idle,
        message_queue: queue,
        conversation_view: new_conversation_view
    }

    {new_state, []}
  end

  @doc """
  Handles a streaming error.
  """
  @spec handle_stream_error(term(), Model.t()) :: {Model.t(), list()}
  def handle_stream_error(reason, state) do
    error_content = "Streaming error: #{inspect(reason)}"
    error_msg = TUI.system_message(error_content)
    queue = queue_message(state.message_queue, {:stream_error, reason})

    # Sync with ConversationView if available - end streaming and add error message
    new_conversation_view =
      if state.conversation_view do
        cv = ConversationView.end_streaming(state.conversation_view)
        ConversationView.add_message(cv, %{
          id: generate_message_id(),
          role: :system,
          content: error_content,
          timestamp: DateTime.utc_now()
        })
      else
        state.conversation_view
      end

    new_state = %{
      state
      | messages: [error_msg | state.messages],
        streaming_message: nil,
        is_streaming: false,
        agent_status: :error,
        message_queue: queue,
        conversation_view: new_conversation_view
    }

    {new_state, []}
  end

  # ============================================================================
  # Status Handlers
  # ============================================================================

  @doc """
  Handles agent status updates.
  """
  @spec handle_status_update(Model.agent_status(), Model.t()) :: {Model.t(), list()}
  def handle_status_update(status, state) do
    queue = queue_message(state.message_queue, {:status_update, status})
    {%{state | agent_status: status, message_queue: queue}, []}
  end

  # ============================================================================
  # Configuration Handlers
  # ============================================================================

  @doc """
  Handles configuration change events.
  """
  @spec handle_config_change(map(), Model.t()) :: {Model.t(), list()}
  def handle_config_change(config, state) do
    new_config = %{
      provider: Map.get(config, :provider, Map.get(config, "provider")),
      model: Map.get(config, :model, Map.get(config, "model"))
    }

    new_status = TUI.determine_status(new_config)
    queue = queue_message(state.message_queue, {:config_change, config})
    {%{state | config: new_config, agent_status: new_status, message_queue: queue}, []}
  end

  # ============================================================================
  # Reasoning Handlers
  # ============================================================================

  @doc """
  Handles a reasoning step event.
  """
  @spec handle_reasoning_step(map(), Model.t()) :: {Model.t(), list()}
  def handle_reasoning_step(step, state) do
    queue = queue_message(state.message_queue, {:reasoning_step, step})
    # Prepend for O(1) - reverse when displaying
    {%{state | reasoning_steps: [step | state.reasoning_steps], message_queue: queue}, []}
  end

  @doc """
  Clears all reasoning steps.
  """
  @spec handle_clear_reasoning_steps(Model.t()) :: {Model.t(), list()}
  def handle_clear_reasoning_steps(state) do
    {%{state | reasoning_steps: []}, []}
  end

  @doc """
  Toggles the reasoning panel visibility.
  """
  @spec handle_toggle_reasoning(Model.t()) :: {Model.t(), list()}
  def handle_toggle_reasoning(state) do
    {%{state | show_reasoning: not state.show_reasoning}, []}
  end

  # ============================================================================
  # Tool Handlers
  # ============================================================================

  @doc """
  Handles a new tool call being initiated.
  """
  @spec handle_tool_call(String.t(), map(), String.t(), Model.t()) :: {Model.t(), list()}
  def handle_tool_call(tool_name, params, call_id, state) do
    tool_call_entry = %{
      call_id: call_id,
      tool_name: tool_name,
      params: params,
      result: nil,
      timestamp: DateTime.utc_now()
    }

    queue = queue_message(state.message_queue, {:tool_call, tool_name, params, call_id})

    new_state = %{state | tool_calls: [tool_call_entry | state.tool_calls], message_queue: queue}

    {new_state, []}
  end

  @doc """
  Handles a tool result.
  """
  @spec handle_tool_result(Result.t(), Model.t()) :: {Model.t(), list()}
  def handle_tool_result(%Result{} = result, state) do
    updated_tool_calls =
      Enum.map(state.tool_calls, fn entry ->
        if entry.call_id == result.tool_call_id do
          %{entry | result: result}
        else
          entry
        end
      end)

    queue = queue_message(state.message_queue, {:tool_result, result})

    new_state = %{state | tool_calls: updated_tool_calls, message_queue: queue}

    {new_state, []}
  end

  @doc """
  Toggles tool details visibility.
  """
  @spec handle_toggle_tool_details(Model.t()) :: {Model.t(), list()}
  def handle_toggle_tool_details(state) do
    {%{state | show_tool_details: not state.show_tool_details}, []}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec queue_message([Model.queued_message()], term()) :: [Model.queued_message()]
  defp queue_message(queue, msg) do
    [{msg, DateTime.utc_now()} | queue]
    |> Enum.take(@max_queue_size)
  end

  @spec generate_message_id() :: String.t()
  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
