defmodule Kaizen.Examples.HyperparameterTuning do
  @moduledoc """
  Hyperparameter Optimization: Evolve ML model hyperparameters for best performance.

  ## Problem Description

  Optimize hyperparameters (learning rate, layer sizes, dropout, activation)
  to maximize model validation accuracy. Uses a surrogate fitness function
  that simulates training without running actual neural networks.

  This demonstrates:
  - **Mixed-type parameters**: Floats, integers, lists, and enums
  - **Schema-driven evolution**: Type-aware mutations
  - **Log-scale optimization**: Learning rate in log space
  - **Caching**: Avoid re-evaluating identical configurations

  ## Genome Representation

  Hyperparameter map:

      %{
        learning_rate: 0.001,
        hidden_layers: [128, 64],
        dropout_rate: 0.2,
        activation: :relu,
        batch_size: 32
      }

  ## Fitness Evaluation

  Surrogate function rewards:
  - Moderate learning rates (0.0001-0.01)
  - 2-3 hidden layers
  - Medium layer sizes (64-128)
  - Low dropout
  - Specific activations (:relu, :gelu)

  ## Usage

      iex> Kaizen.Examples.HyperparameterTuning.run()
      # Evolution progress shown...
      # Converges to good hyperparameter configuration

  ## Expected Results

  Converges to validation accuracy >0.85 in 50-100 generations,
  demonstrating schema-aware mutation and crossover.
  """

  alias Kaizen.Examples.Utils

  @schema %{
    learning_rate: {:float, {1.0e-5, 1.0e-1}, :log},
    hidden_layers: {:list, {:int, {16, 256}}, length: {1, 4}},
    dropout_rate: {:float, {0.0, 0.6}, :linear},
    activation: {:enum, [:relu, :tanh, :sigmoid, :gelu]},
    batch_size: {:enum, [16, 32, 64, 128]}
  }

  use Kaizen.Fitness

  @impl true
  def evaluate(hparams, context) do
    cache = context.cache
    key = :erlang.phash2(hparams)

    case :ets.lookup(cache, key) do
      [{^key, score}] ->
        {:ok, score}

      [] ->
        score = surrogate_fitness(hparams)
        :ets.insert(cache, {key, score})
        {:ok, score}
    end
  end

  @impl true
  def batch_evaluate(hparams_list, context) do
    results =
      Enum.map(hparams_list, fn hparams ->
        {:ok, score} = evaluate(hparams, context)
        {hparams, score}
      end)

    {:ok, results}
  end

  def run(opts \\ []) do
    population_size = Keyword.get(opts, :population_size, 50)
    generations = Keyword.get(opts, :generations, 100)
    verbose = Keyword.get(opts, :verbose, true)
    print_every = Keyword.get(opts, :print_every, 10)

    # Create cache
    cache = :ets.new(:hparam_cache, [:set, :public])

    # Generate initial population from schema
    initial_population =
      Enum.map(1..population_size, fn _ ->
        Kaizen.Evolvable.HParams.new(@schema)
      end)

    context = %{
      schema: @schema,
      cache: cache,
      gaussian_scale: 0.15
    }

    if verbose do
      Utils.print_header("Hyperparameter Tuning Demo", [
        {"Population Size", population_size},
        {"Generations", generations},
        {"Parameters", map_size(@schema)}
      ])
    end

    {:ok, config} =
      Kaizen.Config.new(
        population_size: population_size,
        generations: generations,
        mutation_rate: 0.3,
        crossover_rate: 0.7,
        elitism_rate: 0.02,
        selection_strategy: Kaizen.Selection.Tournament,
        mutation_strategy: Kaizen.Mutation.HParams,
        crossover_strategy: Kaizen.Crossover.MapUniform,
        termination_criteria: [target_fitness: 0.95]
      )

    result =
      try do
        Kaizen.evolve(
          initial_population: initial_population,
          config: config,
          fitness: __MODULE__,
          evolvable: Kaizen.Evolvable.Map,
          context: context
        )
        |> Stream.with_index()
        |> Stream.map(fn {state, _generation} ->
          if verbose and Utils.should_log?(state.generation, print_every) do
            print_generation(state)
          end

          state
        end)
        |> Stream.take(generations + 1)
        |> Enum.to_list()
        |> List.last()
      catch
        kind, error ->
          if verbose do
            IO.puts("\nError during evolution: #{inspect(kind)} - #{inspect(error)}")
          end

          nil
      end

    if result && verbose do
      print_final_solution(result, cache)
    end

    # Cleanup
    :ets.delete(cache)

    result
  end

  def demo, do: run(verbose: true)

  # Surrogate fitness function that simulates model training
  defp surrogate_fitness(hparams) do
    lr = hparams.learning_rate
    layers = hparams.hidden_layers
    dropout = hparams.dropout_rate
    activation = hparams.activation
    batch_size = hparams.batch_size

    # Reward optimal learning rate range
    lr_score =
      cond do
        lr >= 0.0001 and lr <= 0.01 -> 1.0
        lr > 0.01 and lr <= 0.1 -> 0.7
        true -> 0.3
      end

    # Reward 2-3 hidden layers
    layer_count_score =
      case length(layers) do
        2 -> 1.0
        3 -> 0.95
        1 -> 0.7
        _ -> 0.5
      end

    # Reward medium layer sizes (64-128)
    avg_layer_size = if Enum.empty?(layers), do: 0, else: Enum.sum(layers) / length(layers)

    layer_size_score =
      cond do
        avg_layer_size >= 64 and avg_layer_size <= 128 -> 1.0
        avg_layer_size >= 32 and avg_layer_size <= 256 -> 0.8
        true -> 0.5
      end

    # Reward low dropout
    dropout_score = 1.0 - dropout * 0.7

    # Reward specific activations
    activation_score =
      case activation do
        :relu -> 1.0
        :gelu -> 0.95
        :tanh -> 0.75
        :sigmoid -> 0.6
      end

    # Reward specific batch sizes
    batch_score =
      case batch_size do
        32 -> 1.0
        64 -> 0.95
        16 -> 0.85
        128 -> 0.8
      end

    # Combine scores with weights
    weighted_score =
      lr_score * 0.25 +
        layer_count_score * 0.2 +
        layer_size_score * 0.2 +
        dropout_score * 0.15 +
        activation_score * 0.15 +
        batch_score * 0.05

    # Add small noise to simulate stochasticity
    noise = (:rand.uniform() - 0.5) * 0.05
    max(0.0, min(1.0, weighted_score + noise))
  end

  defp print_generation(state) do
    hparams = state.best_entity
    accuracy = Float.round(state.best_score, 4)

    IO.puts(
      "Gen #{String.pad_leading(to_string(state.generation), 3)}: " <>
        "Accuracy=#{accuracy} " <>
        "LR=#{format_float(hparams.learning_rate, 6)} " <>
        "Layers=#{inspect(hparams.hidden_layers)} " <>
        "Act=#{hparams.activation}"
    )
  end

  defp print_final_solution(state, cache) do
    hparams = state.best_entity
    accuracy = Float.round(state.best_score, 4)
    cache_size = :ets.info(cache, :size)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Final Solution (Generation #{state.generation})")
    IO.puts(String.duplicate("=", 60))
    IO.puts("Validation Accuracy: #{accuracy}")
    IO.puts("\nBest Hyperparameters:")
    IO.puts("  - Learning Rate: #{format_float(hparams.learning_rate, 6)}")
    IO.puts("  - Hidden Layers: #{inspect(hparams.hidden_layers)}")
    IO.puts("  - Dropout Rate: #{Float.round(hparams.dropout_rate, 3)}")
    IO.puts("  - Activation: #{hparams.activation}")
    IO.puts("  - Batch Size: #{hparams.batch_size}")
    IO.puts("\nCache Statistics:")
    IO.puts("  - Unique Configurations Evaluated: #{cache_size}")
    IO.puts("")
  end

  defp format_float(value, precision) do
    :io_lib.format("~.#{precision}f", [value]) |> IO.iodata_to_binary()
  end
end
