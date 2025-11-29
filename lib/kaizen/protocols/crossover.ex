defmodule Kaizen.Crossover do
  @moduledoc """
  Protocol for crossover operations between two parent entities.

  Crossover combines genetic material from two parents to create offspring,
  introducing diversity while preserving beneficial traits from both parents.

  ## Example

      defmodule MyCustomCrossover do
        @behaviour Kaizen.Crossover

        @impl true
        def crossover(parent1, parent2, _config) do
          # Simple single-point crossover for strings
          if String.length(parent1) > 0 and String.length(parent2) > 0 do
            point = :rand.uniform(min(String.length(parent1), String.length(parent2)))
            child1 = String.slice(parent1, 0, point) <> String.slice(parent2, point, String.length(parent2))
            child2 = String.slice(parent2, 0, point) <> String.slice(parent1, point, String.length(parent1))
            {child1, child2}
          else
            {parent1, parent2}
          end
        end
      end
  """

  @doc """
  Performs crossover between two parent entities to produce two offspring.

  ## Parameters

  - `parent1` - First parent entity
  - `parent2` - Second parent entity  
  - `config` - Configuration map that may contain crossover-specific parameters

  ## Returns

  A tuple `{child1, child2}` containing two offspring entities.
  """
  @callback crossover(parent1 :: any(), parent2 :: any(), config :: map()) :: {any(), any()}
end
