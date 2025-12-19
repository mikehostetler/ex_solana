defmodule JidoCode.Reasoning.QueryClassifierTest do
  use ExUnit.Case, async: true

  alias JidoCode.Reasoning.QueryClassifier

  @moduletag :reasoning

  # ============================================================================
  # Test Data Sets
  # ============================================================================

  # Complex queries that SHOULD use CoT (expected: true)
  @complex_queries [
    # Debugging
    "How do I debug this error?",
    "Can you help me fix this bug?",
    "Why is my code not working?",
    "I'm getting an error when I run this",
    "My function is broken, can you help?",
    "This test is failing, what's wrong?",
    "Help me troubleshoot this issue",

    # Explanation
    "Explain how GenServers work in Elixir",
    "How does pattern matching work?",
    "Why does Elixir use immutable data?",
    "What is the difference between a map and a struct?",
    "Can you explain this code?",

    # Step-by-step
    "Walk me through how to set up a Phoenix project",
    "Break down this algorithm step by step",
    "Can you walk through this code?",

    # How-to
    "How do I implement a GenServer?",
    "How can I create a supervision tree?",
    "How to handle errors in Elixir?",
    "How should I structure my application?",
    "How would I build a rate limiter?",

    # Implementation
    "Implement a stack data structure",
    "Create a function that reverses a list",
    "Build a simple HTTP client",
    "Design a caching system",
    "Write a recursive function for fibonacci",

    # Comparison
    "Compare GenServer vs Agent",
    "What's the difference between Task and GenServer?",
    "Pros and cons of using ETS vs Agent",
    "Is Phoenix better than other frameworks?",

    # Optimization
    "How can I optimize this query?",
    "Improve the performance of this function",
    "Refactor this code to be more efficient",

    # Analysis
    "Review this code for issues",
    "Analyze this function for bugs",

    # Code blocks
    """
    I have this code:
    ```elixir
    def foo(x) do
      x + 1
    end
    ```
    What's wrong with it?
    """,

    # Long complex queries
    "I'm building an application that needs to handle real-time updates and I'm not sure whether to use Phoenix Channels or LiveView. Can you help me understand the trade-offs and when to use each approach?",

    # Multiple questions
    "What is a GenServer? How do I create one? When should I use it?",

    # Error messages
    "I'm getting this error: ** (ArgumentError) argument error",
    "FunctionClauseError: no function clause matching"
  ]

  # Simple queries that should NOT use CoT (expected: false)
  @simple_queries [
    # Greetings
    "hi",
    "hello",
    "hey",
    "Hi!",
    "Hello!",
    "howdy",
    "good morning",
    "good afternoon",
    "thanks",
    "thank you",
    "bye",
    "goodbye",

    # Confirmations
    "yes",
    "no",
    "ok",
    "okay",
    "sure",
    "yep",
    "nope",
    "got it",
    "understood",
    "makes sense",
    "perfect",
    "great",
    "cool",
    "nice",
    "awesome",

    # Single words (non-keywords)
    "elixir",
    "phoenix",
    "test",

    # Very short queries
    "what?",
    "why?",
    "really?",
    "huh?",

    # Short follow-ups
    "and then?",
    "what about X?",
    "more please",
    "show me more"
  ]

  # ============================================================================
  # Basic Classification Tests
  # ============================================================================

  describe "should_use_cot?/1" do
    test "returns true for complex debugging queries" do
      assert QueryClassifier.should_use_cot?("How do I debug this error?")
      assert QueryClassifier.should_use_cot?("Can you help me fix this bug?")
      assert QueryClassifier.should_use_cot?("Why is my code not working?")
    end

    test "returns true for explanation queries" do
      assert QueryClassifier.should_use_cot?("Explain how GenServers work")
      assert QueryClassifier.should_use_cot?("How does pattern matching work?")
      assert QueryClassifier.should_use_cot?("What is the difference between map and struct?")
    end

    test "returns true for how-to queries" do
      assert QueryClassifier.should_use_cot?("How do I implement a GenServer?")
      assert QueryClassifier.should_use_cot?("How can I create a supervision tree?")
      assert QueryClassifier.should_use_cot?("How to handle errors?")
    end

    test "returns true for implementation queries" do
      assert QueryClassifier.should_use_cot?("Implement a stack data structure")
      assert QueryClassifier.should_use_cot?("Create a function that reverses a list")
      assert QueryClassifier.should_use_cot?("Build a simple HTTP client")
    end

    test "returns true for queries with code blocks" do
      query = """
      I have this code:
      ```elixir
      def foo(x), do: x + 1
      ```
      What's wrong?
      """

      assert QueryClassifier.should_use_cot?(query)
    end

    test "returns false for greetings" do
      refute QueryClassifier.should_use_cot?("hi")
      refute QueryClassifier.should_use_cot?("hello")
      refute QueryClassifier.should_use_cot?("hey")
      refute QueryClassifier.should_use_cot?("Hi!")
      refute QueryClassifier.should_use_cot?("thanks")
    end

    test "returns false for confirmations" do
      refute QueryClassifier.should_use_cot?("yes")
      refute QueryClassifier.should_use_cot?("no")
      refute QueryClassifier.should_use_cot?("ok")
      refute QueryClassifier.should_use_cot?("got it")
      refute QueryClassifier.should_use_cot?("perfect")
    end

    test "returns false for single words" do
      refute QueryClassifier.should_use_cot?("elixir")
      refute QueryClassifier.should_use_cot?("phoenix")
    end

    test "returns false for very short queries" do
      refute QueryClassifier.should_use_cot?("what?")
      refute QueryClassifier.should_use_cot?("huh?")
    end
  end

  # ============================================================================
  # Force Override Tests
  # ============================================================================

  describe "classify/2 with force_cot option" do
    test "force_cot: true overrides simple query" do
      assert QueryClassifier.classify("hello", force_cot: true)
      assert QueryClassifier.classify("yes", force_cot: true)
    end

    test "force_cot: false overrides complex query" do
      refute QueryClassifier.classify("How do I implement a GenServer?", force_cot: false)
      refute QueryClassifier.classify("Explain pattern matching", force_cot: false)
    end

    test "force_cot: nil uses normal classification" do
      assert QueryClassifier.classify("How do I debug this?", force_cot: nil)
      refute QueryClassifier.classify("hello", force_cot: nil)
    end
  end

  # ============================================================================
  # Analyze Function Tests
  # ============================================================================

  describe "analyze/1" do
    test "returns score and reasons for complex query" do
      result = QueryClassifier.analyze("How do I debug this error?")

      assert result.score >= 1
      assert result.should_use_cot == true
      assert is_list(result.reasons)
      assert length(result.reasons) > 0
    end

    test "returns zero score for simple query" do
      result = QueryClassifier.analyze("hello")

      assert result.score == 0
      assert result.should_use_cot == false
      assert "greeting" in result.reasons
    end

    test "identifies code block presence" do
      result = QueryClassifier.analyze("What's wrong with this code?\n```elixir\ncode\n```")

      assert "contains code block" in result.reasons
    end

    test "identifies long queries" do
      long_query = String.duplicate("word ", 30)
      result = QueryClassifier.analyze(long_query)

      assert Enum.any?(result.reasons, fn r -> String.contains?(r, "long query") end)
    end

    test "identifies multiple questions" do
      result = QueryClassifier.analyze("What is X? How does Y work? Why Z?")

      assert Enum.any?(result.reasons, fn r -> String.contains?(r, "multiple questions") end)
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles empty string" do
      refute QueryClassifier.should_use_cot?("")
    end

    test "handles whitespace only" do
      refute QueryClassifier.should_use_cot?("   ")
    end

    test "handles mixed case" do
      assert QueryClassifier.should_use_cot?("HOW DO I DEBUG THIS?")
      refute QueryClassifier.should_use_cot?("HELLO")
    end

    test "handles queries with extra whitespace" do
      assert QueryClassifier.should_use_cot?("  How do I debug this?  ")
      refute QueryClassifier.should_use_cot?("  hello  ")
    end

    test "handles unicode" do
      refute QueryClassifier.should_use_cot?("你好")
      assert QueryClassifier.should_use_cot?("How do I handle unicode strings?")
    end
  end

  # ============================================================================
  # Accuracy Test
  # ============================================================================

  describe "classification accuracy" do
    test "achieves 90%+ accuracy on complex queries" do
      correct =
        Enum.count(@complex_queries, fn query ->
          QueryClassifier.should_use_cot?(query)
        end)

      total = length(@complex_queries)
      accuracy = correct / total * 100

      assert accuracy >= 90,
             "Complex query accuracy: #{Float.round(accuracy, 1)}% (#{correct}/#{total}). " <>
               "Expected >= 90%"
    end

    test "achieves 90%+ accuracy on simple queries" do
      correct =
        Enum.count(@simple_queries, fn query ->
          not QueryClassifier.should_use_cot?(query)
        end)

      total = length(@simple_queries)
      accuracy = correct / total * 100

      assert accuracy >= 90,
             "Simple query accuracy: #{Float.round(accuracy, 1)}% (#{correct}/#{total}). " <>
               "Expected >= 90%"
    end

    test "achieves 90%+ overall accuracy" do
      complex_correct =
        Enum.count(@complex_queries, fn query ->
          QueryClassifier.should_use_cot?(query)
        end)

      simple_correct =
        Enum.count(@simple_queries, fn query ->
          not QueryClassifier.should_use_cot?(query)
        end)

      total_correct = complex_correct + simple_correct
      total = length(@complex_queries) + length(@simple_queries)
      accuracy = total_correct / total * 100

      assert accuracy >= 90,
             "Overall accuracy: #{Float.round(accuracy, 1)}% (#{total_correct}/#{total}). " <>
               "Expected >= 90%"
    end
  end

  # ============================================================================
  # Specific Keyword Tests
  # ============================================================================

  describe "specific complexity keywords" do
    test "detects debugging keywords" do
      assert QueryClassifier.should_use_cot?("debug this")
      assert QueryClassifier.should_use_cot?("fix this bug")
      assert QueryClassifier.should_use_cot?("troubleshoot the issue")
    end

    test "detects explanation keywords" do
      assert QueryClassifier.should_use_cot?("explain this")
      assert QueryClassifier.should_use_cot?("how does this work")
      assert QueryClassifier.should_use_cot?("why does this happen")
    end

    test "detects implementation keywords" do
      assert QueryClassifier.should_use_cot?("implement a cache")
      assert QueryClassifier.should_use_cot?("create a new module")
      assert QueryClassifier.should_use_cot?("build an API")
    end

    test "detects comparison keywords" do
      assert QueryClassifier.should_use_cot?("compare these approaches")
      assert QueryClassifier.should_use_cot?("difference between X and Y")
      assert QueryClassifier.should_use_cot?("GenServer vs Agent")
    end

    test "detects optimization keywords" do
      assert QueryClassifier.should_use_cot?("optimize this function")
      assert QueryClassifier.should_use_cot?("improve performance")
      assert QueryClassifier.should_use_cot?("refactor this code")
    end
  end
end
