defmodule Mix.Tasks.Roadmap.Complete do
  @moduledoc """
  Mark a roadmap item as complete after PR is merged.

  ## Usage

      mix roadmap.complete 001-jido-core/001-hand-review
      mix roadmap.complete <item-id> --update-roadmap

  Requires the item to be in `in_pr` state.
  Transitions state to `done`.
  Optionally updates the checkbox in ROADMAP.md.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap

  @shortdoc "Mark a roadmap item as complete"

  @switches [update_roadmap: :boolean]

  def run(args) do
    {opts, [item_id | _]} = OptionParser.parse!(args, switches: @switches)

    case Roadmap.load_item(item_id) do
      {:ok, item} ->
        if item["state"] != "in_pr" do
          Mix.raise("Item must be in 'in_pr' state to complete. Current: #{item["state"]}")
        end

        run_complete(item, opts)

      {:error, _} ->
        Mix.raise("Item not found: #{item_id}")
    end
  end

  defp run_complete(item, opts) do
    Logger.info("Completing: #{item["title"]}")

    {:ok, updated} = Roadmap.transition_item(item, "done")
    Roadmap.save_item(updated)

    Logger.info("Item transitioned to 'done'")

    if opts[:update_roadmap] do
      update_roadmap_file(item)
    end

    Mix.shell().info("✓ #{item["title"]} completed!")
  end

  defp update_roadmap_file(item) do
    roadmap_path = "ROADMAP.md"

    cond do
      not File.exists?(roadmap_path) ->
        Logger.warning("ROADMAP.md not found, skipping update")

      is_nil(item["roadmap_line"]) ->
        Logger.warning("No roadmap line number recorded, skipping update")

      true ->
        line_num = item["roadmap_line"]
        content = File.read!(roadmap_path)
        lines = String.split(content, "\n")

        updated_lines =
          lines
          |> Enum.with_index(1)
          |> Enum.map(fn {line, idx} ->
            if idx == line_num do
              mark_complete(line)
            else
              line
            end
          end)

        File.write!(roadmap_path, Enum.join(updated_lines, "\n"))
        Logger.info("Updated ROADMAP.md line #{line_num}")
    end
  end

  defp mark_complete(line) do
    line
    |> String.replace("\\[ \\]", "\\[x\\]")
    |> String.replace("[ ]", "[x]")
  end
end
