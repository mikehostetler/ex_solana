defmodule Mix.Tasks.Claude.Test do
  use Mix.Task

  @shortdoc "Test Claude Code SDK integration with live streaming"

  @moduledoc """
  Sends a prompt to Claude Code and streams output in real-time.
  Usage: mix claude.test [prompt]
  Default prompt: /cost
  """

  @impl Mix.Task
  def run(args) do
    prompt = Enum.join(args, " ") |> String.trim()
    prompt = if prompt == "", do: "/cost", else: prompt

    Mix.shell().info("Prompt: #{prompt}")
    Mix.shell().info("Streaming output...\n")

    args = ["--print", prompt, "--output-format", "stream-json", "--verbose"]

    port =
      Port.open({:spawn_executable, System.find_executable("claude")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    stream_output(port, "")
  end

  defp stream_output(port, buffer) do
    receive do
      {^port, {:data, data}} ->
        new_buffer = buffer <> data
        {lines, remaining} = split_lines(new_buffer)

        Enum.each(lines, fn line ->
          case Jason.decode(line) do
            {:ok, %{"type" => "assistant", "message" => %{"content" => content}}} ->
              content
              |> Enum.filter(&(&1["type"] == "text"))
              |> Enum.each(&IO.write(&1["text"]))

            {:ok, %{"type" => "result"}} ->
              :ok

            {:ok, other} ->
              IO.puts("\n[#{other["type"]}]")

            {:error, _} ->
              IO.write(line)
          end
        end)

        stream_output(port, remaining)

      {^port, {:exit_status, 0}} ->
        IO.puts("\n✓ Done")

      {^port, {:exit_status, status}} ->
        IO.puts("\n✗ Exit status: #{status}")
    after
      600_000 ->
        Port.close(port)
        IO.puts("\n✗ Timeout")
    end
  end

  defp split_lines(data) do
    lines = String.split(data, "\n")
    {Enum.drop(lines, -1), List.last(lines) || ""}
  end
end
