# Kaizen

Evolutionary algorithms for Elixir. Evolve strings, configs, maps, or any data structure toward higher fitness. Stream-based, parallel, pluggable.

## Install

```elixir
def deps do
  [
    {:kaizen, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
defmodule MyFitness do
  use Kaizen.Fitness
  def evaluate(entity, _ctx), do: {:ok, String.length(entity)}
end

config = Kaizen.Config.new!(
  population_size: 50,
  generations: 100,
  mutation_rate: 0.1,
  crossover_rate: 0.7
)

initial = ["random", "strings", "here"]

final_state =
  Kaizen.evolve(
    initial_population: initial,
    config: config,
    fitness: MyFitness,
    evolvable: Kaizen.Evolvable.String
  )
  |> Enum.reduce(fn _prev, state -> state end)

IO.puts("Best: #{final_state.best_entity} (#{final_state.best_score})")
```

## How It Works

`Kaizen.evolve/1` returns a lazy `Stream` of `Kaizen.State` (one per generation).

Each generation:
1. **Evaluate** fitness (parallel via `Task.async_stream`)
2. **Select** parents
3. **Crossover** pairs (probability: `crossover_rate`)
4. **Mutate** offspring (probability: `mutation_rate`)
5. **Apply elitism** (preserve top `elitism_rate`)
6. **Check termination** criteria

Pluggable behaviors:
- `Kaizen.Fitness` — score entities
- `Kaizen.Mutation` — mutate entities
- `Kaizen.Selection` — select parents
- `Kaizen.Crossover` — combine entities
- `Kaizen.Evolvable` (protocol) — representation + similarity

## Configure

```elixir
Kaizen.Config.new!(
  population_size: 100,           # Population size
  generations: 1000,              # Max generations
  mutation_rate: 0.1,             # Mutation probability
  crossover_rate: 0.7,            # Crossover probability
  elitism_rate: 0.05,             # Top % preserved unchanged
  selection_strategy: Kaizen.Selection.Tournament,
  mutation_strategy: Kaizen.Mutation.Text,
  crossover_strategy: Kaizen.Crossover.String,
  termination_criteria: [target_fitness: 100],
  max_concurrency: System.schedulers_online(),
  random_seed: 1234               # For deterministic runs
)
```

## Extend

### Custom Fitness

```elixir
defmodule MyFitness do
  use Kaizen.Fitness
  
  def evaluate(entity, ctx), do: {:ok, my_score(entity, ctx)}
  
  # Optional: batch scoring for efficiency
  def batch_evaluate(entities, ctx) do
    {:ok, Enum.map(entities, &my_score(&1, ctx))}
  end
  
  # Optional: custom comparison (default maximizes)
  def compare(a_score, b_score, _ctx), do: a_score >= b_score
end
```

### Custom Evolvable

```elixir
defimpl Kaizen.Evolvable, for: MyType do
  def to_genome(t), do: normalize(t)
  def from_genome(_t, genome), do: denormalize(genome)
  def similarity(a, b), do: distance_metric(a, b)
end
```

### Custom Mutation

```elixir
defmodule MyMutator do
  @behaviour Kaizen.Mutation
  
  def mutate(entity, _opts), do: {:ok, mutated(entity)}
end
```

Wire via config: `mutation_strategy: MyMutator`

## Operations

**Parallel scoring**: Fitness evaluations run concurrently. Control via `max_concurrency`.

**Determinism**: Set `random_seed` and ensure `evaluate/2` is pure.

**Telemetry**: Emits `:kaizen` events for evolution, generations, and evaluations.

## Examples & Docs

- `lib/examples/hello_world.ex` — runnable example
- `IDEA.md` — multi-objective, distributed evolution
- `GEPA.md` — LLM/prompt evolution
- `NEW_API.md` — proposed convenience API
