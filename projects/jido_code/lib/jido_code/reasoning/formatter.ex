defmodule JidoCode.Reasoning.Formatter do
  @moduledoc """
  Formats Chain-of-Thought reasoning steps for TUI presentation.

  This module converts reasoning plans into human-readable display strings
  with visual status indicators and collapsible summaries.

  ## Usage

      # Format a reasoning plan for display
      formatted = JidoCode.Reasoning.Formatter.format_plan(reasoning_plan)
      IO.puts(formatted)

      # Format individual steps with status
      step = %JidoCode.Reasoning.Formatter.Step{
        number: 1,
        description: "Analyze requirements",
        outcome: "Success",
        status: :complete
      }
      IO.puts(Formatter.format_step(step))
      # => "● 1. Analyze requirements (Success)"

  ## Step Status Indicators

  - `○` - Pending (not started)
  - `◐` - In Progress (currently executing)
  - `●` - Complete (finished successfully)
  - `✗` - Failed (encountered error)

  ## Collapsible Summaries

  For reasoning chains with many steps, use `format_summary/2` to create
  a condensed view that can be expanded.
  """

  # ============================================================================
  # Types
  # ============================================================================

  defmodule Step do
    @moduledoc """
    Represents a single reasoning step with status tracking.
    """

    @type status :: :pending | :in_progress | :complete | :failed

    @type t :: %__MODULE__{
            number: pos_integer(),
            description: String.t(),
            outcome: String.t() | nil,
            status: status()
          }

    defstruct [:number, :description, :outcome, status: :pending]

    @doc """
    Creates a new Step struct from a reasoning step map.

    ## Parameters

    - `step_map` - A map with :number, :description, and optional :expected_outcome

    ## Example

        step = Step.from_map(%{number: 1, description: "Analyze", expected_outcome: "Done"})
    """
    @spec from_map(map()) :: t()
    def from_map(%{number: number, description: description} = step_map) do
      %__MODULE__{
        number: number,
        description: description,
        outcome: step_map[:expected_outcome] || step_map[:outcome],
        status: step_map[:status] || :pending
      }
    end

    def from_map(_), do: nil
  end

  @typedoc """
  Validation result with confidence score.
  """
  @type validation_result :: %{
          valid: boolean(),
          confidence: float(),
          issues: [String.t()]
        }

  @typedoc """
  Options for formatting.
  """
  @type format_opts :: [
          show_outcomes: boolean(),
          indent: non_neg_integer(),
          max_description_length: non_neg_integer()
        ]

  # Status indicators for display
  @status_indicators %{
    pending: "○",
    in_progress: "◐",
    complete: "●",
    failed: "✗"
  }

  # Default options
  @default_opts [
    show_outcomes: true,
    indent: 0,
    max_description_length: 80
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Formats a complete reasoning plan for TUI display.

  ## Parameters

  - `reasoning_plan` - The reasoning plan map from ChainOfThought
  - `opts` - Optional formatting options

  ## Options

  - `:show_outcomes` - Include expected outcomes (default: true)
  - `:indent` - Number of spaces to indent (default: 0)
  - `:max_description_length` - Truncate descriptions longer than this (default: 80)

  ## Returns

  A formatted string ready for terminal display.

  ## Example

      formatted = Formatter.format_plan(reasoning_plan)
      IO.puts(formatted)
      # ══════════════════════════════════════════════════════════
      # Goal: Implement rate limiting for API endpoints
      # ══════════════════════════════════════════════════════════
      #
      # Steps:
      # ○ 1. Analyze current request handling
      # ○ 2. Design rate limiting algorithm
      # ○ 3. Implement token bucket or sliding window
      # ○ 4. Add configuration options
      # ○ 5. Write tests
      #
      # Expected: Working rate limiter with configurable limits
      # ──────────────────────────────────────────────────────────
  """
  @spec format_plan(map() | nil, format_opts()) :: String.t()
  def format_plan(plan, opts \\ [])
  def format_plan(nil, _opts), do: "No reasoning plan available."

  def format_plan(%{goal: goal, steps: steps} = plan, opts) do
    opts = Keyword.merge(@default_opts, opts)
    indent = String.duplicate(" ", opts[:indent])

    sections = [
      format_header(goal, indent),
      format_steps_section(steps, opts),
      format_expected_results(plan[:expected_results], indent),
      format_potential_issues(plan[:potential_issues], indent),
      format_footer(indent)
    ]

    sections
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def format_plan(_, _opts), do: "Invalid reasoning plan."

  @doc """
  Formats a single reasoning step with status indicator.

  ## Parameters

  - `step` - A Step struct or step map
  - `opts` - Optional formatting options

  ## Returns

  A formatted string for the step.

  ## Example

      step = %Step{number: 1, description: "Analyze", status: :complete, outcome: "Done"}
      Formatter.format_step(step)
      # => "● 1. Analyze (Done)"
  """
  @spec format_step(Step.t() | map(), format_opts()) :: String.t()
  def format_step(step, opts \\ [])

  def format_step(%Step{} = step, opts) do
    opts = Keyword.merge(@default_opts, opts)
    indicator = @status_indicators[step.status] || "○"
    indent = String.duplicate(" ", opts[:indent])

    description = truncate(step.description, opts[:max_description_length])

    outcome_str =
      if opts[:show_outcomes] && step.outcome && step.outcome != "" do
        " (#{truncate(step.outcome, 40)})"
      else
        ""
      end

    "#{indent}#{indicator} #{step.number}. #{description}#{outcome_str}"
  end

  def format_step(step_map, opts) when is_map(step_map) do
    case Step.from_map(step_map) do
      nil -> ""
      step -> format_step(step, opts)
    end
  end

  @doc """
  Formats validation results with confidence score.

  ## Parameters

  - `validation` - A validation result map with :valid, :confidence, and :issues

  ## Returns

  A formatted string showing validation status.

  ## Example

      validation = %{valid: true, confidence: 0.92, issues: []}
      Formatter.format_validation(validation)
      # => "✓ Validation passed (92% confidence)"

      validation = %{valid: false, confidence: 0.65, issues: ["Missing edge case"]}
      Formatter.format_validation(validation)
      # => "✗ Validation failed (65% confidence)
      #      - Missing edge case"
  """
  @spec format_validation(validation_result() | nil) :: String.t()
  def format_validation(nil), do: ""

  def format_validation(%{valid: valid, confidence: confidence} = validation) do
    confidence_pct = round(confidence * 100)
    issues = validation[:issues] || []

    status =
      if valid do
        "✓ Validation passed"
      else
        "✗ Validation failed"
      end

    base = "#{status} (#{confidence_pct}% confidence)"

    if valid or Enum.empty?(issues) do
      base
    else
      issue_lines = Enum.map_join(issues, "\n", &"  - #{&1}")

      "#{base}\n#{issue_lines}"
    end
  end

  def format_validation(_), do: ""

  @doc """
  Creates a collapsible summary for long reasoning chains.

  For chains with many steps, this creates a condensed view showing:
  - Goal (truncated)
  - Total step count with status breakdown
  - Expand indicator

  ## Parameters

  - `reasoning_plan` - The reasoning plan map
  - `opts` - Options for summary format

  ## Options

  - `:expanded` - If true, shows all steps; if false, shows summary only (default: false)
  - `:collapse_threshold` - Number of steps above which to collapse (default: 5)

  ## Returns

  A formatted string with optional expansion.

  ## Example

      summary = Formatter.format_summary(plan, expanded: false)
      # => "▶ Implement rate limiting (5 steps: 0/5 complete)"

      summary = Formatter.format_summary(plan, expanded: true)
      # => "▼ Implement rate limiting
      #    ○ 1. Analyze requirements
      #    ○ 2. Design algorithm
      #    ..."
  """
  @spec format_summary(map() | nil, keyword()) :: String.t()
  def format_summary(plan, opts \\ [])
  def format_summary(nil, _opts), do: "No reasoning plan available."

  def format_summary(%{goal: goal, steps: steps} = plan, opts) when is_list(steps) do
    expanded = Keyword.get(opts, :expanded, false)
    collapse_threshold = Keyword.get(opts, :collapse_threshold, 5)

    step_count = length(steps)
    should_collapse = step_count > collapse_threshold and not expanded

    if should_collapse do
      format_collapsed_summary(goal, steps)
    else
      format_plan(plan, opts)
    end
  end

  def format_summary(_, _opts), do: "Invalid reasoning plan."

  @doc """
  Returns the status indicator for a given status atom.

  ## Example

      Formatter.status_indicator(:complete)
      # => "●"
  """
  @spec status_indicator(Step.status()) :: String.t()
  def status_indicator(status), do: @status_indicators[status] || "○"

  @doc """
  Converts a list of step maps to Step structs.

  ## Parameters

  - `steps` - List of step maps from reasoning plan

  ## Returns

  List of Step structs.
  """
  @spec steps_from_maps([map()]) :: [Step.t()]
  def steps_from_maps(steps) when is_list(steps) do
    steps
    |> Enum.map(&Step.from_map/1)
    |> Enum.reject(&is_nil/1)
  end

  def steps_from_maps(_), do: []

  @doc """
  Updates the status of a step in a list.

  ## Parameters

  - `steps` - List of Step structs
  - `step_number` - The step number to update
  - `new_status` - The new status atom

  ## Returns

  Updated list of Step structs.
  """
  @spec update_step_status([Step.t()], pos_integer(), Step.status()) :: [Step.t()]
  def update_step_status(steps, step_number, new_status) when is_list(steps) do
    Enum.map(steps, fn step ->
      if step.number == step_number do
        %{step | status: new_status}
      else
        step
      end
    end)
  end

  @doc """
  Calculates step status counts from a list of steps.

  ## Returns

  A map with counts for each status.

  ## Example

      Formatter.step_status_counts(steps)
      # => %{pending: 3, in_progress: 1, complete: 2, failed: 0}
  """
  @spec step_status_counts([Step.t()]) :: %{Step.status() => non_neg_integer()}
  def step_status_counts(steps) when is_list(steps) do
    base = %{pending: 0, in_progress: 0, complete: 0, failed: 0}

    Enum.reduce(steps, base, fn step, acc ->
      status = step.status || :pending
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  def step_status_counts(_), do: %{pending: 0, in_progress: 0, complete: 0, failed: 0}

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp format_header(goal, indent) do
    goal_text = truncate(goal || "Unknown goal", 60)
    separator = String.duplicate("═", 60)

    """
    #{indent}#{separator}
    #{indent}Goal: #{goal_text}
    #{indent}#{separator}
    """
  end

  defp format_steps_section(nil, _opts), do: nil
  defp format_steps_section([], _opts), do: nil

  defp format_steps_section(steps, opts) when is_list(steps) do
    indent = String.duplicate(" ", opts[:indent])

    step_lines =
      steps
      |> Enum.map(fn step_map ->
        step = Step.from_map(step_map)
        if step, do: format_step(step, opts), else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    """
    #{indent}Steps:
    #{step_lines}
    """
  end

  defp format_expected_results(nil, _indent), do: nil
  defp format_expected_results("", _indent), do: nil

  defp format_expected_results(expected, indent) do
    "#{indent}Expected: #{truncate(expected, 60)}"
  end

  defp format_potential_issues(nil, _indent), do: nil
  defp format_potential_issues([], _indent), do: nil

  defp format_potential_issues(issues, indent) when is_list(issues) do
    issue_lines = Enum.map_join(issues, "\n", &"#{indent}  ⚠ #{truncate(&1, 55)}")

    """
    #{indent}Potential Issues:
    #{issue_lines}
    """
  end

  defp format_footer(indent) do
    separator = String.duplicate("─", 60)
    "#{indent}#{separator}"
  end

  defp format_collapsed_summary(goal, steps) do
    goal_text = truncate(goal || "Unknown goal", 40)
    step_structs = steps_from_maps(steps)
    counts = step_status_counts(step_structs)
    total = length(steps)
    complete = counts.complete

    "▶ #{goal_text} (#{total} steps: #{complete}/#{total} complete)"
  end

  defp truncate(nil, _max), do: ""

  defp truncate(text, max) when is_binary(text) do
    text = String.trim(text)

    if String.length(text) > max do
      String.slice(text, 0, max - 3) <> "..."
    else
      text
    end
  end
end
