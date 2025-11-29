defmodule Kaizen.Selection.Tournament do
  @moduledoc """
  Tournament selection strategy.

  Selects entities by running tournaments between randomly chosen
  candidates and picking the winner based on fitness scores.
  """

  use Kaizen.Selection

  @doc """
  Select entities using tournament selection.

  ## Options

  - `:tournament_size` - Number of entities in each tournament (default: 2)
  - `:pressure` - Selection pressure multiplier (default: 1.0)

  ## Examples

      population = ["a", "b", "c", "d"]
      scores = %{"a" => 0.8, "b" => 0.6, "c" => 0.9, "d" => 0.3}
      selected = Kaizen.Selection.Tournament.select(population, scores, 2, tournament_size: 2)
  """
  def select(population, scores, count, opts \\ []) do
    tournament_size = Keyword.get(opts, :tournament_size, 2)
    pressure = Keyword.get(opts, :pressure, 1.0)

    if length(population) == 0 or map_size(scores) == 0 do
      []
    else
      1..count
      |> Enum.map(fn _ ->
        run_tournament(population, scores, tournament_size, pressure)
      end)
    end
  end

  # Private functions

  defp run_tournament(population, scores, tournament_size, pressure) do
    # Select random candidates for tournament
    candidates = Enum.take_random(population, min(tournament_size, length(population)))

    # Find the best candidate based on fitness scores
    candidates
    |> Enum.map(fn candidate ->
      score = Map.get(scores, candidate, 0.0)
      adjusted_score = :math.pow(score, pressure)
      {candidate, adjusted_score}
    end)
    |> Enum.max_by(fn {_candidate, score} -> score end)
    |> elem(0)
  end
end
