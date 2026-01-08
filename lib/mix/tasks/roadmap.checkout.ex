defmodule Mix.Tasks.Roadmap.Checkout do
  @moduledoc """
  Checkout a roadmap item: claim it, create a branch, and generate prompt.md for Ralph.

  ## Usage

      mix roadmap.checkout 001-jido-core/001-hand-review
      mix roadmap.checkout <item-id> --assignee alice

  Requires the item to be in `planned` state.
  Creates a git branch and generates `prompt.md` for the Ralph loop.
  Transitions state to `checked_out`.
  """

  use Mix.Task
  require Logger

  alias JidoWorkspace.Roadmap
  alias JidoWorkspace.Roadmap.PRD

  @shortdoc "Checkout a roadmap item for implementation"

  @switches [assignee: :string]

  def run(args) do
    {opts, [item_id | _]} = OptionParser.parse!(args, switches: @switches)

    case Roadmap.load_item(item_id) do
      {:ok, item} ->
        if item["state"] != "planned" do
          Mix.raise("Item must be in 'planned' state to checkout. Current: #{item["state"]}")
        end

        assignee = opts[:assignee] || System.get_env("USER") || "unknown"
        run_checkout(item, assignee)

      {:error, _} ->
        Mix.raise("Item not found: #{item_id}")
    end
  end

  defp run_checkout(item, assignee) do
    item_dir = Path.join(Roadmap.base_path(), item["id"])
    plan_path = Path.join(item_dir, "plan.md")
    prompt_path = Path.join(item_dir, "prompt.md")

    case PRD.load(item_dir) do
      {:ok, prd} ->
        branch_name = prd["branchName"]

        Logger.info("Checking out: #{item["title"]}")
        Logger.info("Assignee: #{assignee}")
        Logger.info("Branch: #{branch_name}")

        create_branch(branch_name)

        plan_content = if File.exists?(plan_path), do: File.read!(plan_path), else: ""
        prompt_content = generate_prompt(item, prd, plan_content)
        File.write!(prompt_path, prompt_content)
        Logger.info("Generated: #{prompt_path}")

        {:ok, updated} =
          item
          |> Map.put("branch", branch_name)
          |> Map.put("assignee", assignee)
          |> Roadmap.transition_item("checked_out")

        Roadmap.save_item(updated)

        Logger.info("Item transitioned to 'checked_out'")
        Mix.shell().info("\nNext: mix roadmap.implement #{item["id"]}")

      {:error, _} ->
        Mix.raise("PRD file not found in #{item_dir}. Run `mix roadmap.plan` first.")
    end
  end

  defp create_branch(branch_name) do
    case System.cmd("git", ["switch", "-c", branch_name], stderr_to_stdout: true) do
      {_, 0} ->
        Logger.info("Created branch: #{branch_name}")

      {output, _} ->
        if String.contains?(output, "already exists") do
          Logger.info("Branch already exists, switching to it")
          System.cmd("git", ["switch", branch_name])
        else
          Mix.raise("Failed to create branch: #{output}")
        end
    end
  end

  defp generate_prompt(item, prd, plan_content) do
    stories_text =
      prd["userStories"]
      |> Enum.map(fn story ->
        criteria =
          (story["acceptanceCriteria"] || [])
          |> Enum.map(&"  - [ ] #{&1}")
          |> Enum.join("\n")

        """
        ### #{story["id"]}: #{story["title"]}

        **Acceptance Criteria:**
        #{criteria}
        """
      end)
      |> Enum.join("\n")

    """
    # #{item["title"]}

    ## Overview

    #{item["overview"] || "Implement this roadmap item."}

    ## Plan

    #{plan_content}

    ## User Stories

    #{stories_text}

    ## Instructions

    Work through each user story in order. For each story:
    1. Implement the required changes
    2. Ensure all acceptance criteria are met
    3. Run tests and typecheck
    4. Commit your changes

    When ALL stories are complete and all acceptance criteria pass, output:
    `<promise>COMPLETE</promise>`
    """
  end
end
