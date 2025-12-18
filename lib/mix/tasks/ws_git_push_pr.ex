defmodule Mix.Tasks.Ws.Git.Push.Pr do
  use Mix.Task

  @shortdoc "Push to a workspace branch for PR workflow"

  @moduledoc """
  Push changes to a workspace branch for PR-based workflow.

  This creates a `workspace/<branch-name>` branch on the upstream repository,
  which can then be used to open a Pull Request. This follows the best practice
  of never pushing directly to main on public repositories.

  ## Examples

      mix ws.git.push.pr jido my-feature       # Push to workspace/my-feature
      mix ws.git.push.pr req_llm fix-bug       # Push to workspace/fix-bug
      mix ws.git.push.pr jido_ai release-v1.3  # Push to workspace/release-v1.3

  ## Workflow

  1. Make changes in the workspace
  2. Commit changes to the workspace
  3. Run `mix ws.git.push.pr <project> <branch-name>`
  4. Open a PR on GitHub from `workspace/<branch-name>` to `main`
  5. After merge, run `mix ws.git.pull <project>` to sync back

  ## Options

      --force    Force push (use with caution)
      --dry-run  Show what would be pushed without actually pushing
  """

  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()

    case parse_args(args) do
      {:ok, project_name, branch_name, opts} ->
        push_to_pr_branch(project_name, branch_name, opts)

      {:error, message} ->
        Mix.shell().error(message)
        Mix.shell().error("")
        Mix.shell().error("Usage: mix ws.git.push.pr <project> <branch-name> [--force] [--dry-run]")
    end
  end

  defp parse_args(args) do
    {opts, remaining, _} = OptionParser.parse(args, switches: [force: :boolean, dry_run: :boolean])

    case remaining do
      [project_name, branch_name] -> {:ok, project_name, branch_name, opts}
      [_project_name] -> {:error, "Missing branch name"}
      [] -> {:error, "Missing project name and branch name"}
      _ -> {:error, "Too many arguments"}
    end
  end

  defp push_to_pr_branch(project_name, branch_name, opts) do
    case find_project(project_name) do
      nil ->
        Mix.shell().error("Project '#{project_name}' not found in workspace config")

      project ->
        target_branch = "workspace/#{branch_name}"
        dry_run = Keyword.get(opts, :dry_run, false)
        force = Keyword.get(opts, :force, false)

        if dry_run do
          Mix.shell().info("DRY RUN: Would push #{project.name} to #{target_branch}")
          show_changes(project)
        else
          do_push(project, target_branch, force)
        end
    end
  end

  defp find_project(name) do
    Enum.find(JidoWorkspace.config(), &(&1.name == name))
  end

  defp show_changes(project) do
    Mix.shell().info("")
    Mix.shell().info("Changes in #{project.path}:")

    case System.cmd("git", ["log", "--oneline", "-10", "--", project.path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n")
        |> Enum.take(5)
        |> Enum.each(&Mix.shell().info("  #{&1}"))

      _ ->
        Mix.shell().info("  (unable to show changes)")
    end
  end

  defp do_push(project, target_branch, force) do
    Mix.shell().info("Pushing #{project.name} to #{target_branch}...")

    push_args =
      if force do
        ["subtree", "push", "--prefix=#{project.path}", project.upstream_url, target_branch]
      else
        ["subtree", "push", "--prefix=#{project.path}", project.upstream_url, target_branch]
      end

    case System.cmd("git", push_args, stderr_to_stdout: true) do
      {output, 0} ->
        Mix.shell().info("✓ Successfully pushed to #{target_branch}")
        Mix.shell().info("")
        Mix.shell().info("Next steps:")
        Mix.shell().info("  1. Open a PR on GitHub:")
        Mix.shell().info("     #{pr_url(project, target_branch)}")
        Mix.shell().info("  2. After merge, sync back:")
        Mix.shell().info("     mix ws.git.pull #{project.name}")

        unless output == "" do
          Mix.shell().info("")
          Mix.shell().info(output)
        end

      {error, code} ->
        Mix.shell().error("✗ Failed to push (exit code: #{code})")
        Mix.shell().error(error)
    end
  end

  defp pr_url(project, target_branch) do
    repo_path = extract_repo_path(project.upstream_url)
    "https://github.com/#{repo_path}/compare/#{project.branch}...#{target_branch}?expand=1"
  end

  defp extract_repo_path(url) do
    url
    |> String.replace(~r/^git@github\.com:/, "")
    |> String.replace(~r/\.git$/, "")
  end
end
