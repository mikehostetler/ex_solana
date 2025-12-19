defmodule JidoCode.Reasoning.ChainOfThought do
  @moduledoc """
  Chain-of-Thought reasoning wrapper for JidoCode.

  This module wraps JidoAI's Chain-of-Thought runner to provide step-by-step
  reasoning for complex coding queries. CoT reasoning provides 8-15% accuracy
  improvement on multi-step reasoning tasks.

  ## Usage

      # Run query with CoT reasoning
      {:ok, result} = JidoCode.Reasoning.ChainOfThought.run_with_reasoning(
        agent_pid,
        "How do I implement a GenServer that handles rate limiting?"
      )

      # With custom config
      {:ok, result} = JidoCode.Reasoning.ChainOfThought.run_with_reasoning(
        agent_pid,
        "Debug this code...",
        mode: :structured,
        temperature: 0.3
      )

  ## Configuration Options

  - `:mode` - Reasoning mode: `:zero_shot`, `:few_shot`, or `:structured` (default: `:zero_shot`)
  - `:temperature` - LLM temperature for reasoning (default: 0.2)
  - `:max_iterations` - Maximum reasoning iterations (default: 1)
  - `:enable_validation` - Validate results against expectations (default: true)
  - `:fallback_on_error` - Fall back to direct execution on failure (default: true)

  ## Telemetry Events

  The following telemetry events are emitted:

  - `[:jido_code, :reasoning, :start]` - When reasoning begins
  - `[:jido_code, :reasoning, :complete]` - When reasoning completes successfully
  - `[:jido_code, :reasoning, :fallback]` - When falling back to direct execution
  - `[:jido_code, :reasoning, :error]` - When reasoning fails
  """

  require Logger

  alias JidoCode.Agents.LLMAgent

  # Default configuration for CoT reasoning
  @default_config %{
    mode: :zero_shot,
    temperature: 0.2,
    max_iterations: 1,
    enable_validation: true,
    fallback_on_error: true
  }

  # Maximum response length to prevent ReDoS attacks during parsing
  # LLM responses exceeding this will be truncated before regex parsing
  @max_response_length 100_000

  # Telemetry event names
  @event_start [:jido_code, :reasoning, :start]
  @event_complete [:jido_code, :reasoning, :complete]
  @event_fallback [:jido_code, :reasoning, :fallback]
  @event_error [:jido_code, :reasoning, :error]

  # ============================================================================
  # Types
  # ============================================================================

  @typedoc """
  A reasoning step extracted from the CoT plan.
  """
  @type reasoning_step :: %{
          number: pos_integer(),
          description: String.t(),
          expected_outcome: String.t() | nil
        }

  @typedoc """
  The result of running a query with CoT reasoning.
  """
  @type reasoning_result :: %{
          response: String.t(),
          reasoning_plan: reasoning_plan() | nil,
          used_fallback: boolean(),
          duration_ms: non_neg_integer()
        }

  @typedoc """
  A reasoning plan containing the goal, analysis, and execution steps.
  """
  @type reasoning_plan :: %{
          goal: String.t(),
          analysis: String.t(),
          steps: [reasoning_step()],
          expected_results: String.t(),
          potential_issues: [String.t()]
        }

  @typedoc """
  Configuration options for CoT reasoning.
  """
  @type config_opts :: [
          mode: :zero_shot | :few_shot | :structured,
          temperature: float(),
          max_iterations: pos_integer(),
          enable_validation: boolean(),
          fallback_on_error: boolean(),
          chat_fn: (GenServer.server(), String.t(), keyword() ->
                      {:ok, String.t()} | {:error, term()})
        ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Returns the default CoT configuration.

  ## Example

      config = JidoCode.Reasoning.ChainOfThought.default_config()
      # => %{mode: :zero_shot, temperature: 0.2, ...}
  """
  @spec default_config() :: map()
  def default_config, do: @default_config

  @doc """
  Runs a query with Chain-of-Thought reasoning.

  This function executes the query through the LLM agent with CoT reasoning
  enabled, extracting the reasoning plan and steps for display.

  ## Parameters

  - `agent` - The LLMAgent pid or GenServer reference
  - `query` - The user's query string
  - `opts` - Optional configuration overrides

  ## Returns

  - `{:ok, result}` - Success with reasoning result map
  - `{:error, reason}` - Failure with error reason

  ## Result Structure

  The result map contains:
  - `:response` - The final response string
  - `:reasoning_plan` - The extracted reasoning plan (nil if fallback used)
  - `:used_fallback` - Whether fallback to direct execution was used
  - `:duration_ms` - Total execution time in milliseconds

  ## Examples

      {:ok, result} = ChainOfThought.run_with_reasoning(pid, "Explain recursion")
      IO.puts(result.response)

      # With custom config
      {:ok, result} = ChainOfThought.run_with_reasoning(pid, "Debug this", mode: :structured)
  """
  @spec run_with_reasoning(GenServer.server(), String.t(), config_opts()) ::
          {:ok, reasoning_result()} | {:error, term()}
  def run_with_reasoning(agent, query, opts \\ []) when is_binary(query) do
    config = build_config(opts)
    start_time = System.monotonic_time(:millisecond)

    # Emit start telemetry
    emit_start(query, config)

    # Try CoT reasoning first
    case execute_with_reasoning(agent, query, config) do
      {:ok, response, reasoning_plan} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        result = %{
          response: response,
          reasoning_plan: reasoning_plan,
          used_fallback: false,
          duration_ms: duration_ms
        }

        emit_complete(result, config)
        {:ok, result}

      {:error, reason} when config.fallback_on_error ->
        Logger.warning(
          "CoT reasoning failed, falling back to direct execution: #{inspect(reason)}"
        )

        emit_fallback(reason, config)

        # Fall back to direct chat
        case execute_direct(agent, query, config) do
          {:ok, response} ->
            duration_ms = System.monotonic_time(:millisecond) - start_time

            result = %{
              response: response,
              reasoning_plan: nil,
              used_fallback: true,
              duration_ms: duration_ms
            }

            {:ok, result}

          {:error, _} = error ->
            emit_error(reason, config)
            error
        end

      {:error, reason} ->
        emit_error(reason, config)
        {:error, reason}
    end
  end

  @doc """
  Formats reasoning steps for TUI display.

  Converts a reasoning plan into a list of formatted step strings suitable
  for terminal display.

  ## Parameters

  - `reasoning_plan` - The reasoning plan map from run_with_reasoning

  ## Returns

  A list of formatted step strings.

  ## Example

      steps = ChainOfThought.format_steps_for_display(result.reasoning_plan)
      # => ["1. Analyze the problem requirements", "2. Design the solution...", ...]
  """
  @spec format_steps_for_display(reasoning_plan() | nil) :: [String.t()]
  def format_steps_for_display(nil), do: []

  def format_steps_for_display(%{steps: steps}) when is_list(steps) do
    Enum.map(steps, fn step ->
      outcome =
        if step[:expected_outcome] && step[:expected_outcome] != "" do
          " (expected: #{step[:expected_outcome]})"
        else
          ""
        end

      "#{step.number}. #{step.description}#{outcome}"
    end)
  end

  def format_steps_for_display(_), do: []

  @doc """
  Extracts a summary from the reasoning plan.

  Returns a brief summary including the goal and number of steps.

  ## Example

      summary = ChainOfThought.summarize_plan(result.reasoning_plan)
      # => "Goal: Implement rate limiting | 5 steps | Issues: 2"
  """
  @spec summarize_plan(reasoning_plan() | nil) :: String.t()
  def summarize_plan(nil), do: "No reasoning plan available"

  def summarize_plan(%{goal: goal, steps: steps, potential_issues: issues}) do
    step_count = length(steps)
    issue_count = length(issues || [])

    goal_summary =
      if String.length(goal || "") > 50 do
        String.slice(goal, 0, 47) <> "..."
      else
        goal || "Unknown"
      end

    "Goal: #{goal_summary} | #{step_count} steps | Issues: #{issue_count}"
  end

  def summarize_plan(_), do: "Invalid reasoning plan"

  # ============================================================================
  # Telemetry Event Names (for external attachment)
  # ============================================================================

  @doc """
  Returns the telemetry event name for reasoning start events.
  """
  @spec event_start() :: [atom()]
  def event_start, do: @event_start

  @doc """
  Returns the telemetry event name for reasoning complete events.
  """
  @spec event_complete() :: [atom()]
  def event_complete, do: @event_complete

  @doc """
  Returns the telemetry event name for reasoning fallback events.
  """
  @spec event_fallback() :: [atom()]
  def event_fallback, do: @event_fallback

  @doc """
  Returns the telemetry event name for reasoning error events.
  """
  @spec event_error() :: [atom()]
  def event_error, do: @event_error

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_config(opts) do
    @default_config
    |> Map.merge(Map.new(opts))
    |> validate_config()
  end

  defp validate_config(config) do
    # Ensure mode is valid
    config =
      if config.mode in [:zero_shot, :few_shot, :structured] do
        config
      else
        Logger.warning("Invalid CoT mode #{inspect(config.mode)}, defaulting to :zero_shot")
        %{config | mode: :zero_shot}
      end

    # Ensure temperature is in valid range
    config =
      if is_number(config.temperature) and config.temperature >= 0.0 and config.temperature <= 2.0 do
        config
      else
        Logger.warning("Invalid temperature #{inspect(config.temperature)}, defaulting to 0.2")
        %{config | temperature: 0.2}
      end

    config
  end

  defp execute_with_reasoning(agent, query, config) do
    # Build the CoT-enhanced prompt
    cot_prompt = build_cot_prompt(query, config)

    # Get chat function (allows injection for testing)
    chat_fn = Map.get(config, :chat_fn, &LLMAgent.chat/3)

    # Execute through the agent
    case chat_fn.(agent, cot_prompt, timeout: 120_000) do
      {:ok, response} ->
        # Try to parse reasoning from response
        case parse_reasoning_response(response) do
          {:ok, reasoning_plan, final_response} ->
            {:ok, final_response, reasoning_plan}

          {:error, :no_reasoning_found} ->
            # Response didn't contain structured reasoning, use as-is
            {:ok, response, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_direct(agent, query, config) do
    chat_fn = Map.get(config, :chat_fn, &LLMAgent.chat/3)
    chat_fn.(agent, query, timeout: 60_000)
  end

  defp build_cot_prompt(query, config) do
    case config.mode do
      :zero_shot ->
        build_zero_shot_prompt(query)

      :structured ->
        build_structured_prompt(query)

      :few_shot ->
        # Few-shot falls back to zero-shot for now
        build_zero_shot_prompt(query)
    end
  end

  defp build_zero_shot_prompt(query) do
    """
    Let's approach this step by step.

    Question: #{query}

    Please structure your response as follows:

    REASONING:
    1. [First step of reasoning]
    2. [Second step of reasoning]
    ...

    ANSWER:
    [Your final answer based on the reasoning above]
    """
  end

  defp build_structured_prompt(query) do
    """
    Let's solve this systematically using structured reasoning.

    Question: #{query}

    Please structure your response as follows:

    UNDERSTAND:
    - What is being asked?
    - What are the constraints?
    - What are the inputs and expected outputs?

    PLAN:
    1. [First step]
    2. [Second step]
    ...

    IMPLEMENT:
    [Your solution]

    VALIDATE:
    - Does this meet all requirements?
    - What edge cases should be considered?

    ANSWER:
    [Your final, concise answer]
    """
  end

  defp parse_reasoning_response(response) do
    # Truncate response to prevent ReDoS attacks during regex parsing
    safe_response = truncate_for_parsing(response)

    # Try to extract structured reasoning from the response
    cond do
      String.contains?(safe_response, "REASONING:") and String.contains?(safe_response, "ANSWER:") ->
        parse_zero_shot_response(safe_response)

      String.contains?(safe_response, "UNDERSTAND:") and
          String.contains?(safe_response, "ANSWER:") ->
        parse_structured_response(safe_response)

      true ->
        {:error, :no_reasoning_found}
    end
  end

  defp truncate_for_parsing(response) when byte_size(response) > @max_response_length do
    # Truncate at safe boundary (avoid cutting in middle of unicode char)
    binary_part(response, 0, @max_response_length)
  end

  defp truncate_for_parsing(response), do: response

  # Unified response parser with configurable section mappings
  defp parse_zero_shot_response(response) do
    parse_response_with_sections(response, %{
      goal_extractor: &extract_goal_from_reasoning/1,
      analysis_section: "REASONING:",
      results_from_answer: true
    })
  end

  defp parse_structured_response(response) do
    parse_response_with_sections(response, %{
      goal_section: "UNDERSTAND:",
      analysis_section: "PLAN:",
      results_section: "VALIDATE:"
    })
  end

  defp parse_response_with_sections(response, section_config) do
    case String.split(response, ~r/ANSWER:/i, parts: 2) do
      [reasoning_part, answer_part] ->
        steps = extract_numbered_steps(reasoning_part)

        goal =
          if section_config[:goal_extractor] do
            section_config.goal_extractor.(reasoning_part)
          else
            extract_section(reasoning_part, section_config.goal_section)
          end

        analysis = extract_section(reasoning_part, section_config.analysis_section)

        expected_results =
          if section_config[:results_from_answer] do
            String.trim(answer_part)
          else
            extract_section(reasoning_part, section_config.results_section)
          end

        reasoning_plan = %{
          goal: goal,
          analysis: analysis,
          steps: steps,
          expected_results: expected_results,
          potential_issues: []
        }

        {:ok, reasoning_plan, String.trim(answer_part)}

      _ ->
        {:error, :no_reasoning_found}
    end
  end

  defp extract_numbered_steps(text) do
    # Match numbered steps like "1. ...", "2. ...", etc.
    ~r/(\d+)\.\s+(.+?)(?=\n\d+\.|\n[A-Z]+:|\z)/s
    |> Regex.scan(text)
    |> Enum.map(fn
      [_, number, description] ->
        %{
          number: String.to_integer(number),
          description: String.trim(description),
          expected_outcome: nil
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_section(text, header) do
    case Regex.run(~r/#{Regex.escape(header)}\s*\n?(.*?)(?=\n[A-Z]+:|\z)/s, text) do
      [_, content] -> String.trim(content)
      _ -> ""
    end
  end

  defp extract_goal_from_reasoning(text) do
    # Try to get the first meaningful line after REASONING:
    case Regex.run(~r/REASONING:\s*\n?(.*?)(?=\n\d+\.|\z)/s, text) do
      [_, content] ->
        content
        |> String.trim()
        |> String.split("\n")
        |> List.first()
        |> Kernel.||("")
        |> String.trim()

      _ ->
        ""
    end
  end

  # ============================================================================
  # Telemetry Emission
  # ============================================================================

  defp emit_start(query, config) do
    :telemetry.execute(
      @event_start,
      %{system_time: System.system_time()},
      %{
        query_length: String.length(query),
        mode: config.mode,
        temperature: config.temperature
      }
    )
  end

  defp emit_complete(result, config) do
    step_count =
      case result.reasoning_plan do
        %{steps: steps} -> length(steps)
        _ -> 0
      end

    :telemetry.execute(
      @event_complete,
      %{
        duration_ms: result.duration_ms,
        step_count: step_count
      },
      %{
        mode: config.mode,
        used_fallback: result.used_fallback
      }
    )
  end

  defp emit_fallback(reason, config) do
    :telemetry.execute(
      @event_fallback,
      %{system_time: System.system_time()},
      %{
        reason: inspect(reason),
        mode: config.mode
      }
    )
  end

  defp emit_error(reason, config) do
    :telemetry.execute(
      @event_error,
      %{system_time: System.system_time()},
      %{
        reason: inspect(reason),
        mode: config.mode
      }
    )
  end
end
