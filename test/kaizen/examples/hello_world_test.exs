defmodule Kaizen.Examples.HelloWorldTest do
  use ExUnit.Case
  doctest Kaizen.Examples.HelloWorld

  test "fitness function evaluates strings correctly" do
    # Perfect match should have high fitness
    {:ok, score} = Kaizen.Examples.HelloWorld.evaluate("Hello, world!", %{})
    assert score == 1.0

    # Similar string should have good fitness
    {:ok, score} = Kaizen.Examples.HelloWorld.evaluate("Hello, world", %{})
    assert score > 0.8

    # Very different string should have low fitness
    {:ok, score} = Kaizen.Examples.HelloWorld.evaluate("xyz", %{})
    assert score < 0.5
  end

  test "run method returns expected structure" do
    result =
      Kaizen.Examples.HelloWorld.run(
        population_size: 20,
        generations: 5,
        verbose: false
      )

    assert Map.has_key?(result, :best_entity)
    assert Map.has_key?(result, :best_score)
    assert Map.has_key?(result, :generation)
    assert Map.has_key?(result, :target)
    assert Map.has_key?(result, :success)
    assert result.target == "Hello, world!"
  end

  test "evolution can make progress" do
    # Run a longer evolution to see if it improves
    result =
      Kaizen.Examples.HelloWorld.run(
        population_size: 50,
        generations: 20,
        mutation_rate: 0.5,
        # Start with something far from target
        seed: ["abc"],
        verbose: false
      )

    # Should make some progress (though may not reach target)
    assert result.best_score > 0.0
    assert result.generation > 0
  end
end
