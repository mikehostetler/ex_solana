defmodule Kaizen.Mutation.Permutation do
  @moduledoc """
  Mutation strategies for permutation genomes.

  Supports three mutation modes:
  - `:swap` - Swap two random positions
  - `:inversion` - Reverse a random segment
  - `:insertion` - Remove an element and insert it elsewhere

  ## Options

  - `:mode` - Mutation mode (default: `:swap`)
  - `:rate` - Mutation rate (default: from config)

  ## Examples

      # Swap mutation
      mutate([0, 1, 2, 3, 4], 1.0, mode: :swap)
      # => [0, 3, 2, 1, 4]

      # Inversion mutation
      mutate([0, 1, 2, 3, 4], 1.0, mode: :inversion)
      # => [0, 3, 2, 1, 4]

      # Insertion mutation
      mutate([0, 1, 2, 3, 4], 1.0, mode: :insertion)
      # => [0, 1, 3, 4, 2]
  """

  use Kaizen.Mutation

  @impl true
  def mutate(permutation, opts) when is_list(permutation) do
    rate = Keyword.get(opts, :rate, 0.1)
    mode = Keyword.get(opts, :mode, :swap)

    if :rand.uniform() < rate do
      case mode do
        :swap -> swap(permutation)
        :inversion -> inversion(permutation)
        :insertion -> insertion(permutation)
        _ -> {:error, "Unknown mutation mode: #{mode}"}
      end
    else
      {:ok, permutation}
    end
  end

  def mutate(_genome, _opts) do
    {:error, "Permutation mutation requires list genome"}
  end

  # Swap two random positions
  defp swap(permutation) do
    n = length(permutation)

    if n < 2 do
      {:ok, permutation}
    else
      i = :rand.uniform(n) - 1
      j = :rand.uniform(n) - 1

      if i == j do
        {:ok, permutation}
      else
        list = List.replace_at(permutation, i, Enum.at(permutation, j))
        list = List.replace_at(list, j, Enum.at(permutation, i))
        {:ok, list}
      end
    end
  end

  # Reverse a random segment
  defp inversion(permutation) do
    n = length(permutation)

    if n < 2 do
      {:ok, permutation}
    else
      i = :rand.uniform(n) - 1
      j = :rand.uniform(n) - 1
      {start_idx, end_idx} = if i <= j, do: {i, j}, else: {j, i}

      if start_idx == end_idx do
        {:ok, permutation}
      else
        before = Enum.slice(permutation, 0..(start_idx - 1))
        segment = Enum.slice(permutation, start_idx..end_idx) |> Enum.reverse()
        after_segment = Enum.slice(permutation, (end_idx + 1)..(n - 1))

        {:ok, before ++ segment ++ after_segment}
      end
    end
  end

  # Remove an element and insert it elsewhere
  defp insertion(permutation) do
    n = length(permutation)

    if n < 2 do
      {:ok, permutation}
    else
      from_idx = :rand.uniform(n) - 1
      to_idx = :rand.uniform(n) - 1

      if from_idx == to_idx do
        {:ok, permutation}
      else
        value = Enum.at(permutation, from_idx)
        without = List.delete_at(permutation, from_idx)
        result = List.insert_at(without, to_idx, value)
        {:ok, result}
      end
    end
  end
end
