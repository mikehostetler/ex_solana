defmodule Mix.Tasks.Claude.Test do
  use Mix.Task

  alias ClaudeAgentSDK.{Options, Message}

  @shortdoc "Test Claude Agent SDK - streams multi-turn conversation progress"

  @moduledoc """
  Sends a prompt to Claude and streams all events showing real-time progress.

  The SDK returns a stream of Message structs as they arrive, allowing you to
  see tool calls, text responses, and results in real-time - even for long
  running conversations that take several minutes.

  ## Usage

      mix claude.test [prompt]
      mix claude.test --verbose [prompt]     # Also show text responses
      mix claude.test --turns 20 [prompt]    # Increase max turns (default: 15)

  ## Examples

      mix claude.test "Tell me about this project"
      mix claude.test -v -t 25 "Analyze the codebase and suggest improvements"
  """

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:claude_agent_sdk)

    {opts, remaining, _} =
      OptionParser.parse(args,
        switches: [verbose: :boolean, turns: :integer],
        aliases: [v: :verbose, t: :turns]
      )

    verbose = opts[:verbose] || false
    max_turns = opts[:turns] || 15

    prompt = Enum.join(remaining, " ") |> String.trim()
    prompt = if prompt == "", do: "What is Elixir? Reply in 2 sentences.", else: prompt

    Mix.shell().info("Prompt: #{prompt}\n")

    options = %Options{
      model: "sonnet",
      max_turns: max_turns,
      allowed_tools: ["Read", "Glob", "Grep", "Bash"],
      cwd: File.cwd!()
    }

    prompt
    |> ClaudeAgentSDK.query(options)
    |> Stream.each(fn message -> handle_message(message, verbose) end)
    |> Stream.run()
  end

  defp handle_message(%Message{type: :system, subtype: :init, data: data}, _verbose) do
    IO.puts("⚙ Session started (#{data.model})")
  end

  defp handle_message(%Message{type: :assistant} = msg, verbose) do
    msg
    |> Message.content_blocks()
    |> Enum.each(fn
      %{type: :text, text: text} ->
        if verbose do
          preview = text |> String.slice(0, 100) |> String.replace("\n", " ")
          IO.puts("💬 #{preview}...")
        end

      %{type: :tool_use, name: name, input: input} ->
        input_preview = input |> inspect() |> String.slice(0, 50)
        IO.puts("🔧 #{name}: #{input_preview}")

      _ ->
        :ok
    end)
  end

  defp handle_message(%Message{type: :user, data: data}, verbose) do
    if verbose do
      tool_result = get_in(data, [:raw, "tool_use_result"])

      if tool_result do
        duration = tool_result["durationMs"]
        if duration, do: IO.puts("  ✓ (#{round(duration)}ms)")
      end
    end
  end

  defp handle_message(%Message{type: :result, data: data} = msg, verbose) do
    IO.puts("\n" <> String.duplicate("─", 60))

    cond do
      data[:result] && data.result != "" ->
        IO.puts("\n#{data.result}")

      msg.subtype == :error_max_turns ->
        IO.puts("\n⚠ Hit max_turns limit - increase max_turns for longer tasks")

      true ->
        if verbose, do: IO.puts("\n[No final text - check raw: #{inspect(Map.keys(data))}]")
    end

    IO.puts("\n" <> String.duplicate("─", 60))

    turns = data[:num_turns] && round(data.num_turns)
    cost = data[:total_cost_usd] && Float.round(data.total_cost_usd, 4)
    duration = data[:duration_ms] && round(data.duration_ms / 1000)

    IO.puts("✓ Done | Turns: #{turns || "?"} | Cost: $#{cost || "?"} | Time: #{duration || "?"}s")
  end

  defp handle_message(_msg, _verbose), do: :ok
end
