defmodule Jido.Character.EvolveTest do
  use ExUnit.Case, async: true

  alias Jido.Character

  describe "evolve/2 with age" do
    test "ages integer age by full years" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, years: 1)

      assert evolved.identity.age == 31
      assert evolved.version == char.version + 1
    end

    test "does not age for less than a full year" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, days: 364)

      assert evolved.identity.age == 30
      assert evolved.version == char.version
    end

    test "ages by multiple years" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, years: 5)

      assert evolved.identity.age == 35
    end

    test "converts days to years for aging" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, days: 730)

      assert evolved.identity.age == 32
    end

    test "combines days and years" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, days: 365, years: 1)

      assert evolved.identity.age == 32
    end

    test "does not modify string ages" do
      {:ok, char} = Character.new(%{name: "Gandalf", identity: %{age: "ancient"}})

      {:ok, evolved} = Character.evolve(char, years: 100)

      assert evolved.identity.age == "ancient"
    end

    test "skips age evolution when age? is false" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, years: 1, age?: false)

      assert evolved.identity.age == 30
    end

    test "handles character with no identity" do
      {:ok, char} = Character.new(%{name: "Bob"})

      {:ok, evolved} = Character.evolve(char, years: 1)

      assert evolved.version == char.version
    end
  end

  describe "evolve/2 with memory decay" do
    test "decays memory importance over time" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Important event", importance: 1.0, decay_rate: 0.1)

      {:ok, evolved} = Character.evolve(char, days: 1)

      entry = hd(evolved.memory.entries)
      assert_in_delta entry.importance, 0.9, 0.001
    end

    test "compounds decay over multiple days" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Event", importance: 1.0, decay_rate: 0.1)

      {:ok, evolved} = Character.evolve(char, days: 7)

      entry = hd(evolved.memory.entries)
      expected = 1.0 * :math.pow(0.9, 7)
      assert_in_delta entry.importance, expected, 0.001
    end

    test "prunes memories below threshold" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Fading", importance: 0.1, decay_rate: 0.5)
      {:ok, char} = Character.add_memory(char, "Strong", importance: 0.9, decay_rate: 0.01)

      {:ok, evolved} = Character.evolve(char, days: 7)

      assert length(evolved.memory.entries) == 1
      assert hd(evolved.memory.entries).content == "Strong"
    end

    test "does not prune when memory_prune_below is nil" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Fading", importance: 0.1, decay_rate: 0.5)

      {:ok, evolved} = Character.evolve(char, days: 30, memory_prune_below: nil)

      assert length(evolved.memory.entries) == 1
    end

    test "custom prune threshold" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Event", importance: 0.5, decay_rate: 0.1)

      {:ok, evolved} = Character.evolve(char, days: 1, memory_prune_below: 0.5)

      assert evolved.memory.entries == []
    end

    test "skips memory evolution when memory? is false" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Event", importance: 1.0, decay_rate: 0.5)

      {:ok, evolved} = Character.evolve(char, days: 30, memory?: false)

      entry = hd(evolved.memory.entries)
      assert entry.importance == 1.0
    end

    test "handles character with no memories" do
      {:ok, char} = Character.new(%{name: "Bob"})

      {:ok, evolved} = Character.evolve(char, days: 30)

      assert evolved.version == char.version
    end

    test "preserves other memory fields during decay" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Event", importance: 1.0, decay_rate: 0.1, category: "test")

      {:ok, evolved} = Character.evolve(char, days: 1)

      entry = hd(evolved.memory.entries)
      assert entry.content == "Event"
      assert entry.category == "test"
      assert entry.decay_rate == 0.1
      assert %DateTime{} = entry.timestamp
    end
  end

  describe "evolve/2 edge cases" do
    test "returns unchanged character for zero time" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char)

      assert evolved.version == char.version
      assert evolved.identity.age == 30
    end

    test "returns unchanged character for negative time" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      {:ok, evolved} = Character.evolve(char, days: -10)

      assert evolved.version == char.version
    end

    test "multiple smaller evolutions equal one big evolution" do
      {:ok, char} = Character.new(%{name: "Bob"})
      {:ok, char} = Character.add_memory(char, "Event", importance: 1.0, decay_rate: 0.1)

      {:ok, evolved_once} = Character.evolve(char, days: 10)

      {:ok, evolved_twice} =
        char
        |> Character.evolve(days: 5)
        |> then(fn {:ok, c} -> Character.evolve(c, days: 5) end)

      entry_once = hd(evolved_once.memory.entries)
      entry_twice = hd(evolved_twice.memory.entries)

      assert_in_delta entry_once.importance, entry_twice.importance, 0.0001
    end
  end

  describe "evolve/2 via module-based character" do
    defmodule TestCharacter do
      use Jido.Character,
        defaults: %{name: "Test", identity: %{age: 25}}
    end

    test "module delegates to Character.evolve/2" do
      {:ok, char} = TestCharacter.new()

      {:ok, evolved} = TestCharacter.evolve(char, years: 1)

      assert evolved.identity.age == 26
    end
  end

  describe "evolve!/2" do
    test "returns evolved character on success" do
      {:ok, char} = Character.new(%{name: "Bob", identity: %{age: 30}})

      evolved = Character.evolve!(char, years: 1)

      assert evolved.identity.age == 31
    end

    test "works with zero time (returns same character)" do
      {:ok, char} = Character.new(%{name: "Bob"})

      evolved = Character.evolve!(char)

      assert evolved.version == char.version
    end

    test "module-based evolve! works" do
      {:ok, char} = __MODULE__.TestCharacter.new()

      evolved = __MODULE__.TestCharacter.evolve!(char, years: 2)

      assert evolved.identity.age == 27
    end
  end
end
