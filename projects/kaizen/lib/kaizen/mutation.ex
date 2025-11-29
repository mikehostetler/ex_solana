defmodule Kaizen.Mutation do
  @moduledoc """
  Behaviour for mutation strategies.

  Mutation introduces variation into the population by
  modifying entities in various ways.
  """

  @type entity :: term()
  @type opts :: keyword()
  @type feedback :: map()

  @doc """
  Mutate an entity.

  The mutation should introduce variation while preserving
  the general structure of the entity.

  ## Options

  - `:rate` - Mutation rate (0.0 to 1.0), defaults to 0.1
  - `:strength` - Mutation strength (0.0 to 1.0), defaults to 0.5

  ## Examples

      def mutate(entity, opts) do
        rate = Keyword.get(opts, :rate, 0.1)
        # Apply mutations based on rate
        {:ok, mutated_entity}
      end
  """
  @callback mutate(entity(), opts()) ::
              {:ok, entity()} | {:error, term()}

  @doc """
  Mutate an entity with feedback from previous evaluations.

  This allows for more intelligent mutations that take into
  account what has worked well in the past.
  """
  @callback mutate_with_feedback(entity(), feedback(), opts()) ::
              {:ok, entity()} | {:error, term()}

  @optional_callbacks [mutate_with_feedback: 3]

  @doc """
  Calculate mutation strength based on generation number.

  This allows for adaptive mutation rates that change over time,
  typically starting high for exploration and decreasing for exploitation.
  """
  @callback mutation_strength(integer()) :: float()

  @optional_callbacks [mutation_strength: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Kaizen.Mutation

      @doc """
      Default implementation of mutate_with_feedback/3 that ignores feedback.
      """
      def mutate_with_feedback(entity, _feedback, opts) do
        mutate(entity, opts)
      end

      @doc """
      Default mutation strength that decreases linearly with generation.
      """
      def mutation_strength(generation) when generation <= 0, do: 1.0

      def mutation_strength(generation) do
        max(0.1, 1.0 - generation / 1000.0)
      end

      defoverridable mutate_with_feedback: 3, mutation_strength: 1
    end
  end
end
