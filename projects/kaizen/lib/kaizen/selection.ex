defmodule Kaizen.Selection do
  @moduledoc """
  Behaviour for selection strategies.

  Selection determines which entities from the current population
  should be chosen as parents for the next generation.
  """

  @type entity :: term()
  @type population :: list(entity())
  @type scores :: %{entity() => float()}
  @type count :: pos_integer()
  @type opts :: keyword()

  @doc """
  Select entities from the population for reproduction.

  ## Parameters

  - `population` - The current population
  - `scores` - Map of entity to fitness score
  - `count` - Number of entities to select
  - `opts` - Strategy-specific options

  ## Returns

  A list of selected entities for reproduction.

  ## Examples

      def select(population, scores, count, opts) do
        # Tournament selection implementation
        Enum.take_random(population, count)
      end
  """
  @callback select(population(), scores(), count(), opts()) :: population()

  @doc """
  Maintain diversity in the selected population.

  This optional callback can be implemented to ensure
  the selected population maintains genetic diversity.
  """
  @callback maintain_diversity(population(), population(), opts()) :: population()

  @optional_callbacks [maintain_diversity: 3]

  defmacro __using__(_opts) do
    quote do
      @behaviour Kaizen.Selection

      @doc """
      Default diversity maintenance that returns the selected population unchanged.
      """
      def maintain_diversity(_population, selected, _opts) do
        selected
      end

      defoverridable maintain_diversity: 3
    end
  end
end
