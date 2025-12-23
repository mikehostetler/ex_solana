defmodule Jido.Character.IntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Character
  alias Jido.Character.Test.AliceAssistant
  alias Jido.Character.Persistence.Memory

  setup do
    Memory.clear_all()
    :ok
  end

  describe "direct API end-to-end" do
    test "create, update, render, and persist a character" do
      {:ok, char} =
        Character.new(%{
          name: "Bob",
          description: "A helpful assistant",
          personality: %{traits: ["helpful"], values: ["accuracy"]}
        })

      assert char.name == "Bob"
      assert char.version == 1

      {:ok, updated} =
        Character.update(char, %{
          identity: %{role: "Assistant"},
          instructions: ["Be concise"]
        })

      assert updated.version == 2
      assert updated.identity.role == "Assistant"

      prompt = Character.to_system_prompt(updated)
      assert prompt =~ "Character: Bob"
      assert prompt =~ "helpful assistant"
      assert prompt =~ "Be concise"

      context = Character.to_context(updated)
      assert %ReqLLM.Context{} = context
      assert length(context.messages) == 1
      assert hd(context.messages).role == :system
    end
  end

  describe "macro-based API end-to-end" do
    test "create character from module with defaults" do
      {:ok, alice} = AliceAssistant.new()

      assert alice.name == "Alice"
      assert alice.description =~ "curious AI assistant"
      assert alice.identity.role == "Research Assistant"
      assert length(alice.personality.traits) == 3
    end

    test "override defaults at creation" do
      {:ok, alice} = AliceAssistant.new(%{name: "Alicia"})
      assert alice.name == "Alicia"
      assert alice.identity.role == "Research Assistant"
    end

    test "save and retrieve via adapter" do
      {:ok, alice} = AliceAssistant.new()
      {:ok, saved} = AliceAssistant.save(alice)

      {:ok, retrieved} = Memory.get(AliceAssistant.definition(), saved.id)
      assert retrieved.name == "Alice"
    end

    test "full workflow: create, update, save, retrieve" do
      {:ok, alice} = AliceAssistant.new()
      original_id = alice.id

      {:ok, alice} =
        AliceAssistant.update(alice, %{
          memory: %{
            entries: [
              %{content: "User is learning Elixir", importance: 0.8}
            ],
            capacity: 100
          }
        })

      assert alice.version == 2

      {:ok, _} = AliceAssistant.save(alice)

      {:ok, retrieved} = Memory.get(AliceAssistant.definition(), original_id)
      assert length(retrieved.memory.entries) == 1
    end

    test "render to LLM context includes all sections" do
      {:ok, alice} = AliceAssistant.new()

      prompt = AliceAssistant.to_system_prompt(alice)

      assert prompt =~ "# Character: Alice"
      assert prompt =~ "curious AI assistant"
      assert prompt =~ "## Identity"
      assert prompt =~ "Research Assistant"
      assert prompt =~ "## Personality"
      assert prompt =~ "curious (high)"
      assert prompt =~ "accuracy"
      assert prompt =~ "## Voice"
      assert prompt =~ "Warm"
      assert prompt =~ "## Knowledge"
      assert prompt =~ "Elixir"
      assert prompt =~ "## Instructions"
      assert prompt =~ "cite sources"
    end

    test "to_context returns valid ReqLLM.Context" do
      {:ok, alice} = AliceAssistant.new()

      context = AliceAssistant.to_context(alice)

      assert {:ok, _} = ReqLLM.Context.validate(context)

      assert length(context.messages) == 1
      [msg] = context.messages
      assert msg.role == :system
    end
  end

  describe "character evolution" do
    test "multiple updates preserve history via version" do
      {:ok, char} = Character.new(%{name: "Evolving"})

      {:ok, v2} = Character.update(char, %{description: "First update"})
      {:ok, v3} = Character.update(v2, %{description: "Second update"})
      {:ok, v4} = Character.update(v3, %{description: "Third update"})

      assert v4.version == 4
      assert v4.description == "Third update"
      assert v4.name == "Evolving"
    end
  end
end
