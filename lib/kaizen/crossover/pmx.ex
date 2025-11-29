defmodule Kaizen.Crossover.PMX do
  @moduledoc """
  Partially Mapped Crossover (PMX) for permutations.

  PMX preserves permutation validity by mapping conflicting values
  when copying segments between parents.

  ## Algorithm

  1. Select two random crossover points
  2. Copy the segment from parent1 to child
  3. For remaining positions, use mapping from parent2
  4. If value conflicts, follow the mapping chain

  ## Example

      parent1 = [0, 1, 2, 3, 4, 5, 6, 7, 8]
      parent2 = [1, 2, 3, 5, 4, 6, 8, 7, 0]
      
      # Cut points at 3 and 6
      child   = [_, _, _, 3, 4, 5, _, _, _]
      
      # Fill remaining using mapping
      child   = [0, 1, 2, 3, 4, 5, 6, 7, 8]
  """

  @behaviour Kaizen.Crossover

  @impl true
  def crossover(parent1, parent2, _config) when is_list(parent1) and is_list(parent2) do
    n = length(parent1)

    if n != length(parent2) or n < 2 do
      # Return parents unchanged if invalid
      {parent1, parent2}
    else
      # Select two random crossover points (ensure cut2 > cut1)
      point1 = :rand.uniform(n) - 1
      point2 = :rand.uniform(n - 1) - 1
      point2 = if point2 >= point1, do: point2 + 1, else: point2
      {cut1, cut2} = if point1 < point2, do: {point1, point2}, else: {point2, point1}

      # Copy segment from parent1 to child
      segment = Enum.slice(parent1, cut1, cut2 - cut1)

      # Create mapping from parent2's segment to parent1's segment
      parent2_segment = Enum.slice(parent2, cut1, cut2 - cut1)
      mapping = Enum.zip(parent2_segment, segment) |> Map.new()

      # Fill child: segment positions get parent1 values, rest get mapped parent2 values
      child =
        Enum.with_index(parent2)
        |> Enum.map(fn {value, idx} ->
          cond do
            idx >= cut1 and idx < cut2 ->
              # Inside segment: use parent1 value
              Enum.at(parent1, idx)

            true ->
              # Outside segment: use parent2 value, mapped if needed
              map_value(value, mapping, segment)
          end
        end)

      # PMX returns single child; return child with swapped parent as second child
      {child, parent2}
    end
  end

  def crossover(parent1, parent2, _config) do
    # Invalid types - return parents unchanged
    {parent1, parent2}
  end

  # Recursively map a value if it exists in the segment
  # Add a visited set to prevent infinite loops
  defp map_value(value, mapping, segment) do
    map_value(value, mapping, segment, MapSet.new())
  end

  defp map_value(value, mapping, segment, visited) do
    if value in segment do
      if MapSet.member?(visited, value) do
        # Cycle detected, return value as-is
        value
      else
        # Value is in segment, follow mapping
        mapped = Map.get(mapping, value, value)
        map_value(mapped, mapping, segment, MapSet.put(visited, value))
      end
    else
      value
    end
  end
end
