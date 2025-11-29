defmodule Kaizen.State do
  @moduledoc """
  Represents the state of an evolutionary algorithm at a given generation.

  This structure tracks the current population, their fitness scores,
  and metadata about the evolution process.
  """

  use TypedStruct

  typedstruct do
    @typedoc "State of evolutionary algorithm"

    field(:population, list(), default: [])
    field(:scores, map(), default: %{})
    field(:generation, non_neg_integer(), default: 0)
    field(:best_entity, term(), default: nil)
    field(:best_score, float(), default: 0.0)
    field(:average_score, float(), default: 0.0)
    field(:diversity, float(), default: 0.0)
    field(:fitness_history, list(), default: [])
    field(:metadata, map(), default: %{})
    field(:config, Kaizen.Config.t(), enforce: true)
  end

  @doc """
  Create a new initial state from a population and config.

  ## Examples

      iex> config = Kaizen.Config.new!()
      iex> state = Kaizen.State.new(["a", "b", "c"], config)
      iex> state.population
      ["a", "b", "c"]
  """
  @spec new(list(any()), Kaizen.Config.t()) :: t()
  def new(population, %Kaizen.Config{} = config) do
    %__MODULE__{
      population: population,
      config: config
    }
  end

  @doc """
  Update the state with new fitness scores.

  This recalculates the best entity, best score, and average score.
  """
  @spec update_scores(t(), map()) :: t()
  def update_scores(%__MODULE__{} = state, scores) when is_map(scores) do
    {best_entity, best_score} = find_best(scores)
    average_score = calculate_average(scores)

    %{
      state
      | scores: scores,
        best_entity: best_entity,
        best_score: best_score,
        average_score: average_score
    }
  end

  @doc """
  Update the population and advance the generation counter.
  """
  @spec next_generation(t(), list(any())) :: t()
  def next_generation(%__MODULE__{} = state, new_population) do
    # Update fitness history with current best score (keep last 100 generations)
    new_history = [state.best_score | state.fitness_history] |> Enum.take(100)

    %{
      state
      | population: new_population,
        generation: state.generation + 1,
        # Clear scores for new population
        scores: %{},
        best_entity: nil,
        best_score: 0.0,
        average_score: 0.0,
        fitness_history: new_history
    }
  end

  @doc """
  Calculate diversity of the current population.

  This is useful for monitoring convergence and maintaining diversity.
  """
  def calculate_diversity(%__MODULE__{population: population} = state, evolvable_module) do
    diversity = calculate_population_diversity(population, evolvable_module)
    %{state | diversity: diversity}
  end

  @doc """
  Add metadata to the state.
  """
  def put_metadata(%__MODULE__{metadata: metadata} = state, key, value) do
    %{state | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Check if termination criteria are met.
  """
  def terminated?(%__MODULE__{config: config} = state) do
    criteria = config.termination_criteria
    Enum.any?(criteria, &check_criterion(state, &1))
  end

  # Private functions

  defp find_best(scores) when map_size(scores) == 0, do: {nil, 0.0}

  defp find_best(scores) do
    Enum.max_by(scores, fn {_entity, score} -> score end)
  end

  defp calculate_average(scores) when map_size(scores) == 0, do: 0.0

  defp calculate_average(scores) do
    sum = scores |> Map.values() |> Enum.sum()
    sum / map_size(scores)
  end

  defp calculate_population_diversity(population, _evolvable_module)
       when length(population) < 2 do
    0.0
  end

  defp calculate_population_diversity(population, _evolvable_module) do
    pop_size = length(population)

    # Use sampling for large populations to avoid O(n²) complexity
    max_samples = 1000

    if pop_size < 10 do
      # For small populations, calculate all pairs
      pairs = for i <- population, j <- population, i != j, do: {i, j}

      if length(pairs) == 0 do
        0.0
      else
        total_similarity =
          pairs
          |> Enum.map(fn {a, b} -> Kaizen.Evolvable.similarity(a, b) end)
          |> Enum.sum()

        total_similarity / length(pairs)
      end
    else
      # Sample random pairs for large populations
      sample_count = min(max_samples, div(pop_size * pop_size, 10))

      sampled_similarities =
        1..sample_count
        |> Enum.map(fn _ ->
          # Pick two random different entities
          i = Enum.random(population)
          j = Enum.random(population)

          # Ensure they're different entities (retry if same)
          if i == j do
            # Pick another random entity
            candidates = population -- [i]

            if length(candidates) > 0 do
              j = Enum.random(candidates)
              Kaizen.Evolvable.similarity(i, j)
            else
              # Single entity case
              0.0
            end
          else
            Kaizen.Evolvable.similarity(i, j)
          end
        end)

      if length(sampled_similarities) == 0 do
        0.0
      else
        Enum.sum(sampled_similarities) / length(sampled_similarities)
      end
    end
  end

  defp check_criterion(state, {:max_generations, max_gen}) do
    state.generation >= max_gen
  end

  defp check_criterion(state, {:target_fitness, target}) do
    state.best_score >= target
  end

  defp check_criterion(state, {:no_improvement, generations}) do
    # Check if we have enough history to evaluate
    if length(state.fitness_history) < generations do
      false
    else
      # Get the last N generations of best scores
      recent_scores = Enum.take(state.fitness_history, generations)

      # Check if there's been improvement (variance in recent scores)
      if length(recent_scores) < 2 do
        false
      else
        # Calculate variance of recent best scores
        mean = Enum.sum(recent_scores) / length(recent_scores)

        variance =
          recent_scores
          |> Enum.map(fn score -> :math.pow(score - mean, 2) end)
          |> Enum.sum()
          |> Kernel./(length(recent_scores))

        # If variance is very small, we haven't improved
        variance < 0.0001
      end
    end
  end

  defp check_criterion(_state, _criterion), do: false
end
