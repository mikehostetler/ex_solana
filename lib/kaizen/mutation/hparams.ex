defmodule Kaizen.Mutation.HParams do
  @moduledoc """
  Schema-driven mutation for hyperparameter maps.

  Mutates values according to their type in the schema:
  - Floats: Gaussian perturbation (log-space for log-scale)
  - Integers: ±1 step with clamping
  - Enums: Random reselection with low probability
  - Lists: Mutate elements, insert, or delete

  ## Options

  - `:schema` - Schema definition (required)
  - `:rate` - Mutation rate per parameter (default: from config)
  - `:gaussian_scale` - Scale for Gaussian mutations (default: 0.1)

  ## Example

      schema = %{
        learning_rate: {:float, 0.001..0.1, :log},
        activation: {:enum, [:relu, :tanh]}
      }
      
      hparams = %{learning_rate: 0.01, activation: :relu}
      mutate(hparams, config, schema: schema)
  """

  use Kaizen.Mutation

  @impl true
  def mutate(hparams, opts) when is_map(hparams) do
    schema = Keyword.get(opts, :schema)
    rate = Keyword.get(opts, :rate, 0.1)
    gaussian_scale = Keyword.get(opts, :gaussian_scale, 0.1)

    if schema == nil do
      {:error, "HParams mutation requires :schema in opts"}
    else
      mutated =
        Enum.map(hparams, fn {key, value} ->
          spec = Map.get(schema, key)

          if spec && :rand.uniform() < rate do
            {key, mutate_value(value, spec, gaussian_scale)}
          else
            {key, value}
          end
        end)
        |> Map.new()

      {:ok, mutated}
    end
  end

  def mutate(_genome, _opts) do
    {:error, "HParams mutation requires map genome"}
  end

  defp mutate_value(value, {:float, {min, max}, :linear}, scale) do
    delta = :rand.normal(0.0, scale) * (max - min)
    clamp(value + delta, min, max)
  end

  defp mutate_value(value, {:float, {min, max}, :log}, scale) do
    log_value = :math.log(value)
    log_min = :math.log(min)
    log_max = :math.log(max)
    delta = :rand.normal(0.0, scale) * (log_max - log_min)
    new_log = clamp(log_value + delta, log_min, log_max)
    :math.exp(new_log)
  end

  defp mutate_value(value, {:int, {min, max}}, _scale) do
    delta = Enum.random([-1, 1])
    clamp(value + delta, min, max)
  end

  defp mutate_value(_value, {:enum, choices}, _scale) do
    Enum.random(choices)
  end

  defp mutate_value(list, {:list, elem_spec, opts}, scale) when is_list(list) do
    {min_len, max_len} = Keyword.get(opts, :length, {1, 10})

    case :rand.uniform(3) do
      1 when length(list) > min_len ->
        # Delete random element
        List.delete_at(list, :rand.uniform(length(list)) - 1)

      2 when length(list) < max_len ->
        # Insert random element
        new_elem = random_value(elem_spec)
        List.insert_at(list, :rand.uniform(length(list) + 1) - 1, new_elem)

      _ ->
        # Mutate random element
        idx = :rand.uniform(length(list)) - 1
        elem = Enum.at(list, idx)
        mutated_elem = mutate_value(elem, elem_spec, scale)
        List.replace_at(list, idx, mutated_elem)
    end
  end

  defp mutate_value(value, _spec, _scale), do: value

  defp clamp(value, min, max) do
    value
    |> max(min)
    |> min(max)
  end

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

  defp random_value(_), do: 0
end
