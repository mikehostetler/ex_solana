defmodule Kaizen do
  @moduledoc """
  Kaizen - A generic evolutionary algorithm framework for Elixir.

  Kaizen provides a flexible, protocol-based system for evolving any data structure
  using pluggable strategies for mutation, selection, crossover, and evaluation.

  ## Quick Start

      # Define a fitness function
      defmodule MyFitness do
        use Kaizen.Fitness
        
        def evaluate(text, _context) do
          target = "Hello, world!"
          similarity = String.jaro_distance(text, target)
          {:ok, similarity}
        end
      end
      
      # Configure and run evolution
      config = Kaizen.Config.new!(
        population_size: 100,
        generations: 50,
        mutation_rate: 0.3
      )
      
      result = Kaizen.evolve(
        initial_population: ["Hello, wrld!"],
        config: config,
        fitness: MyFitness,
        evolvable: Kaizen.Evolvable.String
      )
      |> Enum.take(50)
      |> List.last()

  ## Core Concepts

  - **Evolvable**: Protocol that defines how entities can be converted to/from genomes
  - **Fitness**: Behaviour for evaluating how good an entity is
  - **Mutation**: Behaviour for creating variations of entities
  - **Selection**: Behaviour for choosing which entities reproduce
  - **Engine**: Core algorithm that orchestrates the evolutionary process
  - **State**: Immutable representation of population state at each generation

  ## Available Strategies

  ### Selection
  - `Kaizen.Selection.Tournament` - Tournament selection with configurable size

  ### Mutation  
  - `Kaizen.Mutation.Random` - Random mutations for any evolvable type

  ### Evolvable Implementations
  - `Kaizen.Evolvable.String` - For evolving strings/text
  """

  @doc """
  Convenience function to run evolution with a simple configuration.

  This function provides an easier interface to `Kaizen.Engine.evolve/5`
  with commonly used defaults.

  ## Parameters

  - `:initial_population` - List of initial entities
  - `:config` - Kaizen.Config struct
  - `:fitness` - Module implementing Kaizen.Fitness behaviour  
  - `:evolvable` - Module implementing Kaizen.Evolvable protocol

  ## Options

  - `:mutation` - Mutation module (default from config)
  - `:selection` - Selection module (default from config)  
  - `:context` - Context passed to fitness evaluation

  ## Examples

      config = Kaizen.Config.new!(population_size: 50)
      
      Kaizen.evolve(
        initial_population: ["seed"],
        config: config, 
        fitness: MyFitness,
        evolvable: Kaizen.Evolvable.String
      )
      |> Stream.take_while(fn state -> state.best_score < 0.95 end)
      |> Enum.to_list()
      |> List.last()
  """
  def evolve(opts) do
    initial_population = Keyword.fetch!(opts, :initial_population)
    config = Keyword.fetch!(opts, :config)
    fitness = Keyword.fetch!(opts, :fitness)
    evolvable = Keyword.fetch!(opts, :evolvable)

    engine_opts = Keyword.take(opts, [:mutation, :selection, :context])

    Kaizen.Engine.evolve(initial_population, config, fitness, evolvable, engine_opts)
  end

  @doc """
  Get version information.
  """
  def version do
    Application.spec(:kaizen, :vsn) |> List.to_string()
  end
end
