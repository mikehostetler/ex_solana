defimpl Kaizen.Evolvable, for: List do
  @moduledoc """
  Implementation of Kaizen.Evolvable for lists.

  Lists are already genomes, so to_genome/from_genome are identity operations.
  Similarity is calculated using Hamming distance for equal-length lists.
  """

  @doc """
  Convert list to genome (identity operation).
  """
  def to_genome(list) when is_list(list) do
    list
  end

  @doc """
  Convert genome back to list (identity operation).
  """
  def from_genome(_original, genome) when is_list(genome) do
    genome
  end

  @doc """
  Calculate similarity using normalized Hamming distance.

  Returns 0.0 for identical lists, 1.0 for completely different lists.
  Only works for equal-length lists.
  """
  def similarity(list1, list2) when is_list(list1) and is_list(list2) do
    if length(list1) != length(list2) do
      1.0
    else
      differences =
        Enum.zip(list1, list2)
        |> Enum.count(fn {a, b} -> a != b end)

      differences / length(list1)
    end
  end
end
