defmodule Kaizen.Examples.TravelingSalesman do
  @moduledoc """
  Traveling Salesman Problem (TSP): Find the shortest route visiting all cities.

  ## Problem Description

  Given a list of cities with x,y coordinates, find the shortest route that
  visits each city exactly once and returns to the starting city.

  This is an NP-hard problem that demonstrates:
  - **Permutation genomes**: Order of cities matters
  - **Specialized operators**: PMX crossover preserves valid permutations
  - **Local optima**: GAs can escape local minima through crossover

  ## Genome Representation

  Permutation of city indices:

      [0, 3, 1, 4, 2]  # Visit cities in order: 0 -> 3 -> 1 -> 4 -> 2 -> 0

  ## Fitness Evaluation

  Fitness = -total_distance (negative so shorter is better)

  ## Usage

      iex> Kaizen.Examples.TravelingSalesman.run()
      # Evolution progress shown...
      # Converges to near-optimal route

  ## Expected Results

  Converges to within 5-10% of optimal in 100-300 generations,
  demonstrating how PMX crossover combines good route segments.
  """

  alias Kaizen.Examples.Utils

  @cities [
    %{name: "A", x: 0.0, y: 0.0},
    %{name: "B", x: 1.0, y: 3.0},
    %{name: "C", x: 4.0, y: 1.0},
    %{name: "D", x: 6.0, y: 2.0},
    %{name: "E", x: 5.0, y: 5.0},
    %{name: "F", x: 2.0, y: 6.0},
    %{name: "G", x: 1.0, y: 4.0},
    %{name: "H", x: 3.0, y: 0.0},
    %{name: "I", x: 7.0, y: 4.0},
    %{name: "J", x: 5.0, y: 1.0}
  ]

  use Kaizen.Fitness

  @impl true
  def evaluate(permutation, context) do
    distance = calculate_distance(permutation, context.dist_matrix)
    {:ok, -distance}
  end

  @impl true
  def batch_evaluate(permutations, context) do
    results =
      Enum.map(permutations, fn perm ->
        {:ok, score} = evaluate(perm, context)
        {perm, score}
      end)

    {:ok, results}
  end

  def run(opts \\ []) do
    population_size = Keyword.get(opts, :population_size, 100)
    generations = Keyword.get(opts, :generations, 200)
    verbose = Keyword.get(opts, :verbose, true)
    print_every = Keyword.get(opts, :print_every, 10)

    cities = Keyword.get(opts, :cities, @cities)
    n = length(cities)

    # Precompute distance matrix
    dist_matrix = build_distance_matrix(cities)

    # Random permutation seeds
    initial_population =
      Enum.map(1..population_size, fn _ ->
        Utils.random_permutation(n)
      end)

    context = %{
      dist_matrix: dist_matrix,
      cities: cities
    }

    if verbose do
      Utils.print_header("Traveling Salesman Problem Demo", [
        {"Cities", n},
        {"Population Size", population_size},
        {"Generations", generations}
      ])
    end

    {:ok, config} =
      Kaizen.Config.new(
        population_size: population_size,
        generations: generations,
        mutation_rate: 0.25,
        crossover_rate: 0.9,
        elitism_rate: 0.02,
        selection_strategy: Kaizen.Selection.Tournament,
        mutation_strategy: Kaizen.Mutation.Permutation,
        crossover_strategy: Kaizen.Crossover.PMX,
        termination_criteria: []
      )

    result =
      try do
        Kaizen.evolve(
          initial_population: initial_population,
          config: config,
          fitness: __MODULE__,
          evolvable: Kaizen.Evolvable.List,
          context: context
        )
        |> Stream.with_index()
        |> Stream.map(fn {state, _generation} ->
          if verbose and Utils.should_log?(state.generation, print_every) do
            print_generation(state, cities)
          end

          state
        end)
        |> Stream.take(generations + 1)
        |> Enum.to_list()
        |> List.last()
      catch
        kind, error ->
          if verbose do
            IO.puts("\nError during evolution: #{inspect(kind)} - #{inspect(error)}")
          end

          nil
      end

    if result && verbose do
      print_final_solution(result, cities, dist_matrix)
    end

    result
  end

  def demo, do: run(verbose: true)

  defp build_distance_matrix(cities) do
    n = length(cities)

    for i <- 0..(n - 1), j <- 0..(n - 1), into: %{} do
      city_i = Enum.at(cities, i)
      city_j = Enum.at(cities, j)
      distance = euclidean_distance(city_i, city_j)
      {{i, j}, distance}
    end
  end

  defp euclidean_distance(city1, city2) do
    dx = city1.x - city2.x
    dy = city1.y - city2.y
    :math.sqrt(dx * dx + dy * dy)
  end

  defp calculate_distance(permutation, dist_matrix) do
    permutation
    |> Enum.chunk_every(2, 1, [Enum.at(permutation, 0)])
    |> Enum.reduce(0.0, fn [i, j], acc ->
      acc + Map.get(dist_matrix, {i, j}, 0.0)
    end)
  end

  defp print_generation(state, cities) do
    distance = -state.best_score

    route_preview =
      state.best_entity
      |> Enum.take(5)
      |> Enum.map(fn idx -> Enum.at(cities, idx).name end)
      |> Enum.join(" -> ")

    IO.puts(
      "Gen #{String.pad_leading(to_string(state.generation), 3)}: " <>
        "Distance=#{Float.round(distance, 2)} " <>
        "Route: #{route_preview}..."
    )
  end

  defp print_final_solution(state, cities, dist_matrix) do
    distance = calculate_distance(state.best_entity, dist_matrix)

    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("Final Solution (Generation #{state.generation})")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Total Distance: #{Float.round(distance, 2)}")
    IO.puts("\nRoute:")

    route_names =
      state.best_entity
      |> Enum.map(fn idx -> Enum.at(cities, idx).name end)
      |> Enum.join(" -> ")

    IO.puts("  #{route_names} -> #{Enum.at(cities, Enum.at(state.best_entity, 0)).name}")
    IO.puts("")
  end
end
