defmodule Kaizen.Mutation.Binary do
  @moduledoc """
  Bit-flip mutation for binary genomes.

  Randomly flips bits (0→1 or 1→0) based on mutation rate.
  Each position has an independent probability of being flipped.

  ## Usage

      config = %{
        mutation_module: Kaizen.Mutation.Binary,
        mutation_rate: 0.1  # 10% chance per bit
      }
  """

  use Kaizen.Mutation

  @impl true
  def mutate(genome, opts) do
    rate = Keyword.get(opts, :rate, 0.1)

    mutated_genome =
      Enum.map(genome, fn bit ->
        if :rand.uniform() < rate do
          1 - bit
        else
          bit
        end
      end)

    {:ok, mutated_genome}
  end
end
