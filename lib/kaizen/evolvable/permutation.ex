defmodule Kaizen.Evolvable.Permutation do
  @moduledoc """
  Helper functions for working with permutation genomes.

  A permutation is a list of unique integers from 0 to n-1.
  Used for problems like the Traveling Salesman Problem (TSP)
  where the order of elements matters and no duplicates are allowed.

  Note: Permutations use the existing Kaizen.Evolvable.List protocol implementation.
  This module provides validation and creation utilities specific to permutations.
  """

  @doc """
  Validates that a list is a valid permutation.

  Returns true if:
  - All elements are unique
  - All elements are integers from 0 to n-1
  """
  def valid?(permutation) when is_list(permutation) do
    n = length(permutation)
    sorted = Enum.sort(permutation)
    expected = Enum.to_list(0..(n - 1))
    sorted == expected
  end

  @doc """
  Creates a new random permutation of length n.
  """
  def new(n) when is_integer(n) and n > 0 do
    Enum.shuffle(0..(n - 1))
  end

  def new(_), do: {:error, "Permutation size must be a positive integer"}
end
