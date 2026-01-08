defmodule Mix.Tasks.JidoClaude do
  @moduledoc """
  Starts an interactive Claude Code session.

  ## Usage

      mix jido_claude "Analyze this codebase"
      mix jido_claude --model opus "Review the authentication system"
      mix jido_claude --cwd /path/to/project "Fix the failing tests"

  ## Options

    * `--model` - Claude model to use ("haiku", "sonnet", "opus"). Default: "sonnet"
    * `--max-turns` - Maximum agentic loop iterations. Default: 25
    * `--cwd` - Working directory for tools. Default: current directory
    * `--tools` - Comma-separated list of allowed tools. Default: "Read,Glob,Grep,Bash"
    * `--debug` - Show debug output for message processing

  ## Examples

      # Basic usage
      mix jido_claude "What does this project do?"

      # With specific model
      mix jido_claude --model opus "Refactor this module for better performance"

      # With custom working directory
      mix jido_claude --cwd ./my_project "Run the tests and fix any failures"

  """

  use Mix.Task

  alias ClaudeAgentSDK.{Options, Message}

  require Logger

  @shortdoc "Start an interactive Claude Code session"

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_claude)

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          model: :string,
          max_turns: :integer,
          cwd: :string,
          tools: :string,
          debug: :boolean
        ]
      )

    prompt = parse_prompt(positional)

    if prompt == "" do
      Mix.shell().error("Error: prompt is required")
      Mix.shell().info("\nUsage: mix jido_claude \"Your prompt here\"")
      exit({:shutdown, 1})
    end

    options = build_options(opts)
    debug? = Keyword.get(opts, :debug, false)

    Mix.shell().info("Starting Claude session...")
    Mix.shell().info("  Model: #{options.model}")
    Mix.shell().info("  Working directory: #{options.cwd}")
    Mix.shell().info("  Max turns: #{options.max_turns}")
    Mix.shell().info("")

    run_session(prompt, options, debug?)
  end

  defp parse_prompt([]), do: ""
  defp parse_prompt(positional), do: Enum.join(positional, " ")

  defp build_options(opts) do
    allowed_tools =
      case Keyword.get(opts, :tools) do
        nil -> ["Read", "Glob", "Grep", "Bash"]
        tools_str -> String.split(tools_str, ",", trim: true)
      end

    %Options{
      model: Keyword.get(opts, :model, "sonnet"),
      max_turns: Keyword.get(opts, :max_turns, 25),
      allowed_tools: allowed_tools,
      cwd: Keyword.get(opts, :cwd, File.cwd!()),
      timeout_ms: 600_000
    }
  end

  defp run_session(prompt, options, debug?) do
    prompt
    |> ClaudeAgentSDK.query(options)
    |> Stream.each(&handle_message(&1, debug?))
    |> Stream.run()

    Mix.shell().info("\n✓ Session complete")
  rescue
    e ->
      Mix.shell().error("\nError: #{Exception.message(e)}")
      exit({:shutdown, 1})
  end

  defp handle_message(%Message{type: :system, subtype: :init, data: data}, _debug?) do
    Mix.shell().info("Session initialized (#{data[:model]})")
    Mix.shell().info("─────────────────────────────────────────")
  end

  defp handle_message(%Message{type: :assistant} = msg, debug?) do
    if debug? do
      Mix.shell().info("\n[DEBUG] Assistant message:")
      Mix.shell().info("  raw: #{inspect(msg.raw, pretty: true, limit: 500)}")
      Mix.shell().info("  data: #{inspect(msg.data, pretty: true, limit: 500)}")
    end

    content_blocks = Message.content_blocks(msg)

    if debug? && content_blocks == [] do
      Mix.shell().info("  [DEBUG] No content blocks extracted")
    end

    Enum.each(content_blocks, fn
      %{type: :text, text: text} when is_binary(text) ->
        IO.write(text)

      %{type: :tool_use, name: name, input: input} ->
        Mix.shell().info("\n🔧 Tool: #{name}")
        Mix.shell().info("   Input: #{inspect(input, limit: 100)}")

      other ->
        if debug?, do: Mix.shell().info("  [DEBUG] Unhandled block: #{inspect(other)}")
    end)
  end

  defp handle_message(%Message{type: :user, subtype: :tool_result, data: data}, _debug?) do
    status = if data[:is_error], do: "❌", else: "✓"
    Mix.shell().info("   #{status} Result received")
  end

  defp handle_message(%Message{type: :result, subtype: :success, data: data}, _debug?) do
    Mix.shell().info("\n─────────────────────────────────────────")
    Mix.shell().info("Session completed successfully")

    if data[:total_cost_usd] do
      Mix.shell().info("Total cost: $#{Float.round(data[:total_cost_usd], 4)}")
    end
  end

  defp handle_message(%Message{type: :result, subtype: subtype, data: data}, _debug?)
       when subtype in [:error_max_turns, :error_sdk, :error_exception] do
    Mix.shell().error("\n─────────────────────────────────────────")
    Mix.shell().error("Session error: #{data[:error] || inspect(subtype)}")
  end

  defp handle_message(msg, debug?) do
    if debug? do
      Mix.shell().info("[DEBUG] Unhandled message type: #{msg.type}/#{msg.subtype}")
    end
  end
end
