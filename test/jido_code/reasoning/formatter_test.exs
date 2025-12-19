defmodule JidoCode.Reasoning.FormatterTest do
  use ExUnit.Case, async: true

  alias JidoCode.Reasoning.Formatter
  alias JidoCode.Reasoning.Formatter.Step

  @moduletag :reasoning

  # ============================================================================
  # Test Data
  # ============================================================================

  @sample_reasoning_plan %{
    goal: "Implement rate limiting for API endpoints",
    analysis: "Need to track request counts and enforce limits",
    steps: [
      %{
        number: 1,
        description: "Analyze current request handling",
        expected_outcome: "Understand flow"
      },
      %{
        number: 2,
        description: "Design rate limiting algorithm",
        expected_outcome: "Algorithm chosen"
      },
      %{
        number: 3,
        description: "Implement token bucket",
        expected_outcome: "Working implementation"
      },
      %{
        number: 4,
        description: "Add configuration options",
        expected_outcome: "Configurable limits"
      },
      %{number: 5, description: "Write tests", expected_outcome: "Full coverage"}
    ],
    expected_results: "Working rate limiter with configurable limits",
    potential_issues: ["High concurrency edge cases", "Memory usage for large deployments"]
  }

  @simple_plan %{
    goal: "Fix typo in documentation",
    analysis: "Simple text fix",
    steps: [
      %{number: 1, description: "Find the typo", expected_outcome: nil},
      %{number: 2, description: "Fix it", expected_outcome: nil}
    ],
    expected_results: "Corrected documentation",
    potential_issues: []
  }

  # ============================================================================
  # Step Struct Tests
  # ============================================================================

  describe "Step struct" do
    test "from_map/1 creates Step from map" do
      step_map = %{number: 1, description: "Test step", expected_outcome: "Done"}
      step = Step.from_map(step_map)

      assert %Step{} = step
      assert step.number == 1
      assert step.description == "Test step"
      assert step.outcome == "Done"
      assert step.status == :pending
    end

    test "from_map/1 handles missing outcome" do
      step_map = %{number: 1, description: "Test step"}
      step = Step.from_map(step_map)

      assert step.outcome == nil
    end

    test "from_map/1 preserves status if provided" do
      step_map = %{number: 1, description: "Test", status: :complete}
      step = Step.from_map(step_map)

      assert step.status == :complete
    end

    test "from_map/1 returns nil for invalid input" do
      assert Step.from_map(%{}) == nil
      assert Step.from_map(%{number: 1}) == nil
      assert Step.from_map(nil) == nil
    end
  end

  # ============================================================================
  # format_plan/2 Tests
  # ============================================================================

  describe "format_plan/2" do
    test "formats complete reasoning plan" do
      result = Formatter.format_plan(@sample_reasoning_plan)

      assert is_binary(result)
      assert String.contains?(result, "Implement rate limiting")
      assert String.contains?(result, "Steps:")
      assert String.contains?(result, "1. Analyze current request handling")
      assert String.contains?(result, "2. Design rate limiting algorithm")
      assert String.contains?(result, "Expected:")
      assert String.contains?(result, "Potential Issues:")
    end

    test "includes status indicators" do
      result = Formatter.format_plan(@sample_reasoning_plan)

      # Default status is pending (○)
      assert String.contains?(result, "○")
    end

    test "handles nil plan" do
      assert Formatter.format_plan(nil) == "No reasoning plan available."
    end

    test "handles invalid plan" do
      assert Formatter.format_plan("not a plan") == "Invalid reasoning plan."
      assert Formatter.format_plan(%{}) == "Invalid reasoning plan."
    end

    test "respects indent option" do
      result = Formatter.format_plan(@simple_plan, indent: 2)

      # Check that lines are indented
      lines = String.split(result, "\n")
      assert Enum.any?(lines, fn line -> String.starts_with?(line, "  ") end)
    end

    test "truncates long descriptions" do
      long_desc =
        "This is a very long description that should be truncated because it exceeds the maximum length allowed for display purposes"

      plan = %{
        goal: "Test",
        steps: [%{number: 1, description: long_desc}],
        expected_results: nil,
        potential_issues: nil
      }

      result = Formatter.format_plan(plan, max_description_length: 50)
      assert String.contains?(result, "...")
    end

    test "shows outcomes when show_outcomes: true" do
      result = Formatter.format_plan(@sample_reasoning_plan, show_outcomes: true)
      assert String.contains?(result, "(Understand flow)")
    end

    test "hides outcomes when show_outcomes: false" do
      result = Formatter.format_plan(@sample_reasoning_plan, show_outcomes: false)
      refute String.contains?(result, "(Understand flow)")
    end

    test "handles empty steps list" do
      plan = %{goal: "Test", steps: [], expected_results: nil, potential_issues: nil}
      result = Formatter.format_plan(plan)

      assert String.contains?(result, "Test")
      refute String.contains?(result, "Steps:")
    end

    test "handles nil potential_issues" do
      plan = %{
        goal: "Test",
        steps: [%{number: 1, description: "Step"}],
        expected_results: nil,
        potential_issues: nil
      }

      result = Formatter.format_plan(plan)
      refute String.contains?(result, "Potential Issues:")
    end
  end

  # ============================================================================
  # format_step/2 Tests
  # ============================================================================

  describe "format_step/2" do
    test "formats step with pending status" do
      step = %Step{number: 1, description: "Test step", status: :pending}
      result = Formatter.format_step(step)

      assert result == "○ 1. Test step"
    end

    test "formats step with in_progress status" do
      step = %Step{number: 2, description: "Working", status: :in_progress}
      result = Formatter.format_step(step)

      assert result == "◐ 2. Working"
    end

    test "formats step with complete status" do
      step = %Step{number: 3, description: "Done", status: :complete}
      result = Formatter.format_step(step)

      assert result == "● 3. Done"
    end

    test "formats step with failed status" do
      step = %Step{number: 4, description: "Failed step", status: :failed}
      result = Formatter.format_step(step)

      assert result == "✗ 4. Failed step"
    end

    test "includes outcome when present" do
      step = %Step{number: 1, description: "Test", outcome: "Success", status: :complete}
      result = Formatter.format_step(step)

      assert result == "● 1. Test (Success)"
    end

    test "hides outcome when show_outcomes: false" do
      step = %Step{number: 1, description: "Test", outcome: "Success", status: :complete}
      result = Formatter.format_step(step, show_outcomes: false)

      assert result == "● 1. Test"
    end

    test "formats step from map" do
      step_map = %{number: 1, description: "Test step", status: :complete}
      result = Formatter.format_step(step_map)

      assert result == "● 1. Test step"
    end

    test "handles indent option" do
      step = %Step{number: 1, description: "Test", status: :pending}
      result = Formatter.format_step(step, indent: 4)

      assert String.starts_with?(result, "    ○")
    end

    test "truncates long outcome" do
      long_outcome = String.duplicate("x", 100)
      step = %Step{number: 1, description: "Test", outcome: long_outcome, status: :pending}
      result = Formatter.format_step(step)

      assert String.contains?(result, "...")
      assert String.length(result) < 150
    end
  end

  # ============================================================================
  # format_validation/1 Tests
  # ============================================================================

  describe "format_validation/1" do
    test "formats passing validation" do
      validation = %{valid: true, confidence: 0.92, issues: []}
      result = Formatter.format_validation(validation)

      assert result == "✓ Validation passed (92% confidence)"
    end

    test "formats failing validation with issues" do
      validation = %{
        valid: false,
        confidence: 0.65,
        issues: ["Missing edge case", "Incomplete implementation"]
      }

      result = Formatter.format_validation(validation)

      assert String.contains?(result, "✗ Validation failed (65% confidence)")
      assert String.contains?(result, "Missing edge case")
      assert String.contains?(result, "Incomplete implementation")
    end

    test "formats failing validation without issues" do
      validation = %{valid: false, confidence: 0.40, issues: []}
      result = Formatter.format_validation(validation)

      assert result == "✗ Validation failed (40% confidence)"
    end

    test "handles nil validation" do
      assert Formatter.format_validation(nil) == ""
    end

    test "handles invalid validation" do
      assert Formatter.format_validation(%{}) == ""
      assert Formatter.format_validation("invalid") == ""
    end

    test "rounds confidence percentage" do
      validation = %{valid: true, confidence: 0.876, issues: []}
      result = Formatter.format_validation(validation)

      assert String.contains?(result, "88% confidence")
    end
  end

  # ============================================================================
  # format_summary/2 Tests
  # ============================================================================

  describe "format_summary/2" do
    test "collapses long plans by default" do
      plan = %{
        goal: "Complex task",
        steps: Enum.map(1..10, fn i -> %{number: i, description: "Step #{i}"} end),
        expected_results: nil,
        potential_issues: nil
      }

      result = Formatter.format_summary(plan, expanded: false)

      # Should show collapsed summary
      assert String.starts_with?(result, "▶")
      assert String.contains?(result, "10 steps")
      refute String.contains?(result, "═")
    end

    test "expands when expanded: true" do
      plan = %{
        goal: "Complex task",
        steps: Enum.map(1..10, fn i -> %{number: i, description: "Step #{i}"} end),
        expected_results: nil,
        potential_issues: nil
      }

      result = Formatter.format_summary(plan, expanded: true)

      # Should show full plan
      assert String.contains?(result, "═")
      assert String.contains?(result, "Step 1")
      assert String.contains?(result, "Step 10")
    end

    test "shows full plan when under threshold" do
      result = Formatter.format_summary(@simple_plan, expanded: false)

      # 2 steps is under default threshold of 5
      assert String.contains?(result, "═")
    end

    test "respects custom collapse_threshold" do
      plan = %{
        goal: "Test",
        steps: Enum.map(1..3, fn i -> %{number: i, description: "Step #{i}"} end),
        expected_results: nil,
        potential_issues: nil
      }

      # Threshold of 2 should collapse 3 steps
      result = Formatter.format_summary(plan, collapse_threshold: 2)
      assert String.starts_with?(result, "▶")

      # Threshold of 5 should not collapse
      result = Formatter.format_summary(plan, collapse_threshold: 5)
      assert String.contains?(result, "═")
    end

    test "shows step completion counts in collapsed view" do
      steps =
        Enum.map(1..6, fn i ->
          %{
            number: i,
            description: "Step #{i}",
            status: if(i <= 2, do: :complete, else: :pending)
          }
        end)

      plan = %{goal: "Test", steps: steps, expected_results: nil, potential_issues: nil}
      result = Formatter.format_summary(plan, expanded: false)

      assert String.contains?(result, "2/6 complete")
    end

    test "handles nil plan" do
      assert Formatter.format_summary(nil) == "No reasoning plan available."
    end

    test "handles invalid plan" do
      assert Formatter.format_summary(%{}) == "Invalid reasoning plan."
    end
  end

  # ============================================================================
  # Helper Function Tests
  # ============================================================================

  describe "status_indicator/1" do
    test "returns correct indicators" do
      assert Formatter.status_indicator(:pending) == "○"
      assert Formatter.status_indicator(:in_progress) == "◐"
      assert Formatter.status_indicator(:complete) == "●"
      assert Formatter.status_indicator(:failed) == "✗"
    end

    test "defaults to pending for unknown status" do
      assert Formatter.status_indicator(:unknown) == "○"
    end
  end

  describe "steps_from_maps/1" do
    test "converts list of maps to Step structs" do
      maps = [
        %{number: 1, description: "First"},
        %{number: 2, description: "Second"}
      ]

      steps = Formatter.steps_from_maps(maps)

      assert length(steps) == 2
      assert Enum.all?(steps, &match?(%Step{}, &1))
      assert hd(steps).number == 1
    end

    test "filters out invalid maps" do
      maps = [
        %{number: 1, description: "Valid"},
        %{invalid: true},
        %{number: 2, description: "Also valid"}
      ]

      steps = Formatter.steps_from_maps(maps)
      assert length(steps) == 2
    end

    test "handles empty list" do
      assert Formatter.steps_from_maps([]) == []
    end

    test "handles non-list input" do
      assert Formatter.steps_from_maps(nil) == []
      assert Formatter.steps_from_maps("invalid") == []
    end
  end

  describe "update_step_status/3" do
    test "updates status of specific step" do
      steps = [
        %Step{number: 1, description: "First", status: :pending},
        %Step{number: 2, description: "Second", status: :pending}
      ]

      updated = Formatter.update_step_status(steps, 1, :complete)

      assert hd(updated).status == :complete
      assert List.last(updated).status == :pending
    end

    test "leaves other steps unchanged" do
      steps = [
        %Step{number: 1, description: "First", status: :complete},
        %Step{number: 2, description: "Second", status: :in_progress},
        %Step{number: 3, description: "Third", status: :pending}
      ]

      updated = Formatter.update_step_status(steps, 2, :failed)

      assert Enum.at(updated, 0).status == :complete
      assert Enum.at(updated, 1).status == :failed
      assert Enum.at(updated, 2).status == :pending
    end

    test "handles non-existent step number" do
      steps = [%Step{number: 1, description: "First", status: :pending}]
      updated = Formatter.update_step_status(steps, 99, :complete)

      assert hd(updated).status == :pending
    end
  end

  describe "step_status_counts/1" do
    test "counts steps by status" do
      steps = [
        %Step{number: 1, status: :complete},
        %Step{number: 2, status: :complete},
        %Step{number: 3, status: :in_progress},
        %Step{number: 4, status: :pending},
        %Step{number: 5, status: :pending},
        %Step{number: 6, status: :failed}
      ]

      counts = Formatter.step_status_counts(steps)

      assert counts.complete == 2
      assert counts.in_progress == 1
      assert counts.pending == 2
      assert counts.failed == 1
    end

    test "handles empty list" do
      counts = Formatter.step_status_counts([])

      assert counts.complete == 0
      assert counts.in_progress == 0
      assert counts.pending == 0
      assert counts.failed == 0
    end

    test "handles non-list input" do
      counts = Formatter.step_status_counts(nil)
      assert counts == %{pending: 0, in_progress: 0, complete: 0, failed: 0}
    end
  end

  # ============================================================================
  # Output Readability Tests
  # ============================================================================

  describe "output readability" do
    test "formatted plan is human-readable" do
      result = Formatter.format_plan(@sample_reasoning_plan)

      # Should have clear structure
      lines = String.split(result, "\n")
      assert length(lines) > 5

      # Should have headers/separators
      assert Enum.any?(lines, fn line -> String.contains?(line, "═") end)
      assert Enum.any?(lines, fn line -> String.contains?(line, "─") end)

      # Should have numbered steps
      assert Enum.any?(lines, fn line -> Regex.match?(~r/\d+\.\s+/, line) end)
    end

    test "step indicators are visually distinct" do
      indicators = [:pending, :in_progress, :complete, :failed]
      symbols = Enum.map(indicators, &Formatter.status_indicator/1)

      # All indicators should be unique
      assert length(Enum.uniq(symbols)) == 4

      # All indicators should be single characters
      assert Enum.all?(symbols, fn s -> String.length(s) == 1 end)
    end

    test "collapsed summary fits on one line" do
      plan = %{
        goal: "A reasonably long goal description for testing",
        steps: Enum.map(1..10, fn i -> %{number: i, description: "Step #{i}"} end),
        expected_results: nil,
        potential_issues: nil
      }

      result = Formatter.format_summary(plan, expanded: false)
      lines = String.split(result, "\n")

      assert length(lines) == 1
      assert String.length(result) < 80
    end
  end
end
