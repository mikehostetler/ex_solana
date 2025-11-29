defmodule Kaizen.Mutation.Text do
  @moduledoc """
  Text-specific mutation strategy that works directly with strings.

  This mutation strategy is designed specifically for text/string evolution
  and provides efficient mutations for string data.
  """

  @behaviour Kaizen.Mutation

  @alphabet String.to_charlist("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ ,!?")

  @doc """
  Apply random mutations to a string entity.

  ## Options

  - `:rate` - Mutation rate (0.0 to 1.0), default: 0.1
  - `:strength` - Mutation strength (0.0 to 1.0), default: 0.5
  - `:operations` - List of allowed operations (default: [:replace])

  ## Examples

      iex> {:ok, mutated} = Kaizen.Mutation.Text.mutate("hello", rate: 0.5)
      iex> is_binary(mutated)
      true
  """
  def mutate(entity, opts \\ [])

  def mutate(entity, opts) when is_binary(entity) do
    rate = Keyword.get(opts, :rate, 0.1)
    _strength = Keyword.get(opts, :strength, 0.5)
    operations = Keyword.get(opts, :operations, [:replace])

    # Convert to charlist for easier manipulation
    chars = String.to_charlist(entity)

    # Apply mutations
    mutated_chars = apply_mutations(chars, rate, operations)

    # Convert back to string
    mutated_entity = List.to_string(mutated_chars)

    {:ok, mutated_entity}
  rescue
    error -> {:error, error}
  end

  # Handle non-string entities
  def mutate(entity, _opts) do
    {:error, "Text mutation only works with string entities, got: #{inspect(entity)}"}
  end

  @doc """
  Calculate mutation strength based on generation number.
  Returns a value between 0.0 and 1.0.
  """
  def mutation_strength(generation) do
    # Start with high mutation strength, decrease over time
    max(0.1, 1.0 - generation / 1000.0)
  end

  # Private functions

  defp apply_mutations(chars, rate, operations) when is_list(chars) do
    chars
    |> Enum.with_index()
    |> Enum.reduce(chars, fn {_char, index}, acc ->
      if :rand.uniform() < rate do
        operation = Enum.random(operations)
        apply_mutation_operation(acc, operation, index)
      else
        acc
      end
    end)
    |> maybe_apply_insertions(rate, operations)
  end

  defp apply_mutation_operation(chars, :replace, index) when index < length(chars) do
    case Enum.at(chars, index) do
      char when is_integer(char) ->
        # Replace with random character from alphabet
        new_char = Enum.random(@alphabet)
        List.replace_at(chars, index, new_char)

      _ ->
        chars
    end
  end

  defp apply_mutation_operation(chars, :delete, index)
       when index < length(chars) and length(chars) > 1 do
    List.delete_at(chars, index)
  end

  defp apply_mutation_operation(chars, :insert, index) when index <= length(chars) do
    # Insert random printable ASCII character
    new_char = Enum.random(32..126)
    List.insert_at(chars, index, new_char)
  end

  defp apply_mutation_operation(chars, _operation, _index), do: chars

  defp maybe_apply_insertions(chars, rate, operations) do
    if :insert in operations and :rand.uniform() < rate do
      # Random insertion at random position
      position = :rand.uniform(length(chars) + 1) - 1
      new_char = Enum.random(32..126)
      List.insert_at(chars, position, new_char)
    else
      chars
    end
  end
end
