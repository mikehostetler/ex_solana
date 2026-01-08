defmodule JidoClaude.StreamRunner do
  @moduledoc """
  Task that runs ClaudeAgentSDK.query/3 and dispatches each message
  as a signal to the owning ClaudeSessionAgent.

  This module is spawned as a fire-and-forget Task by the StartSession action.
  It handles the streaming SDK messages and converts them to internal signals
  that the ClaudeSessionAgent processes via HandleMessage.
  """

  alias ClaudeAgentSDK.{Options, Message}
  alias Jido.Signal

  require Logger

  @doc """
  Runs a Claude session and dispatches messages to the agent.

  ## Parameters

    * `agent_pid` - PID of the ClaudeSessionAgent to dispatch to
    * `prompt` - The prompt to send to Claude
    * `options` - ClaudeAgentSDK.Options struct

  """
  def run(%{agent_pid: agent_pid, prompt: prompt, options: options}) do
    Application.ensure_all_started(:claude_agent_sdk)

    sdk_options = build_sdk_options(options)

    prompt
    |> ClaudeAgentSDK.query(sdk_options)
    |> Stream.each(fn message ->
      dispatch_message(agent_pid, message)
    end)
    |> Stream.run()
  rescue
    e ->
      Logger.error("StreamRunner error: #{Exception.message(e)}")
      error_signal = build_error_signal(e, __STACKTRACE__)
      Jido.Signal.Dispatch.dispatch(error_signal, {:pid, target: agent_pid})
  end

  defp build_sdk_options(options) when is_struct(options, Options), do: options

  defp build_sdk_options(options) when is_map(options) do
    %Options{
      model: options[:model] || "sonnet",
      max_turns: options[:max_turns] || 25,
      allowed_tools: options[:allowed_tools] || ["Read", "Glob", "Grep", "Bash"],
      cwd: options[:cwd] || File.cwd!(),
      system_prompt: options[:system_prompt],
      timeout_ms: options[:timeout_ms] || 600_000
    }
  end

  defp dispatch_message(agent_pid, %Message{} = msg) do
    signal = build_message_signal(msg)
    Jido.Signal.Dispatch.dispatch(signal, {:pid, target: agent_pid})
  end

  defp build_message_signal(%Message{type: type, subtype: subtype, data: data, raw: raw}) do
    Signal.new!(
      "claude.internal.message",
      %{
        type: type,
        subtype: subtype,
        data: data,
        raw: raw
      },
      source: "/claude/stream_runner"
    )
  end

  defp build_error_signal(exception, stacktrace) do
    Signal.new!(
      "claude.internal.message",
      %{
        type: :result,
        subtype: :error_exception,
        data: %{
          error: Exception.message(exception),
          stacktrace: Exception.format_stacktrace(stacktrace)
        },
        raw: nil
      },
      source: "/claude/stream_runner"
    )
  end
end
