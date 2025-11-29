defmodule Kaizen.Crossover.Uniform do
  @moduledoc """
  Uniform crossover implementation for lists.

  Each element has a 50% chance of coming from either parent.
  This is ideal for binary/list genomes where order doesn't matter much.
  """

  @behaviour Kaizen.Crossover

  @impl true
  def crossover(parent1, parent2, _config)
      when is_list(parent1) and is_list(parent2) do
    if length(parent1) != length(parent2) do
      {parent1, parent2}
    else
      {child1, child2} =
        Enum.zip(parent1, parent2)
        |> Enum.reduce({[], []}, fn {gene1, gene2}, {c1, c2} ->
          if :rand.uniform() < 0.5 do
            {[gene1 | c1], [gene2 | c2]}
          else
            {[gene2 | c1], [gene1 | c2]}
          end
        end)

      {Enum.reverse(child1), Enum.reverse(child2)}
    end
  end
end
