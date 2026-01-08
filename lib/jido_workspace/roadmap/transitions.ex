defmodule JidoWorkspace.Roadmap.Transitions do
  @moduledoc """
  State machine for roadmap task transitions.

  All state changes MUST go through this module. It enforces:
  1. Valid state transitions (no skipping steps)
  2. Required artifacts exist before transition
  3. Dependencies are satisfied
  4. Required fields are set (assignee, branch, pr_url)

  ## Usage

      # Transition a task to a new state
      {:ok, updated_task} = Transitions.transition(task, :planned)

      # Check if a transition is allowed (without side effects)
      :ok = Transitions.can_transition?(task, :implementing)
  """

  alias JidoWorkspace.Roadmap.Schema
  alias JidoWorkspace.Roadmap.Store

  # =============================================================================
  # ALLOWED TRANSITIONS
  # =============================================================================

  # All states are strings to match JSON storage
  @allowed_transitions %{
    "raw" => ["researched", "planned"],
    "researched" => ["planned"],
    "planned" => ["checked_out"],
    "checked_out" => ["implementing", "planned"],
    "implementing" => ["in_pr", "planned"],
    "in_pr" => ["implementing", "done"],
    "done" => []
  }

  def allowed_transitions, do: @allowed_transitions

  @doc """
  Get allowed next states for a given state.
  """
  def allowed_next_states(state) when is_binary(state) do
    Map.get(@allowed_transitions, state, [])
  end

  # =============================================================================
  # TRANSITION ERRORS
  # =============================================================================

  @type transition_error ::
          {:invalid_state, String.t()}
          | {:invalid_transition, from :: String.t(), to :: String.t()}
          | {:missing_artifact, path :: String.t()}
          | {:missing_artifacts, [String.t()]}
          | {:blocked_by, [String.t()]}
          | {:requires_assignee}
          | {:requires_branch}
          | {:requires_pr_url}
          | {:already_assigned, String.t()}

  # =============================================================================
  # MAIN TRANSITION FUNCTION
  # =============================================================================

  @doc """
  Transition a task to a new state.

  Validates all requirements and returns the updated task or an error.

  ## Options

  - `:assignee` - Set assignee (required for checked_out)
  - `:branch` - Set branch name (required for checked_out)
  - `:pr_url` - Set PR URL (required for in_pr)
  - `:force` - Skip soft lock check (use with caution)
  - `:check_dependencies` - Validate dependency states (default: true)

  ## Examples

      # Move to researched
      Transitions.transition(task, :researched)

      # Checkout with assignment
      Transitions.transition(task, :checked_out, assignee: "alice", branch: "feat/thing")

      # Complete PR
      Transitions.transition(task, :in_pr, pr_url: "https://github.com/...")
  """
  def transition(task, to_state, opts \\ []) do
    from_state = task.state
    kind = Map.get(task, :kind, "implementation")

    with :ok <- validate_transition_allowed(from_state, to_state),
         :ok <- validate_artifacts(task.id, kind, to_state),
         :ok <- validate_assignment(task, to_state, opts),
         :ok <- validate_branch(task, to_state, opts),
         :ok <- validate_pr_url(task, to_state, opts),
         :ok <- validate_dependencies(task, to_state, opts) do
      updated_task =
        task
        |> Map.put(:state, to_state)
        |> maybe_set(:assignee, opts[:assignee])
        |> maybe_set(:branch, opts[:branch])
        |> maybe_set(:pr_url, opts[:pr_url])

      {:ok, updated_task}
    end
  end

  @doc """
  Check if a transition is allowed without performing it.

  Returns :ok or {:error, reason}.
  """
  def can_transition?(task, to_state, opts \\ []) do
    case transition(task, to_state, Keyword.put(opts, :dry_run, true)) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # =============================================================================
  # VALIDATION HELPERS
  # =============================================================================

  defp validate_transition_allowed(from, to) do
    allowed = Map.get(@allowed_transitions, from, [])

    if to in allowed do
      :ok
    else
      {:error, {:invalid_transition, from, to}}
    end
  end

  defp validate_artifacts(task_id, kind, to_state) do
    required = Schema.required_artifacts(kind, to_state)

    missing =
      Enum.reject(required, fn artifact ->
        Store.artifact_exists?(task_id, artifact)
      end)

    case missing do
      [] -> :ok
      [single] -> {:error, {:missing_artifact, single}}
      multiple -> {:error, {:missing_artifacts, multiple}}
    end
  end

  defp validate_assignment(task, to_state, opts) do
    case to_state do
      state when state in ["checked_out", "implementing", "in_pr"] ->
        current_assignee = Map.get(task, :assignee)
        new_assignee = opts[:assignee]
        force = opts[:force] || false

        cond do
          # Already has assignee and not forcing
          current_assignee && !new_assignee && !force ->
            :ok

          # Trying to reassign without force
          current_assignee && new_assignee && current_assignee != new_assignee && !force ->
            {:error, {:already_assigned, current_assignee}}

          # Moving to checked_out requires assignee
          to_state == "checked_out" && !current_assignee && !new_assignee ->
            {:error, :requires_assignee}

          true ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp validate_branch(task, to_state, opts) do
    case to_state do
      "checked_out" ->
        current = Map.get(task, :branch)
        new = opts[:branch]

        if current || new do
          :ok
        else
          {:error, :requires_branch}
        end

      _ ->
        :ok
    end
  end

  defp validate_pr_url(task, to_state, opts) do
    case to_state do
      "in_pr" ->
        current = Map.get(task, :pr_url)
        new = opts[:pr_url]

        if current || new do
          :ok
        else
          {:error, :requires_pr_url}
        end

      _ ->
        :ok
    end
  end

  defp validate_dependencies(task, to_state, opts) do
    check = Keyword.get(opts, :check_dependencies, true)

    if check && to_state == "done" do
      depends_on = Map.get(task, :depends_on, [])
      check_dependencies_done(depends_on)
    else
      :ok
    end
  end

  defp check_dependencies_done([]), do: :ok

  defp check_dependencies_done(dep_ids) do
    blocking =
      Enum.filter(dep_ids, fn id ->
        case Store.load_task(id) do
          {:ok, dep} -> dep.state != "done"
          {:error, _} -> true
        end
      end)

    case blocking do
      [] -> :ok
      blockers -> {:error, {:blocked_by, blockers}}
    end
  end

  defp maybe_set(task, _key, nil), do: task
  defp maybe_set(task, key, value), do: Map.put(task, key, value)

  # =============================================================================
  # CONVENIENCE FUNCTIONS
  # =============================================================================

  @doc """
  Checkout a task (planned → checked_out).

  Requires assignee and branch.
  """
  def checkout(task, assignee, branch) do
    transition(task, "checked_out", assignee: assignee, branch: branch)
  end

  @doc """
  Unclaim a task (checked_out → planned).

  Clears assignee and branch.
  """
  def unclaim(task) do
    case transition(task, "planned", force: true) do
      {:ok, updated} ->
        {:ok, Map.merge(updated, %{assignee: nil, branch: nil})}

      error ->
        error
    end
  end

  @doc """
  Submit a PR (implementing → in_pr).
  """
  def submit_pr(task, pr_url) do
    transition(task, "in_pr", pr_url: pr_url)
  end

  @doc """
  Mark a task as done (in_pr → done).

  Checks that all dependencies are also done.
  """
  def complete(task) do
    transition(task, "done")
  end

  # =============================================================================
  # STATE QUERIES
  # =============================================================================

  @doc """
  Check if a task is in a terminal state.
  """
  def terminal?(task) do
    task.state == "done"
  end

  @doc """
  Check if a task is currently claimed by someone.
  """
  def claimed?(task) do
    task.state in ["checked_out", "implementing", "in_pr"] &&
      Map.get(task, :assignee) != nil
  end

  @doc """
  Check if a task is blocked by unfinished dependencies.
  """
  def blocked?(task) do
    depends_on = Map.get(task, :depends_on, [])

    Enum.any?(depends_on, fn id ->
      case Store.load_task(id) do
        {:ok, dep} -> dep.state != "done"
        {:error, _} -> true
      end
    end)
  end
end
