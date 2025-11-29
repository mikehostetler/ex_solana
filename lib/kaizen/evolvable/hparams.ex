defmodule Kaizen.Evolvable.HParams do
  @moduledoc """
  Evolvable protocol implementation for hyperparameter maps.

  Supports schema-driven evolution of mixed-type parameters:
  - Floats with linear or log-scale bounds
  - Integers with min/max bounds
  - Enums (categorical choices)
  - Lists of values with length constraints

  ## Schema Format

      %{
        learning_rate: {:float, 1.0e-5..1.0e-1, :log},
        hidden_layers: {:list, {:int, 16..256}, length: 1..3},
        dropout_rate: {:float, 0.0..0.6, :linear},
        activation: {:enum, [:relu, :tanh, :gelu]},
        batch_size: {:enum, [16, 32, 64, 128]}
      }

  ## Usage

      schema = %{learning_rate: {:float, 0.001..0.1, :log}}
      {:ok, hparams} = Kaizen.Evolvable.HParams.new(schema)
      # => %{learning_rate: 0.0032}
  """

  @doc """
  Creates a new random hyperparameter map from a schema.
  """
  def new(schema) when is_map(schema) do
    Enum.map(schema, fn {key, spec} ->
      {key, random_value(spec)}
    end)
    |> Map.new()
  end

  def new(_), do: {:error, "HParams requires a schema map"}

  defp random_value({:float, {min, max}, :linear}) do
    min + :rand.uniform() * (max - min)
  end

  defp random_value({:float, {min, max}, :log}) do
    log_min = :math.log(min)
    log_max = :math.log(max)
    :math.exp(log_min + :rand.uniform() * (log_max - log_min))
  end

  defp random_value({:int, {min, max}}) do
    min + :rand.uniform(max - min + 1) - 1
  end

  defp random_value({:enum, choices}) when is_list(choices) do
    Enum.random(choices)
  end

  defp random_value({:list, elem_spec, opts}) do
    length_range = Keyword.get(opts, :length, {1, 3})
    len = random_value({:int, length_range})
    Enum.map(1..len, fn _ -> random_value(elem_spec) end)
  end

  defp random_value(_), do: nil

  defimpl Kaizen.Evolvable, for: Map do
    @doc """
    Convert map to genome (identity operation).
    """
    def to_genome(map) when is_map(map) do
      map
    end

    @doc """
    Convert genome back to map (identity operation).
    """
    def from_genome(_original, genome) when is_map(genome) do
      genome
    end

    @doc """
    Calculate similarity between two hyperparameter maps.
    Returns 0.0 for identical, 1.0 for completely different.
    """
    def similarity(map1, map2) when is_map(map1) and is_map(map2) do
      keys = Map.keys(map1) |> MapSet.new()
      keys2 = Map.keys(map2) |> MapSet.new()

      if keys != keys2 do
        1.0
      else
        differences =
          Enum.count(keys, fn key ->
            Map.get(map1, key) != Map.get(map2, key)
          end)

        differences / map_size(map1)
      end
    end

    @doc """
    Validates hyperparameters against basic type constraints.
    """
    def valid?(hparams) when is_map(hparams) do
      # Basic validation: all values are present and valid types
      Enum.all?(hparams, fn {_key, value} ->
        is_number(value) or is_atom(value) or is_list(value)
      end)
    end

    def valid?(_), do: false
  end
end
