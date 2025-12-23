defmodule Jido.Character.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.Character

  setup do
    {:ok, char} = Character.new(%{name: "Test"})
    {:ok, char: char}
  end

  describe "add_knowledge/2,3" do
    test "adds knowledge with string shorthand", %{char: char} do
      {:ok, updated} = Character.add_knowledge(char, "Expert in Elixir")

      assert [%{content: "Expert in Elixir"}] = updated.knowledge
    end

    test "adds knowledge with options", %{char: char} do
      {:ok, updated} = Character.add_knowledge(char, "Expert in Elixir", category: "skills", importance: 0.9)

      assert [%{content: "Expert in Elixir", category: "skills", importance: 0.9}] = updated.knowledge
    end

    test "adds knowledge with map", %{char: char} do
      {:ok, updated} = Character.add_knowledge(char, %{content: "Expert in Elixir", importance: 0.8})

      assert [%{content: "Expert in Elixir", importance: 0.8}] = updated.knowledge
    end

    test "adds multiple knowledge items as list", %{char: char} do
      {:ok, updated} = Character.add_knowledge(char, ["Knows Elixir", "Knows Python"])

      assert length(updated.knowledge) == 2
      assert Enum.any?(updated.knowledge, &(&1.content == "Knows Elixir"))
      assert Enum.any?(updated.knowledge, &(&1.content == "Knows Python"))
    end

    test "appends to existing knowledge", %{char: char} do
      {:ok, char} = Character.add_knowledge(char, "First item")
      {:ok, updated} = Character.add_knowledge(char, "Second item")

      assert length(updated.knowledge) == 2
    end

    test "increments version on each add", %{char: char} do
      {:ok, char} = Character.add_knowledge(char, "First")
      {:ok, updated} = Character.add_knowledge(char, "Second")

      assert updated.version == char.version + 1
    end
  end

  describe "add_instruction/2" do
    test "adds single instruction", %{char: char} do
      {:ok, updated} = Character.add_instruction(char, "Always be helpful")

      assert "Always be helpful" in updated.instructions
    end

    test "adds multiple instructions", %{char: char} do
      {:ok, updated} = Character.add_instruction(char, ["Be helpful", "Be concise"])

      assert "Be helpful" in updated.instructions
      assert "Be concise" in updated.instructions
    end

    test "appends to existing instructions", %{char: char} do
      {:ok, char} = Character.add_instruction(char, "First")
      {:ok, updated} = Character.add_instruction(char, "Second")

      assert "First" in updated.instructions
      assert "Second" in updated.instructions
    end
  end

  describe "add_memory/2,3" do
    test "adds memory with string shorthand", %{char: char} do
      {:ok, updated} = Character.add_memory(char, "User prefers brief answers")

      assert updated.memory.entries != []
      assert hd(updated.memory.entries).content == "User prefers brief answers"
    end

    test "adds memory with options", %{char: char} do
      {:ok, updated} = Character.add_memory(char, "Important event", importance: 0.9, category: "events")

      entry = hd(updated.memory.entries)
      assert entry.content == "Important event"
      assert entry.importance == 0.9
      assert entry.category == "events"
    end

    test "adds memory with map", %{char: char} do
      {:ok, updated} = Character.add_memory(char, %{content: "User said hello", importance: 0.5})

      assert hd(updated.memory.entries).content == "User said hello"
    end

    test "sets timestamp automatically", %{char: char} do
      {:ok, updated} = Character.add_memory(char, "Event happened")

      entry = hd(updated.memory.entries)
      assert %DateTime{} = entry.timestamp
    end

    test "preserves memory capacity", %{char: char} do
      {:ok, updated} = Character.add_memory(char, "Event")

      assert updated.memory.capacity == 100
    end

    test "enforces memory capacity by dropping oldest entries" do
      {:ok, char} = Character.new(%{name: "Test", memory: %{capacity: 3}})

      {:ok, char} = Character.add_memory(char, "First")
      {:ok, char} = Character.add_memory(char, "Second")
      {:ok, char} = Character.add_memory(char, "Third")

      assert length(char.memory.entries) == 3

      {:ok, char} = Character.add_memory(char, "Fourth")

      assert length(char.memory.entries) == 3
      contents = Enum.map(char.memory.entries, & &1.content)
      refute "First" in contents
      assert "Second" in contents
      assert "Third" in contents
      assert "Fourth" in contents
    end

    test "drops multiple oldest entries when over capacity" do
      {:ok, char} = Character.new(%{name: "Test", memory: %{capacity: 2}})

      {:ok, char} = Character.add_memory(char, "A")
      {:ok, char} = Character.add_memory(char, "B")
      {:ok, char} = Character.add_memory(char, "C")
      {:ok, char} = Character.add_memory(char, "D")
      {:ok, char} = Character.add_memory(char, "E")

      assert length(char.memory.entries) == 2
      contents = Enum.map(char.memory.entries, & &1.content)
      assert "D" in contents
      assert "E" in contents
    end
  end

  describe "add_trait/2,3" do
    test "adds string trait", %{char: char} do
      {:ok, updated} = Character.add_trait(char, "curious")

      assert "curious" in updated.personality.traits
    end

    test "adds trait with intensity", %{char: char} do
      {:ok, updated} = Character.add_trait(char, "analytical", intensity: 0.9)

      assert %{name: "analytical", intensity: 0.9} in updated.personality.traits
    end

    test "adds trait map", %{char: char} do
      {:ok, updated} = Character.add_trait(char, %{name: "patient", intensity: 0.7})

      assert %{name: "patient", intensity: 0.7} in updated.personality.traits
    end

    test "adds multiple traits", %{char: char} do
      {:ok, updated} = Character.add_trait(char, ["curious", "patient"])

      assert "curious" in updated.personality.traits
      assert "patient" in updated.personality.traits
    end
  end

  describe "add_value/2" do
    test "adds single value", %{char: char} do
      {:ok, updated} = Character.add_value(char, "accuracy")

      assert "accuracy" in updated.personality.values
    end

    test "adds multiple values", %{char: char} do
      {:ok, updated} = Character.add_value(char, ["accuracy", "clarity"])

      assert "accuracy" in updated.personality.values
      assert "clarity" in updated.personality.values
    end
  end

  describe "add_quirk/2" do
    test "adds single quirk", %{char: char} do
      {:ok, updated} = Character.add_quirk(char, "Uses analogies frequently")

      assert "Uses analogies frequently" in updated.personality.quirks
    end

    test "adds multiple quirks", %{char: char} do
      {:ok, updated} = Character.add_quirk(char, ["Uses analogies", "Asks questions"])

      assert "Uses analogies" in updated.personality.quirks
      assert "Asks questions" in updated.personality.quirks
    end
  end

  describe "add_expression/2" do
    test "adds single expression", %{char: char} do
      {:ok, updated} = Character.add_expression(char, "Let me think...")

      assert "Let me think..." in updated.voice.expressions
    end

    test "adds multiple expressions", %{char: char} do
      {:ok, updated} = Character.add_expression(char, ["Let me think...", "Interesting!"])

      assert "Let me think..." in updated.voice.expressions
      assert "Interesting!" in updated.voice.expressions
    end
  end

  describe "add_fact/2" do
    test "adds single fact", %{char: char} do
      {:ok, updated} = Character.add_fact(char, "Has a PhD")

      assert "Has a PhD" in updated.identity.facts
    end

    test "adds multiple facts", %{char: char} do
      {:ok, updated} = Character.add_fact(char, ["Has a PhD", "Worked at startups"])

      assert "Has a PhD" in updated.identity.facts
      assert "Worked at startups" in updated.identity.facts
    end
  end

  describe "pipe-friendly chaining" do
    test "chains multiple helpers together", %{char: char} do
      result =
        char
        |> Character.add_knowledge("Expert in Elixir")
        |> then(fn {:ok, c} -> Character.add_instruction(c, "Be helpful") end)
        |> then(fn {:ok, c} -> Character.add_trait(c, "curious") end)
        |> then(fn {:ok, c} -> Character.add_value(c, "accuracy") end)

      assert {:ok, updated} = result

      assert length(updated.knowledge) == 1
      assert "Be helpful" in updated.instructions
      assert "curious" in updated.personality.traits
      assert "accuracy" in updated.personality.values
      assert updated.version == char.version + 4
    end
  end
end
