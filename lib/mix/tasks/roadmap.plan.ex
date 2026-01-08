defmodule Mix.Tasks.Roadmap.Plan do
  @moduledoc """
  Generate a plan for a roadmap item using LLM.

  ## Usage

      mix roadmap.plan 001-jido-core/001-hand-review
      mix roadmap.plan <item-id> --no-llm-prd

  Requires the item to be in `researched` state.
  Produces `plan.md` and `prd.yaml` (or `prd.json`) in the item folder.
  Transitions state to `planned`.

  ## PRD Generation

  By default, the PRD is generated using LLM to extract structured user stories.
  Use `--no-llm-prd` to fall back to heuristic extraction.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.LLM
  alias JidoWorkspace.Roadmap
  alias JidoWorkspace.Roadmap.PRD

  @shortdoc "Plan a roadmap item"

  @switches [llm_prd: :boolean]

  def run([item_id | rest]) do
    {opts, _} = OptionParser.parse!(rest, switches: @switches)
    use_llm_prd = Keyword.get(opts, :llm_prd, true)

    case Roadmap.load_item(item_id) do
      {:ok, item} ->
        if item["state"] != "researched" do
          Mix.raise("Item must be in 'researched' state to plan. Current: #{item["state"]}")
        end

        run_plan(item, use_llm_prd: use_llm_prd)

      {:error, _} ->
        Mix.raise("Item not found: #{item_id}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix roadmap.plan <item-id>")

  defp run_plan(item, opts) do
    item_dir = Path.join(Roadmap.base_path(), item["id"])
    research_path = Path.join(item_dir, "research.md")
    plan_path = Path.join(item_dir, "plan.md")

    unless File.exists?(research_path) do
      Mix.raise("Research file not found: #{research_path}")
    end

    Logger.info("Planning: #{item["title"]}")

    prompt = "/plan #{research_path}"

    Logger.info("Running LLM with: #{prompt}")

    result = LLM.run(prompt, on_chunk: &IO.write/1)

    File.write!(plan_path, result)
    Logger.info("\nSaved plan to: #{plan_path}")

    prd = PRD.generate(item, result, use_llm: opts[:use_llm_prd])
    PRD.save(item_dir, prd)
    Logger.info("Saved PRD")

    {:ok, updated} = Roadmap.transition_item(item, "planned")
    Roadmap.save_item(updated)

    Logger.info("Item transitioned to 'planned'")
  end
end
