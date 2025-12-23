defmodule Jido.Character.MacroTest do
  use ExUnit.Case, async: true

  alias Jido.Character.Test.SimpleCharacter
  alias Jido.Character.Test.ConfiguredCharacter
  alias Jido.Character.Test.CustomRendererCharacter
  alias Jido.Character.Definition

  describe "definition/0" do
    test "returns a Definition struct" do
      assert %Definition{} = SimpleCharacter.definition()
    end

    test "contains the correct module" do
      assert SimpleCharacter.definition().module == SimpleCharacter
    end
  end

  describe "extensions/0" do
    test "returns empty list by default" do
      assert SimpleCharacter.extensions() == []
    end

    test "returns configured extensions" do
      assert ConfiguredCharacter.extensions() == [:memory, :goals]
    end
  end

  describe "defaults/0" do
    test "returns configured defaults" do
      defaults = SimpleCharacter.defaults()
      assert defaults.name == "Simple"
      assert defaults.personality.values == ["helpfulness"]
    end
  end

  describe "adapter/0 and adapter_opts/0" do
    test "returns default Memory adapter" do
      assert SimpleCharacter.adapter() == Jido.Character.Persistence.Memory
    end

    test "returns configured adapter" do
      assert ConfiguredCharacter.adapter() == SomeTestAdapter
    end

    test "returns configured adapter opts" do
      assert ConfiguredCharacter.adapter_opts() == [table: :test_chars]
    end
  end

  describe "new/0 and new/1" do
    test "creates character with defaults merged" do
      {:ok, char} = SimpleCharacter.new()
      assert char.name == "Simple"
      assert char.personality.values == ["helpfulness"]
    end

    test "allows overriding defaults" do
      {:ok, char} = SimpleCharacter.new(%{name: "Custom"})
      assert char.name == "Custom"
    end

    test "has generated id" do
      {:ok, char} = SimpleCharacter.new()
      assert is_binary(char.id)
    end
  end

  describe "update/2" do
    test "delegates to Jido.Character.update/2" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.update(char, %{name: "Updated"})
      assert updated.name == "Updated"
      assert updated.version == char.version + 1
    end
  end

  describe "renderer/0 and renderer_opts/0" do
    test "returns default Markdown renderer" do
      assert SimpleCharacter.renderer() == Jido.Character.Context.Renderer
    end

    test "returns configured renderer" do
      assert CustomRendererCharacter.renderer() == SomeTestRenderer
    end

    test "returns configured renderer_opts" do
      assert CustomRendererCharacter.renderer_opts() == [prefix: "Module"]
    end
  end

  describe "to_context/2 with custom renderer" do
    test "uses module's configured renderer" do
      {:ok, char} = CustomRendererCharacter.new()
      context = CustomRendererCharacter.to_context(char)

      assert get_message_text(context) == "Module: CustomRendered"
    end

    test "allows per-call renderer override" do
      {:ok, char} = CustomRendererCharacter.new()
      context = CustomRendererCharacter.to_context(char, renderer: Jido.Character.Context.Renderer)

      assert get_message_text(context) =~ "# Character: CustomRendered"
    end
  end

  describe "to_system_prompt/2 with custom renderer" do
    test "uses module's configured renderer" do
      {:ok, char} = CustomRendererCharacter.new()
      prompt = CustomRendererCharacter.to_system_prompt(char)

      assert prompt == "Module: CustomRendered"
    end

    test "allows per-call renderer_opts override" do
      {:ok, char} = CustomRendererCharacter.new()
      prompt = CustomRendererCharacter.to_system_prompt(char, renderer_opts: [prefix: "Override"])

      assert prompt == "Override: CustomRendered"
    end
  end

  describe "helper methods" do
    test "add_knowledge/2,3 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_knowledge(char, "Expert in testing")

      assert [%{content: "Expert in testing"}] = updated.knowledge
    end

    test "add_instruction/2 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_instruction(char, "Always be helpful")

      assert "Always be helpful" in updated.instructions
    end

    test "add_memory/2,3 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_memory(char, "User said hello")

      assert hd(updated.memory.entries).content == "User said hello"
    end

    test "add_trait/2,3 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_trait(char, "curious")

      assert "curious" in updated.personality.traits
    end

    test "add_value/2 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_value(char, "accuracy")

      assert "accuracy" in updated.personality.values
    end

    test "add_quirk/2 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_quirk(char, "Uses analogies")

      assert "Uses analogies" in updated.personality.quirks
    end

    test "add_expression/2 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_expression(char, "Let me think...")

      assert "Let me think..." in updated.voice.expressions
    end

    test "add_fact/2 is available" do
      {:ok, char} = SimpleCharacter.new()
      {:ok, updated} = SimpleCharacter.add_fact(char, "Has a PhD")

      assert "Has a PhD" in updated.identity.facts
    end
  end

  # Helper to extract text from message content (handles ContentPart lists)
  defp get_message_text(context) do
    msg = hd(context.messages)

    case msg.content do
      text when is_binary(text) -> text
      parts when is_list(parts) -> Enum.map_join(parts, "", &extract_text/1)
    end
  end

  defp extract_text(%{text: text}), do: text
  defp extract_text(_), do: ""
end
