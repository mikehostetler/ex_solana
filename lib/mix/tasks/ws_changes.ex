defmodule Mix.Tasks.Ws.Changes do
  use Mix.Task

  @shortdoc "Show projects with unpushed changes"

  @moduledoc """
  Shows which projects have commits not yet pushed to their upstream repositories.

  This compares the local subtree state against the upstream main branch to identify
  commits that exist locally but haven't been pushed.

  ## Examples

      mix ws.changes              # Show all projects with unpushed commits
      mix ws.changes jido         # Show unpushed commits for specific project
      mix ws.changes --summary    # Show only counts, not commit details
  """

  def run(args) do
    Application.ensure_all_started(:jido_workspace)
    JidoWorkspace.ensure_workspace_env()

    {opts, project_filter} = parse_args(args)
    projects = get_projects(project_filter)

    results =
      projects
      |> Enum.filter(&File.exists?(&1.path))
      |> Enum.map(&check_project_changes/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      Mix.shell().info("✓ All projects are in sync with upstream")
    else
      display_results(results, opts)
    end
  end

  defp parse_args(args) do
    {opts, remaining, _} = OptionParser.parse(args, switches: [summary: :boolean])
    project_filter = List.first(remaining)
    {opts, project_filter}
  end

  defp get_projects(nil), do: JidoWorkspace.config()

  defp get_projects(name) do
    JidoWorkspace.config()
    |> Enum.filter(&(&1.name == name))
  end

  defp check_project_changes(project) do
    case get_unpushed_commits(project) do
      {:ok, []} -> nil
      {:ok, commits} -> %{project: project, commits: commits}
      {:error, _reason} -> nil
    end
  end

  defp get_unpushed_commits(project) do
    temp_branch = "temp-subtree-check-#{:erlang.unique_integer([:positive])}"

    try do
      with {:ok, _} <- fetch_upstream(project),
           {:ok, _} <- split_subtree(project, temp_branch),
           {:ok, commits} <- compare_branches(project, temp_branch) do
        {:ok, commits}
      end
    after
      cleanup_temp_branch(temp_branch)
    end
  end

  defp fetch_upstream(project) do
    remote_name = "upstream-#{project.name}"

    System.cmd("git", ["remote", "remove", remote_name], stderr_to_stdout: true)

    case System.cmd("git", ["remote", "add", remote_name, project.upstream_url],
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        case System.cmd("git", ["fetch", remote_name, project.branch, "--depth=100"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, remote_name}
          {error, _} -> {:error, error}
        end

      {error, _} ->
        {:error, error}
    end
  end

  defp split_subtree(project, temp_branch) do
    case System.cmd("git", ["subtree", "split", "--prefix=#{project.path}", "-b", temp_branch],
           stderr_to_stdout: true
         ) do
      {_, 0} -> {:ok, temp_branch}
      {error, _} -> {:error, error}
    end
  end

  defp compare_branches(project, temp_branch) do
    remote_name = "upstream-#{project.name}"
    remote_ref = "#{remote_name}/#{project.branch}"

    case System.cmd(
           "git",
           ["log", "--oneline", "--no-decorate", "#{remote_ref}..#{temp_branch}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        commits =
          output
          |> String.trim()
          |> String.split("\n")
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&parse_commit_line/1)

        {:ok, commits}

      {_, _} ->
        {:ok, []}
    end
  after
    remote_name = "upstream-#{project.name}"
    System.cmd("git", ["remote", "remove", remote_name], stderr_to_stdout: true)
  end

  defp parse_commit_line(line) do
    case String.split(line, " ", parts: 2) do
      [sha, message] -> %{sha: sha, message: message}
      [sha] -> %{sha: sha, message: ""}
    end
  end

  defp cleanup_temp_branch(branch) do
    System.cmd("git", ["branch", "-D", branch], stderr_to_stdout: true)
  end

  defp display_results(results, opts) do
    summary_only = Keyword.get(opts, :summary, false)

    total_commits = Enum.reduce(results, 0, fn r, acc -> acc + length(r.commits) end)

    Mix.shell().info("")
    Mix.shell().info("📦 #{length(results)} project(s) with #{total_commits} unpushed commit(s):")
    Mix.shell().info("")

    Enum.each(results, fn %{project: project, commits: commits} ->
      Mix.shell().info("#{project.name}: #{length(commits)} unpushed commit(s)")

      unless summary_only do
        Enum.each(commits, fn commit ->
          Mix.shell().info("  #{commit.sha} #{commit.message}")
        end)

        Mix.shell().info("")
      end
    end)

    unless summary_only do
      Mix.shell().info("To push changes:")

      Enum.each(results, fn %{project: project} ->
        Mix.shell().info("  mix ws.git.push #{project.name}")
      end)
    end
  end
end
