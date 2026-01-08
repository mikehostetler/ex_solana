defmodule JidoClaude.Actions.HandleMessage do
  @moduledoc """
  Process a message from the Claude SDK stream.

  This action handles internal messages dispatched by the StreamRunner
  and converts them into:
  1. State updates for the ClaudeSessionAgent
  2. Parent-facing signals for orchestration

  ## Message Types

    * `:system/:init` - Session initialized with model info
    * `:assistant` - Claude's response with text and/or tool calls
    * `:user` - Tool execution results
    * `:result/:success` - Session completed successfully
    * `:result/:error_*` - Session failed

  ## Parameters

    * `type` - Required. Message type atom.
    * `subtype` - Optional. Message subtype atom.
    * `data` - Optional. Message-specific data map.
    * `raw` - Optional. Original JSON from CLI.

  """

  use Jido.Action,
    name: "claude_handle_message",
    description: "Process a message from Claude SDK stream",
    schema: [
      type: [type: :atom, required: true],
      subtype: [type: :atom, default: nil],
      data: [type: :map, default: %{}],
      raw: [type: :any, default: nil]
    ]

  alias Jido.Agent.Directive
  alias JidoClaude.Signals

  @impl true
  def run(params, context) do
    agent = context[:agent]
    session_id = get_session_id(agent, context)

    {state_update, parent_signals, terminal?} =
      process_message(params, agent, session_id)

    directives = build_directives(agent, parent_signals, terminal?)

    {:ok, state_update, directives}
  end

  defp get_session_id(agent, context) do
    cond do
      context[:session_id] -> context.session_id
      agent && agent.state[:session_id] -> agent.state.session_id
      true -> nil
    end
  end

  defp process_message(%{type: :system, subtype: :init, data: data}, _agent, _session_id) do
    state = %{
      session_id: data[:session_id],
      model: data[:model]
    }

    signal = Signals.session_started(data)
    {state, [signal], false}
  end

  defp process_message(%{type: :assistant, raw: raw}, agent, session_id) do
    content_blocks = extract_content_blocks(raw)
    current_turns = if agent, do: agent.state.turns, else: 0
    current_transcript = if agent, do: agent.state.transcript, else: []

    state = %{
      turns: current_turns + 1,
      transcript: current_transcript ++ [{:assistant, content_blocks}]
    }

    signals =
      content_blocks
      |> Enum.map(fn
        %{type: :text} = block -> Signals.assistant_text(session_id, block)
        %{type: :tool_use} = block -> Signals.tool_use(session_id, block)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {state, signals, false}
  end

  defp process_message(%{type: :user, data: data}, agent, session_id) do
    current_transcript = if agent, do: agent.state.transcript, else: []

    state = %{
      transcript: current_transcript ++ [{:user, data}]
    }

    signal = Signals.tool_result(session_id, data)
    {state, [signal], false}
  end

  defp process_message(%{type: :result, subtype: :success, data: data}, _agent, _session_id) do
    state = %{
      status: :success,
      result: data[:result],
      cost_usd: data[:total_cost_usd]
    }

    signal = Signals.session_success(data)
    {state, [signal], true}
  end

  defp process_message(%{type: :result, subtype: subtype, data: data}, _agent, session_id)
       when subtype in [:error_max_turns, :error_exception, :error_timeout] do
    state = %{
      status: :failure,
      error: %{type: subtype, details: data}
    }

    signal = Signals.session_error(session_id, subtype, data)
    {state, [signal], true}
  end

  defp process_message(_msg, _agent, _session_id) do
    {%{}, [], false}
  end

  defp build_directives(agent, signals, terminal?) do
    signal_directives =
      signals
      |> Enum.map(fn signal ->
        if agent do
          Directive.emit_to_parent(agent, signal)
        else
          Directive.emit(signal)
        end
      end)
      |> Enum.reject(&is_nil/1)

    if terminal? do
      signal_directives ++ [Directive.stop(:normal)]
    else
      signal_directives
    end
  end

  defp extract_content_blocks(%{"message" => %{"content" => content}}) when is_list(content) do
    Enum.map(content, fn
      %{"type" => "text", "text" => text} ->
        %{type: :text, text: text}

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        %{type: :tool_use, name: name, input: input}

      other ->
        %{type: :unknown, raw: other}
    end)
  end

  defp extract_content_blocks(_), do: []
end
