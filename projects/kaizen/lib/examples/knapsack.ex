defmodule Kaizen.Examples.Knapsack do
  @moduledoc """
  Knapsack Problem: Select items to maximize value without exceeding weight capacity.

  ## Problem Description

  You have a knapsack with limited weight capacity and a collection of items,
  each with a weight and value. The goal is to select items that maximize total
  value without exceeding the weight limit.

  This demonstrates why genetic algorithms excel:
  - **Building blocks**: Good item combinations can be inherited
  - **Crossover value**: Mixing two good solutions often produces better offspring
  - **Selection pressure**: Invalid solutions (too heavy) are penalized

  ## Genome Representation

  Binary vector where 1 = item included, 0 = item excluded:

      [1, 0, 1, 1, 0, 1]  # Items 0, 2, 3, 5 selected

  ## Fitness Evaluation

  - If weight ≤ capacity: fitness = total value
  - If weight > capacity: fitness = total value - penalty * overage

  ## Usage

      iex> Kaizen.Examples.Knapsack.run()
      # Evolution progress shown...
      # Final solution near optimal value

  ## Expected Results

  Converges to near-optimal solution in 50-100 generations, demonstrating
  how crossover combines good item selections from different parents.
  """

  @items [
    %{name: "Laptop", weight: 4, value: 2000},
    %{name: "Camera", weight: 3, value: 1500},
    %{name: "Phone", weight: 2, value: 1000},
    %{name: "Tablet", weight: 3, value: 900},
    %{name: "Headphones", weight: 1, value: 400},
    %{name: "Charger", weight: 1, value: 150},
    %{name: "Book", weight: 2, value: 100},
    %{name: "Sunglasses", weight: 1, value: 250},
    %{name: "Watch", weight: 2, value: 600},
    %{name: "Shoes", weight: 3, value: 850},
    %{name: "Jacket", weight: 4, value: 1100},
    %{name: "Umbrella", weight: 2, value: 200},
    %{name: "Water Bottle", weight: 1, value: 180},
    %{name: "Snacks", weight: 1, value: 220},
    %{name: "Power Bank", weight: 1, value: 350}
  ]

  @capacity 15
  @penalty_multiplier 1000

  use Kaizen.Fitness

  @impl true
  def evaluate(genome, context) do
    items = context.items
    capacity = context.capacity
    penalty_multiplier = context.penalty_multiplier

    {total_weight, total_value} =
      genome
      |> Enum.with_index()
      |> Enum.reduce({0, 0}, fn {selected, idx}, {weight, value} ->
        if selected == 1 do
          item = Enum.at(items, idx)
          {weight + item.weight, value + item.value}
        else
          {weight, value}
        end
      end)

    overage = max(0, total_weight - capacity)
    penalty = penalty_multiplier * overage
    score = total_value - penalty

    {:ok, score}
  end

  @impl true
  def batch_evaluate(genomes, context) do
    results =
      Enum.map(genomes, fn genome ->
        {:ok, score} = evaluate(genome, context)
        {genome, score}
      end)

    {:ok, results}
  end

  def run(opts \\ []) do
    population_size = Keyword.get(opts, :population_size, 50)
    generations = Keyword.get(opts, :generations, 100)
    verbose = Keyword.get(opts, :verbose, true)

    # Random binary genomes matching item count
    initial_population =
      Enum.map(1..population_size, fn _ ->
        Enum.map(@items, fn _ -> Enum.random([0, 1]) end)
      end)

    context = %{
      items: @items,
      capacity: @capacity,
      penalty_multiplier: @penalty_multiplier
    }

    optimal = calculate_optimal_value()

    if verbose do
      IO.puts("\nKnapsack Problem Demo")
      IO.puts("=" |> String.duplicate(50))
      IO.puts("Items: #{length(@items)}")
      IO.puts("Capacity: #{@capacity}kg")
      IO.puts("Optimal value: $#{optimal}  (brute force calculation)\n")
    end

    {:ok, config} =
      Kaizen.Config.new(
        population_size: population_size,
        generations: generations,
        mutation_rate: 0.15,
        crossover_rate: 0.65,
        elitism_rate: 0.02,
        selection_strategy: Kaizen.Selection.Tournament,
        mutation_strategy: Kaizen.Mutation.Binary,
        crossover_strategy: Kaizen.Crossover.Uniform,
        termination_criteria: [target_fitness: optimal]
      )

    result =
      Kaizen.evolve(
        initial_population: initial_population,
        config: config,
        fitness: __MODULE__,
        evolvable: Kaizen.Evolvable.List,
        context: context
      )
      |> Stream.with_index()
      |> Stream.map(fn {state, _generation} ->
        if verbose do
          print_generation(state)
        end

        state
      end)
      |> Stream.take_while(fn state ->
        state.best_score < optimal and state.generation < generations
      end)
      |> Enum.to_list()
      |> List.last()

    if result && verbose do
      print_final_solution(result)
    end

    result
  end

  defp print_generation(state) do
    {weight, value, items} = decode_solution(state.best_entity)
    valid = if weight <= @capacity, do: "[OK]", else: "[OVERWEIGHT]"

    IO.puts(
      "Gen #{String.pad_leading(to_string(state.generation), 3)}: " <>
        "Value=$#{String.pad_leading(to_string(value), 4)} " <>
        "Weight=#{String.pad_leading(to_string(weight), 2)}kg " <>
        "Items=#{length(items)} #{valid}"
    )
  end

  defp print_final_solution(state) do
    {weight, value, items} = decode_solution(state.best_entity)

    IO.puts("\n" <> ("=" |> String.duplicate(50)))
    IO.puts("Final Solution (Generation #{state.generation})")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Total Value: $#{value}")
    IO.puts("Total Weight: #{weight}kg / #{@capacity}kg")
    IO.puts("\nSelected Items:")

    Enum.each(items, fn item ->
      IO.puts("  - #{item.name}: #{item.weight}kg, $#{item.value}")
    end)

    IO.puts("")
  end

  defp decode_solution(genome) do
    {weight, value, items} =
      genome
      |> Enum.with_index()
      |> Enum.reduce({0, 0, []}, fn {selected, idx}, {w, v, items} ->
        if selected == 1 do
          item = Enum.at(@items, idx)
          {w + item.weight, v + item.value, [item | items]}
        else
          {w, v, items}
        end
      end)

    {weight, value, Enum.reverse(items)}
  end

  defp calculate_optimal_value do
    # Brute force for small problem (2^10 = 1024 combinations)
    0..(Integer.pow(2, length(@items)) - 1)
    |> Enum.map(fn combination ->
      genome =
        0..(length(@items) - 1)
        |> Enum.map(fn idx ->
          if Bitwise.band(combination, Bitwise.bsl(1, idx)) > 0, do: 1, else: 0
        end)

      {weight, value, _} = decode_solution(genome)
      if weight <= @capacity, do: value, else: 0
    end)
    |> Enum.max()
  end
end
