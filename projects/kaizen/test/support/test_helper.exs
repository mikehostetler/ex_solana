defmodule TestFitness do
  @moduledoc """
  Deterministic fitness implementation for testing.

  Scores entities based on their string representation length.
  Supports context flags to trigger error conditions:
  - `:raise_error` - raises RuntimeError
  - `:return_error` - returns {:error, :test_error}
  """

  @behaviour Kaizen.Fitness

  @impl true
  def evaluate(entity, context \\ %{}) do
    cond do
      Map.get(context, :raise_error) ->
        raise "TestFitness error triggered"

      Map.get(context, :return_error) ->
        {:error, :test_error}

      true ->
        score = entity |> to_string() |> String.length() |> to_float()
        {:ok, score}
    end
  end

  @impl true
  def batch_evaluate(entities, context) do
    entities
    |> Enum.map(fn entity -> evaluate(entity, context) end)
    |> Enum.map(fn
      {:ok, score} -> {:ok, score}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp to_float(int) when is_integer(int), do: int * 1.0
  defp to_float(float) when is_float(float), do: float
end

defmodule TestSelection do
  @moduledoc """
  Deterministic selection implementation for testing.

  Selects top-k entities by score in descending order.
  """

  @behaviour Kaizen.Selection

  @impl true
  def select(population, scores, count, _opts) do
    population
    |> Enum.map(fn entity -> {entity, Map.get(scores, entity, 0.0)} end)
    |> Enum.sort_by(fn {_entity, score} -> score end, :desc)
    |> Enum.take(count)
    |> Enum.map(fn {entity, _score} -> entity end)
  end
end

defmodule TestMutation do
  @moduledoc """
  Deterministic mutation implementation for testing.

  Appends "_mutated" suffix to string entities or increments numeric entities.
  Context flags:
  - `:return_error` - returns {:error, :mutation_failed}
  - `:mutation_strength` - custom strength value (default: 0.5)
  """

  @behaviour Kaizen.Mutation

  @impl true
  def mutate(entity, opts \\ []) do
    if Keyword.get(opts, :return_error) do
      {:error, :mutation_failed}
    else
      mutated =
        cond do
          is_binary(entity) -> entity <> "_mutated"
          is_integer(entity) -> entity + 1
          is_float(entity) -> entity + 1.0
          is_list(entity) -> [0 | entity]
          true -> entity
        end

      {:ok, mutated}
    end
  end

  @impl true
  def mutation_strength(_generation) do
    0.5
  end
end

defmodule TestCrossover do
  @moduledoc """
  Deterministic crossover implementation for testing.

  For string entities, splits at midpoint and swaps.
  For numeric entities, averages and creates variations.
  For list entities, splits and recombines.
  """

  @behaviour Kaizen.Crossover

  @impl true
  def crossover(parent1, parent2, _config) do
    cond do
      is_binary(parent1) and is_binary(parent2) ->
        mid1 = div(String.length(parent1), 2)
        mid2 = div(String.length(parent2), 2)
        p1_first = String.slice(parent1, 0, mid1)
        p1_last = String.slice(parent1, mid1..-1//1)
        p2_first = String.slice(parent2, 0, mid2)
        p2_last = String.slice(parent2, mid2..-1//1)
        {p1_first <> p2_last, p2_first <> p1_last}

      is_integer(parent1) and is_integer(parent2) ->
        avg = div(parent1 + parent2, 2)
        {avg + 1, avg - 1}

      is_float(parent1) and is_float(parent2) ->
        avg = (parent1 + parent2) / 2.0
        {avg + 0.5, avg - 0.5}

      is_list(parent1) and is_list(parent2) ->
        mid1 = div(length(parent1), 2)
        mid2 = div(length(parent2), 2)
        {p1_first, p1_last} = Enum.split(parent1, mid1)
        {p2_first, p2_last} = Enum.split(parent2, mid2)
        {p1_first ++ p2_last, p2_first ++ p1_last}

      true ->
        {parent1, parent2}
    end
  end
end
