defmodule Kaizen.Crossover.String do
  @moduledoc """
  Single-point crossover implementation for strings.

  Performs crossover by selecting a random point and swapping
  the portions after that point between the two parent strings.
  """

  @behaviour Kaizen.Crossover

  @impl true
  def crossover(parent1, parent2, _config) when is_binary(parent1) and is_binary(parent2) do
    len1 = String.length(parent1)
    len2 = String.length(parent2)

    if len1 > 0 and len2 > 0 do
      # Choose crossover point based on shorter parent
      max_point = min(len1, len2)
      point = if max_point > 1, do: :rand.uniform(max_point - 1), else: 0

      # Create children by swapping segments after crossover point
      child1 = String.slice(parent1, 0, point) <> String.slice(parent2, point, len2)
      child2 = String.slice(parent2, 0, point) <> String.slice(parent1, point, len1)

      {child1, child2}
    else
      # If either parent is empty, return parents unchanged
      {parent1, parent2}
    end
  end
end
