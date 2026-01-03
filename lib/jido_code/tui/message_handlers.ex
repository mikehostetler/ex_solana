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

  # Default usage values for initialization
  @default_usage %{input_tokens: 0, output_tokens: 0, total_cost: 0.0}

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

    new_state =
      %{state | messages: [message | state.messages], message_queue: queue}
      |> Model.set_active_agent_status(:idle)

    {new_state, []}
  end

  @doc """
  Handles a streaming chunk from the agent.

  Two-tier update system (Phase 4.7.3):
  - Active session: Full UI update (conversation_view, streaming_message, etc.)
  - Inactive session: Sidebar-only update (streaming indicator, last_activity)
  """
  @spec handle_stream_chunk(String.t(), String.t(), Model.t()) :: {Model.t(), list()}
  def handle_stream_chunk(session_id, chunk, state) do
    if session_id == state.active_session_id do
      handle_active_stream_chunk(session_id, chunk, state)
    else
      handle_inactive_stream_chunk(session_id, chunk, state)
    end
  end

  # Active session: Full UI update
  defp handle_active_stream_chunk(session_id, chunk, state) do
    queue = queue_message(state.message_queue, {:stream_chunk, chunk})

    # Update active session's UI state: conversation view, streaming message, is_streaming, agent_activity
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        new_streaming_message = (ui.streaming_message || "") <> chunk
        is_first_chunk = ui.streaming_message == nil or ui.streaming_message == ""

        # Start streaming in conversation view if this is the first chunk
        new_conversation_view =
          if ui.conversation_view do
            cv_state =
              if is_first_chunk do
                {cv, _id} = ConversationView.start_streaming(ui.conversation_view, :assistant)
                cv
              else
                ui.conversation_view
              end

            ConversationView.append_chunk(cv_state, chunk)
          else
            ui.conversation_view
          end

        # Set agent_activity to thinking on first chunk (default to :chat, can be enhanced later)
        new_activity =
          if is_first_chunk do
            {:thinking, :chat}
          else
            ui.agent_activity
          end

        %{
          ui
          | conversation_view: new_conversation_view,
            streaming_message: new_streaming_message,
            is_streaming: true,
            agent_activity: new_activity
        }
      end)

    # Track streaming activity (kept at model level for sidebar indicators)
    new_streaming_sessions = MapSet.put(new_state.streaming_sessions, session_id)
    new_last_activity = Map.put(new_state.last_activity, session_id, DateTime.utc_now())

    final_state = %{
      new_state
      | message_queue: queue,
        streaming_sessions: new_streaming_sessions,
        last_activity: new_last_activity
    }

    {final_state, []}
  end

  # Inactive session: Update session's ConversationView without full UI refresh
  defp handle_inactive_stream_chunk(session_id, chunk, state) do
    # Update the inactive session's UI state (accumulate chunks for when user switches)
    new_state =
      Model.update_session_ui_state(state, session_id, fn ui ->
        new_streaming_message = (ui.streaming_message || "") <> chunk
        is_first_chunk = ui.streaming_message == nil or ui.streaming_message == ""

        # Start streaming in conversation view if this is the first chunk
        new_conversation_view =
          if ui.conversation_view do
            cv_state =
              if is_first_chunk do
                {cv, _id} = ConversationView.start_streaming(ui.conversation_view, :assistant)
                cv
              else
                ui.conversation_view
              end

            ConversationView.append_chunk(cv_state, chunk)
          else
            ui.conversation_view
          end

        # Set agent_activity to thinking on first chunk
        new_activity =
          if is_first_chunk do
            {:thinking, :chat}
          else
            ui.agent_activity
          end

        %{
          ui
          | conversation_view: new_conversation_view,
            streaming_message: new_streaming_message,
            is_streaming: true,
            agent_activity: new_activity
        }
      end)

    # Track streaming activity (kept at model level for sidebar indicators)
    new_streaming_sessions = MapSet.put(new_state.streaming_sessions, session_id)
    new_last_activity = Map.put(new_state.last_activity, session_id, DateTime.utc_now())

    final_state = %{
      new_state
      | streaming_sessions: new_streaming_sessions,
        last_activity: new_last_activity
    }

    {final_state, []}
  end

  @doc """
  Handles the end of a streaming response.

  Two-tier update system (Phase 4.7.3):
  - Active session: Complete message, finalize conversation_view, clear streaming indicator
  - Inactive session: Clear streaming indicator, increment unread count

  The metadata map may contain:
  - :usage - Token usage info (input_tokens, output_tokens, total_cost, etc.)
  - :status - HTTP status
  - :headers - Response headers
  """
  @spec handle_stream_end(String.t(), String.t(), map(), Model.t()) :: {Model.t(), list()}
  def handle_stream_end(session_id, full_content, metadata, state) do
    if session_id == state.active_session_id do
      handle_active_stream_end(session_id, full_content, metadata, state)
    else
      handle_inactive_stream_end(session_id, metadata, state)
    end
  end

  # Active session: Complete message and update UI with usage tracking
  defp handle_active_stream_end(session_id, _full_content, metadata, state) do
    # Get streaming message from active session's UI state
    ui_state = Model.get_active_ui_state(state)
    streaming_message = if ui_state, do: ui_state.streaming_message || "", else: ""

    # Extract usage from metadata
    usage = extract_usage(metadata)

    # Create message with usage attached
    message = %{
      id: generate_message_id(),
      role: :assistant,
      content: streaming_message,
      timestamp: DateTime.utc_now(),
      usage: usage
    }

    queue = queue_message(state.message_queue, {:stream_end, streaming_message})

    # Update active session's UI state: end streaming, accumulate usage, add message
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        new_conversation_view =
          if ui.conversation_view do
            ConversationView.end_streaming(ui.conversation_view)
          else
            ui.conversation_view
          end

        # Accumulate usage totals for this session
        current_usage = Map.get(ui, :usage) || @default_usage
        accumulated_usage = accumulate_usage(current_usage, usage)

        # Add message to session's messages, update usage, clear streaming state
        # Use Map.put for :usage since it may not exist in legacy ui_state maps
        ui
        |> Map.merge(%{
          conversation_view: new_conversation_view,
          streaming_message: nil,
          is_streaming: false,
          messages: [message | ui.messages],
          agent_activity: :idle
        })
        |> Map.put(:usage, accumulated_usage)
      end)

    # Clear streaming indicator (kept at model level for sidebar indicators)
    new_streaming_sessions = MapSet.delete(new_state.streaming_sessions, session_id)
    new_last_activity = Map.put(new_state.last_activity, session_id, DateTime.utc_now())

    final_state =
      %{
        new_state
        | message_queue: queue,
          streaming_sessions: new_streaming_sessions,
          last_activity: new_last_activity
      }
      |> Model.set_active_agent_status(:idle)

    {final_state, []}
  end

  # Inactive session: Finalize message in session's ConversationView, increment unread count
  defp handle_inactive_stream_end(session_id, metadata, state) do
    # Get streaming message from the inactive session's UI state
    session_ui = Model.get_session_ui_state(state, session_id)
    streaming_message = if session_ui, do: session_ui.streaming_message || "", else: ""

    # Extract usage from metadata
    usage = extract_usage(metadata)

    # Create message with usage attached
    message = %{
      id: generate_message_id(),
      role: :assistant,
      content: streaming_message,
      timestamp: DateTime.utc_now(),
      usage: usage
    }

    # Update the inactive session's UI state: finalize ConversationView, add message, accumulate usage
    new_state =
      Model.update_session_ui_state(state, session_id, fn ui ->
        new_conversation_view =
          if ui.conversation_view do
            ConversationView.end_streaming(ui.conversation_view)
          else
            ui.conversation_view
          end

        # Accumulate usage totals for this session
        current_usage = Map.get(ui, :usage) || @default_usage
        accumulated_usage = accumulate_usage(current_usage, usage)

        # Add message to session's messages, update usage, clear streaming state
        # Use Map.put for :usage since it may not exist in legacy ui_state maps
        ui
        |> Map.merge(%{
          conversation_view: new_conversation_view,
          streaming_message: nil,
          is_streaming: false,
          messages: [message | ui.messages],
          agent_activity: :idle
        })
        |> Map.put(:usage, accumulated_usage)
      end)

    # Clear streaming indicator (kept at model level for sidebar indicators)
    new_streaming_sessions = MapSet.delete(new_state.streaming_sessions, session_id)

    # Increment unread count (new message arrived in background)
    current_count = Map.get(new_state.unread_counts, session_id, 0)
    new_unread_counts = Map.put(new_state.unread_counts, session_id, current_count + 1)

    new_last_activity = Map.put(new_state.last_activity, session_id, DateTime.utc_now())

    final_state = %{
      new_state
      | streaming_sessions: new_streaming_sessions,
        unread_counts: new_unread_counts,
        last_activity: new_last_activity
    }

    {final_state, []}
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

    new_state =
      %{
        state
        | messages: [error_msg | state.messages],
          streaming_message: nil,
          is_streaming: false,
          message_queue: queue,
          conversation_view: new_conversation_view
      }
      |> Model.set_active_agent_status(:error)

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
    new_state = Model.set_active_agent_status(%{state | message_queue: queue}, status)
    {new_state, []}
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

    new_state =
      Model.set_active_agent_status(
        %{state | config: new_config, message_queue: queue},
        new_status
      )

    {new_state, []}
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

    # Add reasoning step to active session's UI state
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        %{ui | reasoning_steps: [step | ui.reasoning_steps]}
      end)

    {%{new_state | message_queue: queue}, []}
  end

  @doc """
  Clears all reasoning steps.
  """
  @spec handle_clear_reasoning_steps(Model.t()) :: {Model.t(), list()}
  def handle_clear_reasoning_steps(state) do
    new_state =
      Model.update_active_ui_state(state, fn ui ->
        %{ui | reasoning_steps: []}
      end)

    {new_state, []}
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

  Two-tier update system (Phase 4.7.3):
  - Active session: Full update (add to tool_calls list), increment tool count
  - Inactive session: Increment tool count for sidebar badge
  """
  @spec handle_tool_call(String.t(), String.t(), map(), String.t(), Model.t()) ::
          {Model.t(), list()}
  def handle_tool_call(session_id, tool_name, params, call_id, state) do
    if session_id == state.active_session_id do
      handle_active_tool_call(session_id, tool_name, params, call_id, state)
    else
      handle_inactive_tool_call(session_id, tool_name, state)
    end
  end

  # Active session: Full update
  defp handle_active_tool_call(session_id, tool_name, params, call_id, state) do
    tool_call_entry = %{
      call_id: call_id,
      tool_name: tool_name,
      params: params,
      result: nil,
      timestamp: DateTime.utc_now()
    }

    queue = queue_message(state.message_queue, {:tool_call, tool_name, params, call_id})

    # Add tool call to active session's UI state and set agent_activity
    updated_state =
      Model.update_active_ui_state(state, fn ui ->
        %{
          ui
          | tool_calls: [tool_call_entry | ui.tool_calls],
            agent_activity: {:tool_executing, tool_name}
        }
      end)

    # Track active tools (kept at model level for sidebar indicators)
    current_count = Map.get(updated_state.active_tools, session_id, 0)
    new_active_tools = Map.put(updated_state.active_tools, session_id, current_count + 1)
    new_last_activity = Map.put(updated_state.last_activity, session_id, DateTime.utc_now())

    new_state = %{
      updated_state
      | message_queue: queue,
        active_tools: new_active_tools,
        last_activity: new_last_activity
    }

    {new_state, []}
  end

  # Inactive session: Increment tool count for badge and set agent_activity
  defp handle_inactive_tool_call(session_id, tool_name, state) do
    # Update session's agent_activity
    updated_state =
      Model.update_session_ui_state(state, session_id, fn ui ->
        %{ui | agent_activity: {:tool_executing, tool_name}}
      end)

    current_count = Map.get(updated_state.active_tools, session_id, 0)
    new_active_tools = Map.put(updated_state.active_tools, session_id, current_count + 1)
    new_last_activity = Map.put(updated_state.last_activity, session_id, DateTime.utc_now())

    new_state = %{
      updated_state
      | active_tools: new_active_tools,
        last_activity: new_last_activity
    }

    {new_state, []}
  end

  @doc """
  Handles a tool result.

  Two-tier update system (Phase 4.7.3):
  - Active session: Full update (update tool_calls list), decrement tool count
  - Inactive session: Decrement tool count for sidebar badge
  """
  @spec handle_tool_result(String.t(), Result.t(), Model.t()) :: {Model.t(), list()}
  def handle_tool_result(session_id, %Result{} = result, state) do
    if session_id == state.active_session_id do
      handle_active_tool_result(session_id, result, state)
    else
      handle_inactive_tool_result(session_id, state)
    end
  end

  # Active session: Full update
  defp handle_active_tool_result(session_id, result, state) do
    queue = queue_message(state.message_queue, {:tool_result, result})

    # Update tool call result in active session's UI state and set agent_activity
    updated_state =
      Model.update_active_ui_state(state, fn ui ->
        updated_tool_calls =
          Enum.map(ui.tool_calls, fn entry ->
            if entry.call_id == result.tool_call_id do
              %{entry | result: result}
            else
              entry
            end
          end)

        # After tool completes, set activity based on streaming state
        # If still streaming, go back to thinking; otherwise idle
        new_activity =
          if ui.is_streaming do
            {:thinking, :chat}
          else
            :idle
          end

        %{ui | tool_calls: updated_tool_calls, agent_activity: new_activity}
      end)

    # Decrement active tools (kept at model level for sidebar indicators)
    current_count = Map.get(updated_state.active_tools, session_id, 0)
    new_active_tools = Map.put(updated_state.active_tools, session_id, max(0, current_count - 1))
    new_last_activity = Map.put(updated_state.last_activity, session_id, DateTime.utc_now())

    new_state = %{
      updated_state
      | message_queue: queue,
        active_tools: new_active_tools,
        last_activity: new_last_activity
    }

    {new_state, []}
  end

  # Inactive session: Decrement tool count and set agent_activity
  defp handle_inactive_tool_result(session_id, state) do
    # Update session's agent_activity based on streaming state
    updated_state =
      Model.update_session_ui_state(state, session_id, fn ui ->
        new_activity =
          if ui.is_streaming do
            {:thinking, :chat}
          else
            :idle
          end

        %{ui | agent_activity: new_activity}
      end)

    current_count = Map.get(updated_state.active_tools, session_id, 0)
    new_active_tools = Map.put(updated_state.active_tools, session_id, max(0, current_count - 1))
    new_last_activity = Map.put(updated_state.last_activity, session_id, DateTime.utc_now())

    new_state = %{
      updated_state
      | active_tools: new_active_tools,
        last_activity: new_last_activity
    }

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

  # ============================================================================
  # Usage Tracking Helpers
  # ============================================================================

  @doc """
  Returns the default usage map for initialization.
  """
  @spec default_usage() :: map()
  def default_usage, do: @default_usage

  @doc """
  Extracts usage information from stream metadata.

  The metadata from ReqLLM may contain usage in various formats:
  - `%{usage: %{input_tokens: n, output_tokens: n, total_cost: n}}`
  - `%{usage: %{input: n, output: n, total_cost: n}}`
  - `%{usage: %{"input_tokens" => n, "output_tokens" => n}}`

  Returns nil if no usage data is found.
  """
  @spec extract_usage(map() | nil) :: map() | nil
  def extract_usage(nil), do: nil

  def extract_usage(metadata) when is_map(metadata) do
    case metadata[:usage] || metadata["usage"] do
      nil ->
        nil

      usage when is_map(usage) ->
        # Normalize various key formats
        input = get_token_value(usage, [:input_tokens, :input, "input_tokens", "input"])
        output = get_token_value(usage, [:output_tokens, :output, "output_tokens", "output"])
        cost = get_cost_value(usage)

        %{
          input_tokens: input,
          output_tokens: output,
          total_cost: cost
        }

      _ ->
        nil
    end
  end

  def extract_usage(_), do: nil

  @doc """
  Accumulates usage from a new message into existing cumulative usage.

  If new_usage is nil, returns the current usage unchanged.
  """
  @spec accumulate_usage(map(), map() | nil) :: map()
  def accumulate_usage(current, nil), do: current

  def accumulate_usage(current, new_usage) when is_map(current) and is_map(new_usage) do
    %{
      input_tokens: (current[:input_tokens] || 0) + (new_usage[:input_tokens] || 0),
      output_tokens: (current[:output_tokens] || 0) + (new_usage[:output_tokens] || 0),
      total_cost: (current[:total_cost] || 0.0) + (new_usage[:total_cost] || 0.0)
    }
  end

  def accumulate_usage(current, _), do: current

  @doc """
  Formats usage for display in status bar.

  Example: "🎟️ 150 in / 342 out | $0.0023"
  """
  @spec format_usage_compact(map() | nil) :: String.t()
  def format_usage_compact(nil), do: "🎟️ 0 in / 0 out"

  def format_usage_compact(%{input_tokens: in_t, output_tokens: out_t, total_cost: cost})
      when is_number(in_t) and is_number(out_t) do
    cost_str = format_cost(cost)
    "🎟️ #{in_t} in / #{out_t} out | #{cost_str}"
  end

  def format_usage_compact(_), do: "🎟️ 0 in / 0 out"

  @doc """
  Formats usage for display above a message (detailed format).

  Example: "🎟️ 150 in / 342 out | Cost: $0.0023"
  """
  @spec format_usage_detailed(map() | nil) :: String.t()
  def format_usage_detailed(nil), do: ""

  def format_usage_detailed(%{input_tokens: in_t, output_tokens: out_t, total_cost: cost})
      when is_number(in_t) and is_number(out_t) do
    cost_str = format_cost(cost)
    "🎟️ #{in_t} in / #{out_t} out | Cost: #{cost_str}"
  end

  def format_usage_detailed(_), do: ""

  # Private helpers for usage extraction

  defp get_token_value(usage, keys) when is_list(keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(usage, key) do
        nil -> nil
        val when is_number(val) -> val
        _ -> nil
      end
    end)
  end

  defp get_cost_value(usage) do
    cost =
      Map.get(usage, :total_cost) ||
        Map.get(usage, "total_cost") ||
        Map.get(usage, :cost) ||
        Map.get(usage, "cost") ||
        0.0

    if is_number(cost), do: cost, else: 0.0
  end

  defp format_cost(cost) when is_number(cost) and cost > 0 do
    "$#{:erlang.float_to_binary(cost * 1.0, decimals: 4)}"
  end

  defp format_cost(_), do: "$0.0000"
end
