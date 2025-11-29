defmodule Kaizen.Config do
  @moduledoc """
  Configuration structure for evolutionary algorithms.

  Uses NimbleOptions for validation and provides sensible defaults.
  """

  use TypedStruct

  typedstruct do
    @typedoc "Configuration for evolutionary algorithms"

    field(:population_size, pos_integer(), default: 100)
    field(:generations, pos_integer(), default: 1000)
    field(:mutation_rate, float(), default: 0.1)
    field(:crossover_rate, float(), default: 0.7)
    field(:elitism_rate, float(), default: 0.05)
    field(:max_concurrency, pos_integer(), default: System.schedulers_online())
    field(:selection_strategy, atom(), default: Kaizen.Selection.Tournament)
    field(:mutation_strategy, atom(), default: Kaizen.Mutation.Text)
    field(:crossover_strategy, atom(), default: Kaizen.Crossover.String)
    field(:termination_criteria, keyword(), default: [])
    field(:checkpoint_interval, pos_integer() | nil, default: nil)
    field(:metrics_enabled, boolean(), default: true)
    field(:random_seed, integer() | nil, default: nil)
  end

  @config_schema [
    population_size: [
      type: :pos_integer,
      default: 100,
      doc: "Number of entities in the population"
    ],
    generations: [
      type: :pos_integer,
      default: 1000,
      doc: "Maximum number of generations to evolve"
    ],
    mutation_rate: [
      type: :float,
      default: 0.1,
      doc: "Probability of mutation for each entity"
    ],
    crossover_rate: [
      type: :float,
      default: 0.7,
      doc: "Probability of crossover between entities"
    ],
    elitism_rate: [
      type: :float,
      default: 0.05,
      doc: "Fraction of best entities to preserve unchanged"
    ],
    max_concurrency: [
      type: :pos_integer,
      default: System.schedulers_online(),
      doc: "Maximum number of concurrent fitness evaluations"
    ],
    selection_strategy: [
      type: :atom,
      default: Kaizen.Selection.Tournament,
      doc: "Module implementing Kaizen.Selection behaviour"
    ],
    mutation_strategy: [
      type: :atom,
      default: Kaizen.Mutation.Text,
      doc: "Module implementing Kaizen.Mutation behaviour"
    ],
    crossover_strategy: [
      type: :atom,
      default: Kaizen.Crossover.String,
      doc: "Module implementing Kaizen.Crossover behaviour"
    ],
    termination_criteria: [
      type: :keyword_list,
      default: [],
      doc: "Conditions for early termination"
    ],
    checkpoint_interval: [
      type: {:or, [:pos_integer, nil]},
      default: nil,
      doc: "Save checkpoint every N generations"
    ],
    metrics_enabled: [
      type: :boolean,
      default: true,
      doc: "Enable telemetry and metrics collection"
    ],
    random_seed: [
      type: {:or, [:integer, nil]},
      default: nil,
      doc: "Random seed for reproducible results"
    ]
  ]

  @doc """
  Create a new configuration with validation.

  ## Examples

      iex> {:ok, config} = Kaizen.Config.new(population_size: 50)
      iex> config.population_size
      50
      
      iex> {:error, error} = Kaizen.Config.new(population_size: -1)
      iex> error.__struct__
      NimbleOptions.ValidationError
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, NimbleOptions.ValidationError.t()}
  def new(opts \\ []) do
    case NimbleOptions.validate(opts, @config_schema) do
      {:ok, validated_opts} ->
        config = struct(__MODULE__, validated_opts)

        case validate_rates(config) do
          :ok -> {:ok, config}
          {:error, reason} -> {:error, %ArgumentError{message: reason}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Create a new configuration, raising on validation errors.

  ## Examples

      iex> config = Kaizen.Config.new!(population_size: 50)
      iex> config.population_size
      50
  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end

  @doc """
  Get the number of elite entities to preserve.
  """
  @spec elite_count(t()) :: non_neg_integer()
  def elite_count(%__MODULE__{population_size: pop_size, elitism_rate: rate}) do
    if rate > 0.0, do: max(1, round(pop_size * rate)), else: 0
  end

  @doc """
  Initialize random seed if configured.
  """
  @spec init_random_seed(t()) :: :ok
  def init_random_seed(%__MODULE__{random_seed: nil}), do: :ok

  @spec init_random_seed(t()) :: :ok
  def init_random_seed(%__MODULE__{random_seed: seed}) do
    :rand.seed(:default, seed)
    :ok
  end

  # Private helper to validate rate parameters
  defp validate_rates(%__MODULE__{mutation_rate: mr, crossover_rate: cr, elitism_rate: er}) do
    cond do
      mr < 0.0 or mr > 1.0 ->
        {:error, "mutation_rate must be between 0.0 and 1.0, got: #{mr}"}

      cr < 0.0 or cr > 1.0 ->
        {:error, "crossover_rate must be between 0.0 and 1.0, got: #{cr}"}

      er < 0.0 or er > 1.0 ->
        {:error, "elitism_rate must be between 0.0 and 1.0, got: #{er}"}

      true ->
        :ok
    end
  end
end
