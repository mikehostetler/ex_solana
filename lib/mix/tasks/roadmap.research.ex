defmodule Mix.Tasks.Roadmap.Research do
  @moduledoc """
  Run research on a roadmap item using Claude Code CLI.

  ## Usage

      mix roadmap.research <item-id>

  This sends the `/research` prompt to Claude Code with the item path,
  and saves the output to `research.md` in the item folder.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap

  @shortdoc "Research a roadmap item via Claude Code"

  @timeout_ms 600_000

  def run([item_id]) do
    case Roadmap.load_item(item_id) do
      {:ok, item} ->
        research_item(item)

      {:error, reason} ->
        Mix.shell().error("Failed to load item #{item_id}: #{inspect(reason)}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix roadmap.research <item-id>")
  end

  defp research_item(item) do
    item_id = item[:id]
    item_path = Path.join([".roadmap", item_id, "item.json"])

    Mix.shell().info("Researching: #{item[:title]}")
    Mix.shell().info("Item path: #{item_path}")

    prompt = "/research Research the following roadmap item: #{item_path}"

    Mix.shell().info("Sending prompt to Claude Code (timeout: #{div(@timeout_ms, 60_000)} min)...")

    case run_claude_cli(prompt) do
      {:ok, result} ->
        research_path = Path.join([".roadmap", item_id, "research.md"])
        File.write!(research_path, result)
        Mix.shell().info("Research saved to: #{research_path}")

        updated_item = Map.put(item, :state, :researched)
        Roadmap.save_item(updated_item)
        Mix.shell().info("Item state updated to: researched")

      {:error, reason} ->
        Mix.shell().error("Research failed: #{inspect(reason)}")
    end
  end

  defp run_claude_cli(prompt) do
    args = ["--print", prompt, "--output-format", "text"]

    port =
      Port.open({:spawn_executable, System.find_executable("claude")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    collect_output(port, "", @timeout_ms)
  end

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, acc <> data, timeout)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, status}} ->
        {:error, {:exit_status, status, acc}}
    after
      timeout ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end

