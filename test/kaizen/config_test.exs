defmodule Kaizen.ConfigTest do
  use ExUnit.Case
  doctest Kaizen.Config

  test "creates config with defaults" do
    {:ok, config} = Kaizen.Config.new()

    assert config.population_size == 100
    assert config.generations == 1000
    assert config.mutation_rate == 0.1
    assert config.crossover_rate == 0.7
    assert config.elitism_rate == 0.05
  end

  test "creates config with custom values" do
    {:ok, config} = Kaizen.Config.new(population_size: 50, mutation_rate: 0.2)

    assert config.population_size == 50
    assert config.mutation_rate == 0.2
    # Default preserved
    assert config.generations == 1000
  end

  test "validates config parameters" do
    assert {:error, _} = Kaizen.Config.new(population_size: -1)
    assert {:error, _} = Kaizen.Config.new(mutation_rate: 1.5)
  end

  test "calculates elite count correctly" do
    {:ok, config} = Kaizen.Config.new(population_size: 100, elitism_rate: 0.1)
    assert Kaizen.Config.elite_count(config) == 10

    {:ok, config} = Kaizen.Config.new(population_size: 50, elitism_rate: 0.02)
    # Minimum of 1
    assert Kaizen.Config.elite_count(config) == 1
  end
end
