defmodule Kaizen.Mutation.Random do
  @moduledoc """
  Random mutation strategy for any evolvable entity.

  Applies random mutations to the genome representation of entities.
  """

  @behaviour Kaizen.Mutation

  @doc """
  Apply random mutations to an entity.

  The mutation works on the genome representation and supports:
  - Character replacement (for strings/charlists)
  - Insertion of random elements
  - Deletion of elements

  ## Options

  - `:rate` - Mutation rate (0.0 to 1.0), default: 0.1
  - `:strength` - Mutation strength (0.0 to 1.0), default: 0.5
  - `:operations` - List of allowed operations (default: [:replace, :insert, :delete])

  ## Examples

      iex> {:ok, mutated} = Kaizen.Mutation.Random.mutate("hello", rate: 0.5)
      iex> is_binary(mutated)
      true
  """
  def mutate(entity, opts \\ []) do
    rate = Keyword.get(opts, :rate, 0.1)
    strength = Keyword.get(opts, :strength, 0.5)
    operations = Keyword.get(opts, :operations, [:replace, :insert, :delete])

    # Convert to genome
    genome = Kaizen.Evolvable.to_genome(entity)

    # Apply mutations
    mutated_genome = apply_mutations(genome, rate, strength, operations)

    # Convert back to entity
    mutated_entity = Kaizen.Evolvable.from_genome(entity, mutated_genome)

    {:ok, mutated_entity}
  rescue
    error -> {:error, error}
  end

  # Private functions

  defp apply_mutations(genome, rate, _strength, operations) when is_list(genome) do
    genome
    |> Enum.with_index()
    |> Enum.reduce(genome, fn {_element, index}, acc ->
      if :rand.uniform() < rate do
        operation = Enum.random(operations)
        apply_mutation_operation(acc, operation, index)
      else
        acc
      end
    end)
    |> maybe_apply_insertions(rate, operations)
  end

  defp apply_mutation_operation(genome, :replace, index) when index < length(genome) do
    case Enum.at(genome, index) do
      char when is_integer(char) and char >= 32 and char <= 126 ->
        # Replace with random printable ASCII character
        new_char = Enum.random(32..126)
        List.replace_at(genome, index, new_char)

      _ ->
        genome
    end
  end

  defp apply_mutation_operation(genome, :delete, index)
       when index < length(genome) and length(genome) > 1 do
    List.delete_at(genome, index)
  end

  defp apply_mutation_operation(genome, :insert, index) when index <= length(genome) do
    # Insert random printable ASCII character
    new_char = Enum.random(32..126)
    List.insert_at(genome, index, new_char)
  end

  defp apply_mutation_operation(genome, _operation, _index), do: genome

  defp maybe_apply_insertions(genome, rate, operations) do
    if :insert in operations and :rand.uniform() < rate do
      # Random insertion at random position
      position = :rand.uniform(length(genome) + 1) - 1
      new_char = Enum.random(32..126)
      List.insert_at(genome, position, new_char)
    else
      genome
    end
  end
end
