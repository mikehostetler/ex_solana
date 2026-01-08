defmodule Mix.Tasks.Roadmap.Implement do
  @moduledoc """
  Run the Ralph loop to implement a roadmap item.

  ## Usage

      mix roadmap.implement 001-jido-core/001-hand-review
      mix roadmap.implement <item-id> --max-iterations 20

  Requires the item to be in `checked_out` state.
  Runs the Ralph loop using the generated `prompt.md`.
  Transitions state to `implementing`.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.LLM
  alias JidoWorkspace.Roadmap

  @shortdoc "Implement a roadmap item via Ralph loop"

  @switches [max_iterations: :integer]

  def run(args) do
    {opts, [item_id | _]} = OptionParser.parse!(args, switches: @switches)

    case Roadmap.load_item(item_id) do
      {:ok, item} ->
        unless item["state"] in ["checked_out", "implementing"] do
          Mix.raise(
            "Item must be in 'checked_out' or 'implementing' state. Current: #{item["state"]}"
          )
        end

        max_iterations = opts[:max_iterations] || 10
        run_implement(item, max_iterations)

      {:error, _} ->
        Mix.raise("Item not found: #{item_id}")
    end
  end

  defp run_implement(item, max_iterations) do
    item_dir = Path.join(Roadmap.base_path(), item["id"])
    prompt_path = Path.join(item_dir, "prompt.md")
    progress_path = Path.join(item_dir, "progress.txt")

    unless File.exists?(prompt_path) do
      Mix.raise("Prompt file not found: #{prompt_path}. Run `mix roadmap.checkout` first.")
    end

    expected_branch = item["branch"]
    ensure_correct_branch(expected_branch)

    if item["state"] == "checked_out" do
      {:ok, updated} = Roadmap.transition_item(item, "implementing")
      Roadmap.save_item(updated)
    end

    Logger.info("Starting Ralph loop for: #{item["title"]}")
    Logger.info("Max iterations: #{max_iterations}")
    Logger.info("Prompt: #{prompt_path}")

    File.write!(progress_path, "Started: #{DateTime.utc_now() |> DateTime.to_iso8601()}\n\n")

    prompt_content = File.read!(prompt_path)
    result = run_ralph_loop(prompt_content, progress_path, max_iterations)

    case result do
      :complete ->
        Logger.info("Ralph loop completed successfully!")
        Mix.shell().info("\nNext: mix roadmap.pr #{item["id"]}")

      :max_iterations ->
        Logger.warning("Max iterations reached. Review progress and run again if needed.")

      {:error, reason} ->
        Logger.error("Ralph loop failed: #{reason}")
    end
  end

  defp ensure_correct_branch(expected_branch) do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {current, 0} ->
        current = String.trim(current)

        if current != expected_branch do
          Logger.warning("Expected branch #{expected_branch}, currently on #{current}")
          Logger.info("Switching to #{expected_branch}...")
          System.cmd("git", ["switch", expected_branch])
        end

      _ ->
        :ok
    end
  end

  defp run_ralph_loop(prompt, progress_path, max_iterations) do
    Enum.reduce_while(1..max_iterations, :continue, fn iteration, _acc ->
      Logger.info("═══ Iteration #{iteration} ═══")

      File.write!(
        progress_path,
        "Iteration #{iteration}: #{DateTime.utc_now() |> DateTime.to_iso8601()}\n",
        [:append]
      )

      result = LLM.run(prompt, on_chunk: &IO.write/1)

      if String.contains?(result, "<promise>COMPLETE</promise>") do
        File.write!(progress_path, "COMPLETED at iteration #{iteration}\n", [:append])
        {:halt, :complete}
      else
        Process.sleep(2000)
        {:cont, :continue}
      end
    end)
    |> case do
      :continue -> :max_iterations
      result -> result
    end
  end
end
