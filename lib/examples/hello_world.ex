defmodule Kaizen.Examples.HelloWorld do
  @moduledoc """
  A simple example of evolving text towards a target string.

  This example demonstrates how to use Kaizen to evolve a string
  towards the target "Hello, world!" using random mutations and
  tournament selection with adaptive mutation rates.
  """

  use Kaizen.Fitness

  @target "Hello, world!"

  @doc """
  Fitness function that measures similarity to the target string.

  Higher scores indicate better fitness (closer to target).
  """
  def evaluate(text, _context) do
    # Count matching characters at correct positions
    target_chars = String.graphemes(@target)
    text_chars = String.graphemes(text)

    matches =
      Enum.zip(target_chars, text_chars)
      |> Enum.count(fn {t, c} -> t == c end)

    # Normalize to 0.0-1.0
    similarity = matches / String.length(@target)
    {:ok, similarity}
  end

  def batch_evaluate(entities, context) do
    results =
      Enum.map(entities, fn entity ->
        {:ok, score} = evaluate(entity, context)
        {entity, score}
      end)

    {:ok, results}
  end

  @doc """
  Run the hello world evolution example.

  ## Options

  - `:population_size` - Size of the population (default: 100)
  - `:generations` - Maximum generations (default: 300) 
  - `:mutation_rate` - Mutation rate (default: 0.3)
  - `:crossover_rate` - Crossover rate (default: 0.8)
  - `:elitism_rate` - Elitism rate (default: 0.02)
  - `:target_fitness` - Stop when fitness reaches this value (default: 0.99)
  - `:seed` - Initial population (default: 100 random strings)
  - `:verbose` - Print progress (default: false)

  ## Examples

      # Run with defaults
      Kaizen.Examples.HelloWorld.run()
      
      # Run with custom settings
      Kaizen.Examples.HelloWorld.run(
        population_size: 50,
        mutation_rate: 0.6,
        verbose: true
      )
  """
  def run(opts \\ []) do
    population_size = Keyword.get(opts, :population_size, 100)
    generations = Keyword.get(opts, :generations, 300)
    mutation_rate = Keyword.get(opts, :mutation_rate, 0.3)
    crossover_rate = Keyword.get(opts, :crossover_rate, 0.8)
    elitism_rate = Keyword.get(opts, :elitism_rate, 0.02)
    target_fitness = Keyword.get(opts, :target_fitness, 0.99)
    seed = Keyword.get(opts, :seed, Enum.map(1..population_size, fn _ -> random_string() end))
    verbose = Keyword.get(opts, :verbose, false)

    # Create configuration with adaptive mutation
    {:ok, config} =
      Kaizen.Config.new(
        population_size: population_size,
        generations: generations,
        mutation_rate: mutation_rate,
        crossover_rate: crossover_rate,
        elitism_rate: elitism_rate,
        selection_strategy: Kaizen.Selection.Tournament,
        mutation_strategy: Kaizen.Mutation.AdaptiveText,
        crossover_strategy: Kaizen.Crossover.String,
        termination_criteria: [target_fitness: target_fitness]
      )

    if verbose do
      IO.puts("Starting evolution:")
      IO.puts("Target: #{@target}")
      IO.puts("Initial: #{Enum.join(seed, ", ")}")
      IO.puts("Population size: #{population_size}")
      IO.puts("Mutation rate: #{mutation_rate} (adaptive: 0.3 → 0.08 at fitness > 0.75)")
      IO.puts("")
    end

    # Run evolution
    result =
      Kaizen.evolve(
        initial_population: seed,
        config: config,
        fitness: __MODULE__,
        evolvable: Kaizen.Evolvable.String
      )
      |> Stream.with_index()
      |> Stream.map(fn {state, generation} ->
        if verbose and rem(generation, 10) == 0 do
          IO.puts(
            "Generation #{generation}: #{state.best_entity} (fitness: #{Float.round(state.best_score, 4)})"
          )
        end

        state
      end)
      |> Stream.take_while(fn state ->
        state.best_score < target_fitness and state.generation < generations
      end)
      |> Enum.to_list()
      |> List.last()

    if result do
      if verbose do
        IO.puts("")
        IO.puts("Evolution completed!")
        IO.puts("Final result: #{result.best_entity}")
        IO.puts("Final fitness: #{Float.round(result.best_score, 6)}")
        IO.puts("Generations: #{result.generation}")
      end

      %{
        best_entity: result.best_entity,
        best_score: result.best_score,
        generation: result.generation,
        target: @target,
        success: result.best_score >= target_fitness
      }
    else
      if verbose do
        IO.puts("Evolution failed to converge")
      end

      %{
        best_entity: nil,
        best_score: 0.0,
        generation: 0,
        target: @target,
        success: false
      }
    end
  end

  @doc """
  Run a quick demo that prints progress.
  """
  def demo do
    IO.puts("Kaizen Hello World Evolution Demo")
    IO.puts("=" |> String.duplicate(40))

    run(verbose: true)
  end

  defp random_string do
    chars = String.graphemes("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ,!?")

    1..String.length(@target)
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> Enum.join()
  end
end
