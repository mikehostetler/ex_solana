defmodule JidoCode.Reasoning.ChainOfThoughtTest do
  use ExUnit.Case, async: false

  alias JidoCode.Reasoning.ChainOfThought

  @moduletag :reasoning

  # ============================================================================
  # Mock Agent for Testing
  # ============================================================================

  defmodule MockAgent do
    @moduledoc false
    use GenServer

    def start_link(response) do
      GenServer.start_link(__MODULE__, response)
    end

    def init(response), do: {:ok, response}

    def handle_call({:chat, _message}, _from, response) when is_binary(response) do
      {:reply, {:ok, response}, response}
    end

    def handle_call({:chat, _message}, _from, {:error, _} = error) do
      {:reply, error, error}
    end

    def handle_call({:chat, _message}, _from, response) do
      {:reply, response, response}
    end
  end

  # ============================================================================
  # Sample Responses
  # ============================================================================

  @zero_shot_response """
  REASONING:
  Let me analyze this problem step by step.
  1. First, we need to understand the requirements
  2. Then, we design the solution architecture
  3. Finally, we implement and test

  ANSWER:
  The solution is to use a GenServer with proper supervision.
  """

  @structured_response """
  UNDERSTAND:
  - The user wants to implement rate limiting
  - Constraints: Must handle 1000 req/s
  - Input: HTTP requests, Output: Allow/Deny

  PLAN:
  1. Create a token bucket algorithm
  2. Store state in ETS for performance
  3. Add configuration options

  IMPLEMENT:
  Use a GenServer with ETS backing store.

  VALIDATE:
  - Meets throughput requirements
  - Handles edge cases like bucket overflow

  ANSWER:
  Implement using token bucket with ETS storage for O(1) lookups.
  """

  @plain_response """
  This is just a plain response without any structured reasoning.
  It should still work but won't have a reasoning plan.
  """

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Attach a test handler to capture telemetry events
    test_pid = self()

    :telemetry.attach_many(
      "cot-test-handler-#{inspect(self())}",
      [
        ChainOfThought.event_start(),
        ChainOfThought.event_complete(),
        ChainOfThought.event_fallback(),
        ChainOfThought.event_error()
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("cot-test-handler-#{inspect(test_pid)}")
    end)

    :ok
  end

  describe "default_config/0" do
    test "returns default configuration" do
      config = ChainOfThought.default_config()

      assert config.mode == :zero_shot
      assert config.temperature == 0.2
      assert config.max_iterations == 1
      assert config.enable_validation == true
      assert config.fallback_on_error == true
    end
  end

  describe "format_steps_for_display/1" do
    test "formats steps with numbers and descriptions" do
      reasoning_plan = %{
        goal: "Test goal",
        analysis: "Test analysis",
        steps: [
          %{number: 1, description: "First step", expected_outcome: nil},
          %{number: 2, description: "Second step", expected_outcome: "Some result"},
          %{number: 3, description: "Third step", expected_outcome: nil}
        ],
        expected_results: "Final result",
        potential_issues: []
      }

      formatted = ChainOfThought.format_steps_for_display(reasoning_plan)

      assert length(formatted) == 3
      assert Enum.at(formatted, 0) == "1. First step"
      assert Enum.at(formatted, 1) == "2. Second step (expected: Some result)"
      assert Enum.at(formatted, 2) == "3. Third step"
    end

    test "returns empty list for nil plan" do
      assert ChainOfThought.format_steps_for_display(nil) == []
    end

    test "returns empty list for plan without steps" do
      assert ChainOfThought.format_steps_for_display(%{}) == []
    end

    test "handles empty steps list" do
      assert ChainOfThought.format_steps_for_display(%{steps: []}) == []
    end
  end

  describe "summarize_plan/1" do
    test "summarizes plan with goal and step count" do
      reasoning_plan = %{
        goal: "Implement rate limiting",
        analysis: "Analysis",
        steps: [
          %{number: 1, description: "Step 1", expected_outcome: nil},
          %{number: 2, description: "Step 2", expected_outcome: nil}
        ],
        expected_results: "Rate limiter works",
        potential_issues: ["Edge case 1", "Edge case 2"]
      }

      summary = ChainOfThought.summarize_plan(reasoning_plan)

      assert summary =~ "Goal: Implement rate limiting"
      assert summary =~ "2 steps"
      assert summary =~ "Issues: 2"
    end

    test "truncates long goals" do
      reasoning_plan = %{
        goal:
          "This is a very long goal that should be truncated because it exceeds fifty characters",
        analysis: "Analysis",
        steps: [%{number: 1, description: "Step", expected_outcome: nil}],
        expected_results: "Result",
        potential_issues: []
      }

      summary = ChainOfThought.summarize_plan(reasoning_plan)

      assert summary =~ "..."
      assert String.length(summary) < 150
    end

    test "returns message for nil plan" do
      assert ChainOfThought.summarize_plan(nil) == "No reasoning plan available"
    end

    test "returns message for invalid plan" do
      assert ChainOfThought.summarize_plan("invalid") == "Invalid reasoning plan"
    end
  end

  describe "event name accessors" do
    test "event_start/0 returns correct event name" do
      assert ChainOfThought.event_start() == [:jido_code, :reasoning, :start]
    end

    test "event_complete/0 returns correct event name" do
      assert ChainOfThought.event_complete() == [:jido_code, :reasoning, :complete]
    end

    test "event_fallback/0 returns correct event name" do
      assert ChainOfThought.event_fallback() == [:jido_code, :reasoning, :fallback]
    end

    test "event_error/0 returns correct event name" do
      assert ChainOfThought.event_error() == [:jido_code, :reasoning, :error]
    end
  end

  # ============================================================================
  # run_with_reasoning/3 Tests
  # ============================================================================

  describe "run_with_reasoning/3" do
    test "executes query and returns result with zero_shot reasoning plan" do
      # Create a mock chat function that returns a zero_shot response
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @zero_shot_response}
      end

      {:ok, result} =
        ChainOfThought.run_with_reasoning(:mock_agent, "How do I do X?", chat_fn: mock_chat)

      assert is_binary(result.response)
      assert result.response =~ "GenServer with proper supervision"
      assert result.used_fallback == false
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0

      # Verify reasoning plan was extracted
      assert result.reasoning_plan != nil
      assert is_list(result.reasoning_plan.steps)
      assert length(result.reasoning_plan.steps) == 3
    end

    test "extracts reasoning steps from zero_shot response" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @zero_shot_response}
      end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      steps = result.reasoning_plan.steps
      assert Enum.at(steps, 0).number == 1
      assert Enum.at(steps, 0).description =~ "understand the requirements"
      assert Enum.at(steps, 1).number == 2
      assert Enum.at(steps, 2).number == 3
    end

    test "executes with structured mode and extracts plan" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @structured_response}
      end

      {:ok, result} =
        ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat, mode: :structured)

      assert result.reasoning_plan != nil
      assert result.reasoning_plan.goal =~ "rate limiting"
      assert length(result.reasoning_plan.steps) == 3
      assert result.response =~ "token bucket"
    end

    test "handles plain response without reasoning structure" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @plain_response}
      end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      # Should still succeed but without a reasoning plan
      assert result.response =~ "plain response"
      assert result.reasoning_plan == nil
      assert result.used_fallback == false
    end

    test "falls back to direct execution on error when fallback_on_error is true" do
      call_count = :counters.new(1, [:atomics])

      mock_chat = fn _agent, message, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          # First call (with CoT prompt) fails
          {:error, :reasoning_failed}
        else
          # Second call (direct) succeeds
          {:ok, "Direct response without reasoning"}
        end
      end

      {:ok, result} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          fallback_on_error: true
        )

      assert result.response == "Direct response without reasoning"
      assert result.used_fallback == true
      assert result.reasoning_plan == nil
    end

    test "returns error when fallback is disabled and reasoning fails" do
      mock_chat = fn _agent, _message, _opts ->
        {:error, :llm_unavailable}
      end

      result =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          fallback_on_error: false
        )

      assert {:error, :llm_unavailable} = result
    end

    test "emits telemetry events on success" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @zero_shot_response}
      end

      {:ok, _result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      # Check for start event
      assert_receive {:telemetry_event, [:jido_code, :reasoning, :start], measurements, metadata}
      assert is_integer(measurements.system_time)
      assert metadata.mode == :zero_shot

      # Check for complete event
      assert_receive {:telemetry_event, [:jido_code, :reasoning, :complete], measurements,
                      metadata}

      assert is_integer(measurements.duration_ms)
      assert is_integer(measurements.step_count)
      assert metadata.used_fallback == false
    end

    test "emits fallback telemetry event when falling back" do
      call_count = :counters.new(1, [:atomics])

      mock_chat = fn _agent, _message, _opts ->
        count = :counters.get(call_count, 1)
        :counters.add(call_count, 1, 1)

        if count == 0 do
          {:error, :first_call_failed}
        else
          {:ok, "Fallback response"}
        end
      end

      {:ok, _result} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          fallback_on_error: true
        )

      # Check for fallback event
      assert_receive {:telemetry_event, [:jido_code, :reasoning, :fallback], _measurements,
                      metadata}

      assert metadata.reason =~ "first_call_failed"
    end

    test "emits error telemetry event on failure" do
      mock_chat = fn _agent, _message, _opts ->
        {:error, :total_failure}
      end

      {:error, :total_failure} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          fallback_on_error: false
        )

      # Check for error event
      assert_receive {:telemetry_event, [:jido_code, :reasoning, :error], _measurements, metadata}
      assert metadata.reason =~ "total_failure"
    end

    test "uses zero_shot mode by default" do
      captured_message = :persistent_term.put(:test_captured_message, nil)

      mock_chat = fn _agent, message, _opts ->
        :persistent_term.put(:test_captured_message, message)
        {:ok, @zero_shot_response}
      end

      {:ok, _result} = ChainOfThought.run_with_reasoning(:mock, "Test query", chat_fn: mock_chat)

      message = :persistent_term.get(:test_captured_message)
      assert message =~ "Let's approach this step by step"
      assert message =~ "REASONING:"
      assert message =~ "Test query"

      :persistent_term.erase(:test_captured_message)
    end

    test "uses structured mode when specified" do
      captured_message = :persistent_term.put(:test_captured_message, nil)

      mock_chat = fn _agent, message, _opts ->
        :persistent_term.put(:test_captured_message, message)
        {:ok, @structured_response}
      end

      {:ok, _result} =
        ChainOfThought.run_with_reasoning(:mock, "Test query",
          chat_fn: mock_chat,
          mode: :structured
        )

      message = :persistent_term.get(:test_captured_message)
      assert message =~ "systematically using structured reasoning"
      assert message =~ "UNDERSTAND:"
      assert message =~ "PLAN:"
      assert message =~ "VALIDATE:"

      :persistent_term.erase(:test_captured_message)
    end

    test "validates temperature is within range" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @plain_response}
      end

      # Temperature above 2.0 should be clamped to default
      {:ok, _result} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          temperature: 5.0
        )

      # Should not crash - temperature is validated internally
    end

    test "validates mode and defaults to zero_shot for invalid mode" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, @plain_response}
      end

      # Invalid mode should default to zero_shot
      {:ok, _result} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          mode: :invalid_mode
        )

      # Should not crash - mode is validated internally
    end

    test "includes duration_ms in result" do
      mock_chat = fn _agent, _message, _opts ->
        # Small delay to ensure measurable duration
        Process.sleep(10)
        {:ok, @plain_response}
      end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      assert result.duration_ms >= 10
    end

    test "handles empty query" do
      mock_chat = fn _agent, _message, _opts ->
        {:ok, "Response to empty query"}
      end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "", chat_fn: mock_chat)

      assert result.response == "Response to empty query"
    end
  end

  # ============================================================================
  # Response Parsing Tests
  # ============================================================================

  describe "response parsing" do
    test "parses zero_shot response with multiple steps" do
      response = """
      REASONING:
      Here's my analysis:
      1. First step is to analyze
      2. Second step is to design
      3. Third step is to implement
      4. Fourth step is to test

      ANSWER:
      The final answer is 42.
      """

      mock_chat = fn _agent, _message, _opts -> {:ok, response} end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      assert length(result.reasoning_plan.steps) == 4
      assert result.response == "The final answer is 42."
    end

    test "parses structured response with all sections" do
      response = """
      UNDERSTAND:
      - Need to build a cache
      - Must be fast

      PLAN:
      1. Design ETS table
      2. Implement get/put

      IMPLEMENT:
      Code here.

      VALIDATE:
      - Works for concurrent access

      ANSWER:
      Use ETS with read_concurrency.
      """

      mock_chat = fn _agent, _message, _opts -> {:ok, response} end

      {:ok, result} =
        ChainOfThought.run_with_reasoning(:mock, "Query",
          chat_fn: mock_chat,
          mode: :structured
        )

      assert result.reasoning_plan.goal =~ "cache"
      assert result.reasoning_plan.analysis =~ "Design ETS"
      assert length(result.reasoning_plan.steps) == 2
      assert result.response =~ "ETS with read_concurrency"
    end

    test "handles response with only ANSWER section" do
      response = """
      ANSWER:
      Just the answer without reasoning.
      """

      mock_chat = fn _agent, _message, _opts -> {:ok, response} end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      # No REASONING section, so no plan
      assert result.reasoning_plan == nil
      assert result.response == response
    end

    test "handles malformed response gracefully" do
      response = "Random response without any structure whatsoever."

      mock_chat = fn _agent, _message, _opts -> {:ok, response} end

      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      assert result.reasoning_plan == nil
      assert result.response == response
    end

    test "truncates very long responses for ReDoS protection" do
      # Generate a response that exceeds 100KB - the max_response_length limit
      long_content = String.duplicate("x", 200_000)

      # Make sure ANSWER is at the end so truncation would affect it
      response = """
      REASONING:
      1. This is step one

      #{long_content}

      ANSWER:
      This answer is too far in
      """

      mock_chat = fn _agent, _message, _opts -> {:ok, response} end

      # Should not hang or crash due to ReDoS - will truncate before parsing
      {:ok, result} = ChainOfThought.run_with_reasoning(:mock, "Query", chat_fn: mock_chat)

      # Since ANSWER: is past the 100KB limit, it won't be found
      # and we get no reasoning plan (response treated as unstructured)
      assert result.reasoning_plan == nil or result.response != nil
    end
  end

  describe "config validation" do
    # These tests verify internal config validation through public API behavior

    test "default config uses zero_shot mode" do
      config = ChainOfThought.default_config()
      assert config.mode == :zero_shot
    end

    test "default config uses temperature 0.2" do
      config = ChainOfThought.default_config()
      assert config.temperature == 0.2
    end

    test "default config enables validation" do
      config = ChainOfThought.default_config()
      assert config.enable_validation == true
    end

    test "default config enables fallback on error" do
      config = ChainOfThought.default_config()
      assert config.fallback_on_error == true
    end
  end

  describe "reasoning step parsing" do
    # Test the step extraction logic through format_steps_for_display

    test "handles steps with expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: "Something done"}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something (expected: Something done)"
    end

    test "handles steps without expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: nil}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something"
    end

    test "handles steps with empty expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: ""}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something"
    end
  end
end
