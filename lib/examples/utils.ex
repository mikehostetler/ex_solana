defmodule Kaizen.Examples.Utils do
  @moduledoc """
  Shared utilities for Kaizen examples.
  """

  @doc """
  Print a demo header with key-value pairs.
  """
  def print_header(title, opts \\ []) do
    IO.puts("\n#{title}")
    IO.puts(String.duplicate("=", String.length(title)))

    Enum.each(opts, fn {key, value} ->
      IO.puts("#{key}: #{value}")
    end)

    IO.puts("")
  end

  @doc """
  Determine if logging should occur for this generation.
  """
  def should_log?(generation, print_every \\ 10) do
    rem(generation, print_every) == 0
  end

  @doc """
  Generate a random binary vector of length n.
  """
  def random_binary(n) when is_integer(n) and n > 0 do
    Enum.map(1..n, fn _ -> Enum.random([0, 1]) end)
  end

  @doc """
  Generate a random permutation of integers 0..n-1.
  """
  def random_permutation(n) when is_integer(n) and n > 0 do
    Enum.shuffle(0..(n - 1))
  end

  @doc """
  Format a fitness value for display.
  """
  def format_fitness(fitness) when is_float(fitness) do
    Float.round(fitness, 4)
  end

  def format_fitness(fitness) when is_integer(fitness) do
    fitness
  end
end
