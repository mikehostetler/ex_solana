defmodule Kaizen.Mutation.AdaptiveText do
  @moduledoc """
  Adaptive text mutation strategy that adjusts mutation rate based on fitness.

  Uses high mutation rate early for exploration, then lowers it as fitness
  improves for fine-tuning convergence.
  """

  @behaviour Kaizen.Mutation

  @doc """
  Apply adaptive mutation to a string entity.

  ## Options

  - `:rate` - Base mutation rate (adjusted based on fitness context)
  - `:strength` - Mutation strength (0.0 to 1.0), default: 0.5
  - `:operations` - List of allowed operations (default: [:replace])
  - `:high_rate` - High mutation rate for early exploration (default: 0.4)
  - `:low_rate` - Low mutation rate for convergence (default: 0.08)
  - `:fitness_threshold` - Switch to low rate when best fitness exceeds this (default: 0.8)
  - `:best_fitness` - Current best fitness (from context, required for adaptation)
  """
  def mutate(entity, opts \\ [])

  def mutate(entity, opts) when is_binary(entity) do
    high_rate = Keyword.get(opts, :high_rate, 0.3)
    low_rate = Keyword.get(opts, :low_rate, 0.08)
    fitness_threshold = Keyword.get(opts, :fitness_threshold, 0.75)
    best_fitness = Keyword.get(opts, :best_fitness, 0.0)
    operations = Keyword.get(opts, :operations, [:replace])

    # Adapt mutation rate based on fitness
    adaptive_rate =
      if best_fitness >= fitness_threshold do
        low_rate
      else
        high_rate
      end

    # Delegate to Text mutation with adaptive rate
    Kaizen.Mutation.Text.mutate(entity,
      rate: adaptive_rate,
      operations: operations
    )
  end

  def mutate(entity, _opts) do
    {:error, "Adaptive text mutation only works with string entities, got: #{inspect(entity)}"}
  end

  @doc """
  Calculate mutation strength based on generation number.
  """
  def mutation_strength(generation) do
    max(0.1, 1.0 - generation / 1000.0)
  end
end
