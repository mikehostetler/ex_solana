defmodule JidoCode.Reasoning.QueryClassifier do
  @moduledoc """
  Query classifier for determining when to use Chain-of-Thought reasoning.

  This module analyzes query text to determine whether CoT reasoning should be
  applied. CoT adds 2-3s latency and 3-4x token cost, so it's only applied to
  complex queries that benefit from step-by-step reasoning.

  ## Usage

      # Check if CoT should be used
      JidoCode.Reasoning.QueryClassifier.should_use_cot?("How do I implement a GenServer?")
      # => true

      JidoCode.Reasoning.QueryClassifier.should_use_cot?("hello")
      # => false

      # Force CoT on/off
      JidoCode.Reasoning.QueryClassifier.classify("hello", force_cot: true)
      # => true

  ## Classification Heuristics

  **Complex queries (use CoT):**
  - Debugging/troubleshooting requests
  - Explanation requests ("explain", "how does", "why")
  - Multi-step instructions ("step by step", "walk through")
  - Implementation requests ("how to", "implement", "create")
  - Comparison requests ("compare", "difference between")
  - Code blocks present
  - Long queries (>100 characters)

  **Simple queries (direct response):**
  - Greetings ("hi", "hello", "hey")
  - Single-word queries
  - Confirmations ("yes", "no", "ok")
  - Very short queries (<20 characters)
  """

  # ============================================================================
  # Complexity Keywords
  # ============================================================================

  # Keywords that suggest the query needs multi-step reasoning
  @complexity_keywords [
    # Debugging
    "debug",
    "fix",
    "solve",
    "troubleshoot",
    "error",
    "bug",
    "issue",
    "problem",
    "broken",
    "doesn't work",
    "not working",
    "failing",
    # Explanation
    "explain",
    "how does",
    "why does",
    "why is",
    "what does",
    "what is the difference",
    "understand",
    # Step-by-step
    "step by step",
    "walk through",
    "walk me through",
    "break down",
    "breakdown",
    # How-to
    "how to",
    "how do i",
    "how can i",
    "how should i",
    "how would i",
    # Implementation
    "implement",
    "create",
    "build",
    "design",
    "architect",
    "write a",
    "write an",
    "make a",
    "make an",
    # Comparison
    "compare",
    "difference between",
    "versus",
    " vs ",
    "better than",
    "pros and cons",
    # Optimization
    "optimize",
    "improve",
    "refactor",
    "performance",
    "faster",
    "efficient",
    # Analysis
    "analyze",
    "review",
    "evaluate",
    "assess"
  ]

  # Patterns that indicate code-related complexity
  @code_patterns [
    # Code blocks
    ~r/```/,
    # Stack traces
    ~r/\*\* \(/,
    ~r/at line \d+/i,
    ~r/stacktrace/i,
    # Error patterns
    ~r/\w+Error:/,
    ~r/exception/i,
    # Module references
    ~r/\b[A-Z][a-z]+\.[A-Z][a-z]+/
  ]

  # ============================================================================
  # Simplicity Patterns
  # ============================================================================

  # Greetings and simple interactions
  @greeting_patterns [
    ~r/^h(i|ey|ello|owdy)!?$/i,
    ~r/^thanks?!?$/i,
    ~r/^thank you!?$/i,
    ~r/^good (morning|afternoon|evening)!?$/i,
    ~r/^(bye|goodbye|see ya)!?$/i
  ]

  # Confirmations
  @confirmation_patterns [
    ~r/^(yes|no|ok|okay|sure|yep|nope|yup|nah)!?\.?$/i,
    ~r/^(got it|understood|makes sense)!?\.?$/i,
    ~r/^(perfect|great|cool|nice|awesome)!?\.?$/i
  ]

  # Follow-up patterns (context-dependent, usually simple)
  @followup_patterns [
    ~r/^(and|also|what about)\b/i,
    ~r/^more\b/i,
    ~r/^(show me|give me) (more|another)/i
  ]

  # ============================================================================
  # Thresholds
  # ============================================================================

  @min_complex_length 100
  @max_simple_length 20
  @multiple_questions_threshold 2

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Determines if Chain-of-Thought reasoning should be used for the given query.

  This is a convenience function that calls `classify/2` with no options.

  ## Parameters

  - `query` - The query string to classify

  ## Returns

  `true` if CoT should be used, `false` otherwise.

  ## Examples

      iex> QueryClassifier.should_use_cot?("How do I implement a GenServer?")
      true

      iex> QueryClassifier.should_use_cot?("hello")
      false
  """
  @spec should_use_cot?(String.t()) :: boolean()
  def should_use_cot?(query) when is_binary(query) do
    classify(query)
  end

  @doc """
  Classifies a query and returns whether CoT reasoning should be used.

  ## Parameters

  - `query` - The query string to classify
  - `opts` - Options for classification

  ## Options

  - `:force_cot` - Force CoT on (`true`), off (`false`), or use classification (`nil`)

  ## Returns

  `true` if CoT should be used, `false` otherwise.

  ## Examples

      # Normal classification
      QueryClassifier.classify("How do I debug this?")
      # => true

      # Force CoT on
      QueryClassifier.classify("hello", force_cot: true)
      # => true

      # Force CoT off
      QueryClassifier.classify("How do I implement X?", force_cot: false)
      # => false
  """
  @spec classify(String.t(), keyword()) :: boolean()
  def classify(query, opts \\ []) when is_binary(query) do
    # Check for force override first
    case Keyword.get(opts, :force_cot) do
      true -> true
      false -> false
      nil -> do_classify(query)
    end
  end

  @doc """
  Returns the complexity score for a query (for debugging/tuning).

  The score is based on the number of complexity indicators found.
  A score >= 1 indicates the query should use CoT.

  ## Parameters

  - `query` - The query string to analyze

  ## Returns

  A map with:
  - `:score` - Numeric complexity score
  - `:reasons` - List of reasons for the score
  - `:should_use_cot` - Boolean recommendation

  ## Examples

      QueryClassifier.analyze("How do I debug this error?")
      # => %{score: 2, reasons: ["keyword: debug", "keyword: error"], should_use_cot: true}
  """
  @spec analyze(String.t()) :: %{
          score: number(),
          reasons: [String.t()],
          should_use_cot: boolean()
        }
  def analyze(query) when is_binary(query) do
    normalized = normalize_query(query)

    # Check simplicity first
    simplicity_result = check_simplicity(normalized, query)

    case simplicity_result do
      {:simple, reason} ->
        %{score: 0, reasons: [reason], should_use_cot: false}

      :not_simple ->
        # Calculate complexity score
        {score, reasons} = calculate_complexity(normalized, query)
        %{score: score, reasons: reasons, should_use_cot: score >= 1}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_classify(query) do
    normalized = normalize_query(query)

    # Fast path: check for simplicity patterns first
    case check_simplicity(normalized, query) do
      {:simple, _reason} ->
        false

      :not_simple ->
        # Check for complexity indicators
        {score, _reasons} = calculate_complexity(normalized, query)
        score >= 1
    end
  end

  defp normalize_query(query) do
    query
    |> String.downcase()
    |> String.trim()
  end

  defp check_simplicity(normalized, original) do
    cond do
      # Check greetings
      matches_any_pattern?(normalized, @greeting_patterns) ->
        {:simple, "greeting"}

      # Check confirmations
      matches_any_pattern?(normalized, @confirmation_patterns) ->
        {:simple, "confirmation"}

      # Check single word (after trimming)
      single_word?(normalized) ->
        {:simple, "single word"}

      # Check very short queries without complexity keywords
      very_short_without_keywords?(normalized) ->
        {:simple, "very short"}

      # Check follow-ups (usually context-dependent)
      matches_any_pattern?(normalized, @followup_patterns) and String.length(original) < 50 ->
        {:simple, "short follow-up"}

      true ->
        :not_simple
    end
  end

  defp calculate_complexity(normalized, original) do
    reasons = []
    score = 0

    # Check for complexity keywords
    {keyword_score, keyword_reasons} = check_keywords(normalized)
    score = score + keyword_score
    reasons = reasons ++ keyword_reasons

    # Check for code patterns
    {code_score, code_reasons} = check_code_patterns(original)
    score = score + code_score
    reasons = reasons ++ code_reasons

    # Check query length
    {length_score, length_reasons} = check_length(original)
    score = score + length_score
    reasons = reasons ++ length_reasons

    # Check for multiple questions
    {question_score, question_reasons} = check_questions(original)
    score = score + question_score
    reasons = reasons ++ question_reasons

    {score, reasons}
  end

  defp check_keywords(normalized) do
    found_keywords =
      @complexity_keywords
      |> Enum.filter(fn keyword -> String.contains?(normalized, keyword) end)
      |> Enum.take(3)

    score = min(length(found_keywords), 2)
    reasons = Enum.map(found_keywords, fn kw -> "keyword: #{kw}" end)

    {score, reasons}
  end

  defp check_code_patterns(original) do
    matches =
      @code_patterns
      |> Enum.filter(fn pattern -> Regex.match?(pattern, original) end)
      |> Enum.take(2)

    score = min(length(matches), 2)

    reasons =
      cond do
        Regex.match?(~r/```/, original) -> ["contains code block"]
        Regex.match?(~r/stacktrace/i, original) -> ["contains stack trace"]
        Regex.match?(~r/\w+Error:/, original) -> ["contains error"]
        length(matches) > 0 -> ["contains code patterns"]
        true -> []
      end

    {score, reasons}
  end

  defp check_length(original) do
    len = String.length(original)

    if len >= @min_complex_length do
      {1, ["long query (#{len} chars)"]}
    else
      {0, []}
    end
  end

  defp check_questions(original) do
    question_count = original |> String.graphemes() |> Enum.count(&(&1 == "?"))

    if question_count >= @multiple_questions_threshold do
      {1, ["multiple questions (#{question_count})"]}
    else
      {0, []}
    end
  end

  defp matches_any_pattern?(text, patterns) do
    Enum.any?(patterns, fn pattern -> Regex.match?(pattern, text) end)
  end

  defp single_word?(normalized) do
    not String.contains?(normalized, " ")
  end

  defp very_short_without_keywords?(normalized) do
    String.length(normalized) <= @max_simple_length and
      not Enum.any?(@complexity_keywords, fn kw -> String.contains?(normalized, kw) end)
  end
end
