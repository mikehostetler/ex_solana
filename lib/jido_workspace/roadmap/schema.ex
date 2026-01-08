defmodule JidoWorkspace.Roadmap.Schema do
  @moduledoc """
  Zoi schemas for the roadmap domain model.

  All roadmap data flows through these schemas:
  - On load: JSON → validate → struct
  - On save: struct → validate → sorted JSON

  Never modify JSON files directly - use the Store module.
  """

  # =============================================================================
  # ENUMS
  # =============================================================================

  @states ~w(raw researched planned checked_out implementing in_pr done)
  @kinds ~w(implementation decision research spike maintenance chore)

  def states, do: @states
  def kinds, do: @kinds

  # Atom versions for internal use
  def state_atoms, do: Enum.map(@states, &String.to_atom/1)
  def kind_atoms, do: Enum.map(@kinds, &String.to_atom/1)

  # =============================================================================
  # TASK SCHEMA
  # =============================================================================

  @doc """
  Schema for a roadmap task (item.json).

  Required fields:
  - id: unique identifier (path-based, e.g., "jido-ecosystem/foundation-layer/...")
  - number: sequential number for ordering
  - title: human-readable title
  - state: current workflow state
  - section: hierarchy path as list of strings

  Optional fields:
  - kind: task type (defaults to :implementation)
  - overview: detailed description
  - assignee: who owns this task
  - branch: git branch name
  - pr_url: pull request URL
  - depends_on: list of task IDs this blocks on
  - roadmap_line: line number in ROADMAP.md (for sync)
  - created_at: ISO8601 timestamp
  - updated_at: ISO8601 timestamp
  """
  def task_schema do
    Zoi.object(%{
      # Required fields
      id:
        Zoi.string(description: "Unique task identifier (path-based)")
        |> Zoi.trim()
        |> Zoi.min(1),
      number:
        Zoi.integer(description: "Sequential task number")
        |> Zoi.min(1),
      title:
        Zoi.string(description: "Human-readable task title")
        |> Zoi.trim()
        |> Zoi.min(1)
        |> Zoi.max(200),
      state:
        Zoi.string(description: "Current workflow state")
        |> Zoi.one_of(@states),
      section:
        Zoi.list(Zoi.string() |> Zoi.trim() |> Zoi.min(1),
          description: "Hierarchy path"
        )
        |> Zoi.min(1),

      # Optional fields with defaults
      kind:
        Zoi.string(description: "Task type")
        |> Zoi.one_of(@kinds)
        |> Zoi.default("implementation")
        |> Zoi.optional(),
      overview:
        Zoi.string(description: "Detailed description")
        |> Zoi.trim()
        |> Zoi.default("")
        |> Zoi.optional(),
      assignee:
        Zoi.string(description: "Task owner")
        |> Zoi.trim()
        |> Zoi.default(nil)
        |> Zoi.optional(),
      branch:
        Zoi.string(description: "Git branch name")
        |> Zoi.trim()
        |> Zoi.default(nil)
        |> Zoi.optional(),
      pr_url:
        Zoi.string(description: "Pull request URL")
        |> Zoi.trim()
        |> Zoi.default(nil)
        |> Zoi.optional(),
      depends_on:
        Zoi.list(Zoi.string() |> Zoi.trim() |> Zoi.min(1),
          description: "Task IDs this depends on"
        )
        |> Zoi.default([])
        |> Zoi.optional(),
      roadmap_line:
        Zoi.integer(description: "Line number in ROADMAP.md")
        |> Zoi.min(1)
        |> Zoi.optional(),
      created_at:
        Zoi.string(description: "ISO8601 creation timestamp")
        |> Zoi.optional(),
      updated_at:
        Zoi.string(description: "ISO8601 update timestamp")
        |> Zoi.optional()
    })
  end

  # =============================================================================
  # PRD SCHEMA
  # =============================================================================

  @doc """
  Schema for a Product Requirements Document (prd.json).

  Generated during the planning phase for implementation tasks.
  """
  def prd_schema do
    Zoi.object(%{
      id:
        Zoi.string(description: "Task ID this PRD belongs to")
        |> Zoi.trim()
        |> Zoi.min(1),
      branch_name:
        Zoi.string(description: "Git branch for implementation")
        |> Zoi.trim()
        |> Zoi.min(1),
      base_branch:
        Zoi.string(description: "Base branch to merge into")
        |> Zoi.trim()
        |> Zoi.default("main")
        |> Zoi.optional(),
      user_stories:
        Zoi.list(user_story_schema(), description: "Implementation stories")
        |> Zoi.min(1)
    })
  end

  defp user_story_schema do
    Zoi.object(%{
      id:
        Zoi.string(description: "Story ID (e.g., US-001)")
        |> Zoi.trim()
        |> Zoi.min(1),
      title:
        Zoi.string(description: "Story title")
        |> Zoi.trim()
        |> Zoi.min(1)
        |> Zoi.max(200),
      acceptance_criteria:
        Zoi.list(Zoi.string() |> Zoi.trim() |> Zoi.min(1),
          description: "Acceptance criteria"
        )
        |> Zoi.min(1),
      priority:
        Zoi.integer(description: "Priority (1 = highest)")
        |> Zoi.min(1)
        |> Zoi.max(10)
        |> Zoi.default(5)
        |> Zoi.optional(),
      passes:
        Zoi.boolean(description: "Whether this story passes")
        |> Zoi.default(false)
        |> Zoi.optional(),
      notes:
        Zoi.string(description: "Implementation notes")
        |> Zoi.trim()
        |> Zoi.default("")
        |> Zoi.optional()
    })
  end

  # =============================================================================
  # INDEX SCHEMA
  # =============================================================================

  @doc """
  Schema for the roadmap index (index.json).

  This file is GENERATED, not manually edited.
  """
  def index_schema do
    Zoi.object(%{
      version:
        Zoi.string(description: "Schema version")
        |> Zoi.default("1.0.0")
        |> Zoi.optional(),
      created_at:
        Zoi.string(description: "ISO8601 creation timestamp")
        |> Zoi.optional(),
      items:
        Zoi.list(Zoi.string() |> Zoi.trim() |> Zoi.min(1),
          description: "List of task IDs"
        )
    })
  end

  # =============================================================================
  # VALIDATION HELPERS
  # =============================================================================

  @doc """
  Parse and validate a map against the task schema.

  Returns {:ok, validated_map} or {:error, errors}.
  """
  def validate_task(data) when is_map(data) do
    Zoi.parse(task_schema(), data)
  end

  @doc """
  Parse and validate a map against the PRD schema.
  """
  def validate_prd(data) when is_map(data) do
    Zoi.parse(prd_schema(), data)
  end

  @doc """
  Parse and validate a map against the index schema.
  """
  def validate_index(data) when is_map(data) do
    Zoi.parse(index_schema(), data)
  end

  # =============================================================================
  # ARTIFACT REQUIREMENTS
  # =============================================================================

  @doc """
  Returns the required artifacts for a given (kind, state) pair.

  Used to enforce that tasks have necessary files before transitioning.
  """
  def required_artifacts(kind, state) do
    artifacts_map()
    |> get_in([kind, state])
    |> Kernel.||([])
  end

  defp artifacts_map do
    %{
      "implementation" => %{
        "researched" => ["research.md"],
        "planned" => ["plan.md"],
        "checked_out" => ["plan.md", "prompt.md"],
        "implementing" => ["plan.md", "prompt.md"],
        "in_pr" => ["plan.md", "prd.json"],
        "done" => ["plan.md", "prd.json", "progress.txt"]
      },
      "decision" => %{
        "researched" => ["research.md"],
        "planned" => ["research.md", "plan.md"],
        "done" => ["research.md", "plan.md"]
      },
      "research" => %{
        "researched" => ["research.md"],
        "done" => ["research.md"]
      },
      "spike" => %{
        "researched" => ["research.md"],
        "done" => ["research.md", "progress.txt"]
      },
      "maintenance" => %{
        "planned" => ["plan.md"],
        "done" => ["plan.md"]
      },
      "chore" => %{
        # Chores have minimal requirements
        "done" => []
      }
    }
  end
end
