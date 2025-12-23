defmodule Jido.Character.SchemaTest do
  use ExUnit.Case, async: true

  alias Jido.Character.Schema

  describe "character/0" do
    test "parses minimal character with only id" do
      input = %{id: "test-123"}

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.id == "test-123"
      assert result.knowledge == []
      assert result.instructions == []
      assert result.extensions == %{}
      assert result.version == 1
    end

    test "parses complete character with all fields" do
      now = DateTime.utc_now()

      input = %{
        id: "alex-researcher",
        name: "Alex",
        description: "A curious research assistant",
        identity: %{
          age: 30,
          role: "Researcher",
          background: "Former academic",
          facts: ["Has PhD", "Worked at startups"]
        },
        personality: %{
          traits: ["curious", %{name: "patient", intensity: 0.8}],
          values: ["accuracy", "clarity"],
          quirks: ["Uses analogies"]
        },
        voice: %{
          tone: :warm,
          style: "Conversational but precise",
          vocabulary: :conversational,
          expressions: ["Great question!", "Let me explain..."]
        },
        memory: %{
          capacity: 50,
          entries: [
            %{content: "User likes Elixir", importance: 0.8, decay_rate: 0.05}
          ]
        },
        knowledge: [
          %{content: "Expert in Elixir", category: "skills", importance: 0.9}
        ],
        instructions: ["Be helpful", "Ask clarifying questions"],
        extensions: %{custom: %{data: "value"}},
        created_at: now,
        updated_at: now,
        version: 2
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.id == "alex-researcher"
      assert result.name == "Alex"
      assert result.description == "A curious research assistant"
      assert result.identity.age == 30
      assert result.identity.role == "Researcher"
      assert result.personality.traits == ["curious", %{name: "patient", intensity: 0.8}]
      assert result.voice.tone == :warm
      assert result.memory.capacity == 50
      assert length(result.memory.entries) == 1
      assert length(result.knowledge) == 1
      assert result.instructions == ["Be helpful", "Ask clarifying questions"]
      assert result.extensions == %{custom: %{data: "value"}}
      assert result.version == 2
    end

    test "fails when id is missing" do
      input = %{name: "Alex"}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "fails when id is empty string" do
      input = %{id: ""}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "trims name and description" do
      input = %{id: "test", name: "  Alex  ", description: "  A description  "}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.name == "Alex"
      assert result.description == "A description"
    end
  end

  describe "identity/0" do
    test "age can be integer" do
      input = %{id: "test", identity: %{age: 30}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.identity.age == 30
    end

    test "age can be string" do
      input = %{id: "test", identity: %{age: "30s"}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.identity.age == "30s"
    end

    test "age can be descriptive string" do
      input = %{id: "test", identity: %{age: "ancient"}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.identity.age == "ancient"
    end

    test "rejects negative age" do
      input = %{id: "test", identity: %{age: -5}}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "facts defaults to empty list" do
      input = %{id: "test", identity: %{role: "Helper"}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.identity.facts == []
    end
  end

  describe "personality/0" do
    test "trait as simple string" do
      input = %{id: "test", personality: %{traits: ["curious", "patient"]}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.personality.traits == ["curious", "patient"]
    end

    test "trait as map with name and intensity" do
      input = %{
        id: "test",
        personality: %{traits: [%{name: "curious", intensity: 0.9}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.personality.traits == [%{name: "curious", intensity: 0.9}]
    end

    test "mixed traits (string and map)" do
      input = %{
        id: "test",
        personality: %{traits: ["patient", %{name: "curious", intensity: 0.9}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.personality.traits == ["patient", %{name: "curious", intensity: 0.9}]
    end

    test "intensity defaults to 0.5" do
      input = %{
        id: "test",
        personality: %{traits: [%{name: "curious"}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.personality.traits == [%{name: "curious", intensity: 0.5}]
    end

    test "rejects intensity > 1" do
      input = %{
        id: "test",
        personality: %{traits: [%{name: "curious", intensity: 1.5}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects intensity < 0" do
      input = %{
        id: "test",
        personality: %{traits: [%{name: "curious", intensity: -0.1}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "defaults collections to empty lists" do
      input = %{id: "test", personality: %{}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.personality.traits == []
      assert result.personality.values == []
      assert result.personality.quirks == []
    end
  end

  describe "voice/0" do
    test "tone defaults to :casual" do
      input = %{id: "test", voice: %{}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.voice.tone == :casual
    end

    test "accepts valid tone values" do
      for tone <- [:formal, :casual, :playful, :serious, :warm, :cold, :professional, :friendly] do
        input = %{id: "test", voice: %{tone: tone}}
        assert {:ok, result} = Zoi.parse(Schema.character(), input)
        assert result.voice.tone == tone
      end
    end

    test "rejects invalid tone" do
      input = %{id: "test", voice: %{tone: :invalid}}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "accepts valid vocabulary values" do
      for vocab <- [:simple, :technical, :academic, :conversational, :poetic] do
        input = %{id: "test", voice: %{vocabulary: vocab}}
        assert {:ok, result} = Zoi.parse(Schema.character(), input)
        assert result.voice.vocabulary == vocab
      end
    end

    test "expressions defaults to empty list" do
      input = %{id: "test", voice: %{tone: :warm}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.voice.expressions == []
    end
  end

  describe "memory/0" do
    test "capacity defaults to 100" do
      input = %{id: "test", memory: %{}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.memory.capacity == 100
    end

    test "entries defaults to empty list" do
      input = %{id: "test", memory: %{}}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.memory.entries == []
    end

    test "rejects non-positive capacity" do
      input = %{id: "test", memory: %{capacity: 0}}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects negative capacity" do
      input = %{id: "test", memory: %{capacity: -10}}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end
  end

  describe "memory_entry/0" do
    test "parses valid memory entry" do
      input = %{
        id: "test",
        memory: %{
          entries: [
            %{content: "User likes Elixir", importance: 0.8, decay_rate: 0.05}
          ]
        }
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      entry = hd(result.memory.entries)
      assert entry.content == "User likes Elixir"
      assert entry.importance == 0.8
      assert entry.decay_rate == 0.05
    end

    test "importance defaults to 0.5" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Something happened"}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert hd(result.memory.entries).importance == 0.5
    end

    test "decay_rate defaults to 0.1" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Something happened"}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert hd(result.memory.entries).decay_rate == 0.1
    end

    test "rejects importance > 1" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Event", importance: 1.5}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects importance < 0" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Event", importance: -0.1}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects decay_rate > 1" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Event", decay_rate: 1.5}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects decay_rate < 0" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Event", decay_rate: -0.1}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "rejects empty content" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: ""}]}
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end

    test "category is optional" do
      input = %{
        id: "test",
        memory: %{entries: [%{content: "Event", category: "conversations"}]}
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert hd(result.memory.entries).category == "conversations"
    end
  end

  describe "knowledge_item/0" do
    test "parses valid knowledge item" do
      input = %{
        id: "test",
        knowledge: [
          %{content: "Expert in Elixir", category: "skills", importance: 0.9}
        ]
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      item = hd(result.knowledge)
      assert item.content == "Expert in Elixir"
      assert item.category == "skills"
      assert item.importance == 0.9
    end

    test "importance defaults to 0.5" do
      input = %{
        id: "test",
        knowledge: [%{content: "Knows things"}]
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert hd(result.knowledge).importance == 0.5
    end

    test "category is optional" do
      input = %{
        id: "test",
        knowledge: [%{content: "Knows things"}]
      }

      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      refute Map.has_key?(hd(result.knowledge), :category)
    end

    test "rejects empty content" do
      input = %{
        id: "test",
        knowledge: [%{content: ""}]
      }

      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end
  end

  describe "defaults" do
    test "knowledge defaults to empty list" do
      input = %{id: "test"}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.knowledge == []
    end

    test "instructions defaults to empty list" do
      input = %{id: "test"}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.instructions == []
    end

    test "extensions defaults to empty map" do
      input = %{id: "test"}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.extensions == %{}
    end

    test "version defaults to 1" do
      input = %{id: "test"}
      assert {:ok, result} = Zoi.parse(Schema.character(), input)
      assert result.version == 1
    end

    test "rejects negative version" do
      input = %{id: "test", version: -1}
      assert {:error, _} = Zoi.parse(Schema.character(), input)
    end
  end

  describe "Schema sub-module new/1 and new!/1" do
    test "Trait.new/1 creates valid trait" do
      assert {:ok, trait} = Schema.Trait.new(%{name: "curious"})
      assert trait.name == "curious"
      assert trait.intensity == 0.5
    end

    test "Trait.new!/1 returns trait on success" do
      trait = Schema.Trait.new!(%{name: "patient", intensity: 0.9})
      assert trait.name == "patient"
      assert trait.intensity == 0.9
    end

    test "Trait.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid trait/, fn ->
        Schema.Trait.new!(%{})
      end
    end

    test "KnowledgeItem.new/1 creates valid item" do
      assert {:ok, item} = Schema.KnowledgeItem.new(%{content: "Knows Elixir"})
      assert item.content == "Knows Elixir"
      assert item.importance == 0.5
    end

    test "KnowledgeItem.new!/1 returns item on success" do
      item = Schema.KnowledgeItem.new!(%{content: "Expert", importance: 0.9})
      assert item.content == "Expert"
    end

    test "KnowledgeItem.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid knowledge item/, fn ->
        Schema.KnowledgeItem.new!(%{})
      end
    end

    test "MemoryEntry.new/1 creates valid entry" do
      assert {:ok, entry} = Schema.MemoryEntry.new(%{content: "Event happened"})
      assert entry.content == "Event happened"
      assert entry.decay_rate == 0.1
    end

    test "MemoryEntry.new!/1 returns entry on success" do
      entry = Schema.MemoryEntry.new!(%{content: "Test", importance: 0.8})
      assert entry.importance == 0.8
    end

    test "MemoryEntry.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid memory entry/, fn ->
        Schema.MemoryEntry.new!(%{})
      end
    end

    test "Memory.new/1 creates valid memory" do
      assert {:ok, memory} = Schema.Memory.new(%{})
      assert memory.entries == []
      assert memory.capacity == 100
    end

    test "Memory.new!/1 returns memory on success" do
      memory = Schema.Memory.new!(%{capacity: 50})
      assert memory.capacity == 50
    end

    test "Memory.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid memory/, fn ->
        Schema.Memory.new!(%{capacity: -1})
      end
    end

    test "Identity.new/1 creates valid identity" do
      assert {:ok, identity} = Schema.Identity.new(%{role: "Assistant"})
      assert identity.role == "Assistant"
      assert identity.facts == []
    end

    test "Identity.new!/1 returns identity on success" do
      identity = Schema.Identity.new!(%{age: 30})
      assert identity.age == 30
    end

    test "Identity.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid identity/, fn ->
        Schema.Identity.new!(%{age: -5})
      end
    end

    test "Personality.new/1 creates valid personality" do
      assert {:ok, personality} = Schema.Personality.new(%{})
      assert personality.traits == []
      assert personality.values == []
    end

    test "Personality.new!/1 returns personality on success" do
      personality = Schema.Personality.new!(%{values: ["honesty"]})
      assert personality.values == ["honesty"]
    end

    test "Personality.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid personality/, fn ->
        Schema.Personality.new!(%{traits: "not_a_list"})
      end
    end

    test "Voice.new/1 creates valid voice" do
      assert {:ok, voice} = Schema.Voice.new(%{})
      assert voice.tone == :casual
      assert voice.expressions == []
    end

    test "Voice.new!/1 returns voice on success" do
      voice = Schema.Voice.new!(%{tone: :formal})
      assert voice.tone == :formal
    end

    test "Voice.new!/1 raises on invalid data" do
      assert_raise ArgumentError, ~r/Invalid voice/, fn ->
        Schema.Voice.new!(%{tone: :invalid_tone})
      end
    end

    test "each sub-module exposes schema/0" do
      assert is_map(Schema.Trait.schema())
      assert is_map(Schema.KnowledgeItem.schema())
      assert is_map(Schema.MemoryEntry.schema())
      assert is_map(Schema.Memory.schema())
      assert is_map(Schema.Identity.schema())
      assert is_map(Schema.Personality.schema())
      assert is_map(Schema.Voice.schema())
    end

    test "Personality exposes trait_schema/0" do
      assert is_map(Schema.Personality.trait_schema())
    end
  end
end
