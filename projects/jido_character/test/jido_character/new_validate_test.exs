defmodule Jido.Character.NewValidateTest do
  use ExUnit.Case, async: true

  alias Jido.Character

  describe "validate/1" do
    test "valid attrs with id passes" do
      attrs = %{id: "test-char"}
      assert {:ok, parsed} = Character.validate(attrs)
      assert parsed.id == "test-char"
    end

    test "missing id fails" do
      assert {:error, errors} = Character.validate(%{name: "Bob"})
      assert is_list(errors)
    end

    test "applies defaults for optional fields" do
      attrs = %{id: "test"}
      {:ok, parsed} = Character.validate(attrs)
      assert parsed.knowledge == []
      assert parsed.instructions == []
      assert parsed.extensions == %{}
      assert parsed.version == 1
    end
  end

  describe "new/0" do
    test "creates character with generated id" do
      assert {:ok, char} = Character.new()
      assert is_binary(char.id)
      assert String.length(char.id) > 0
    end

    test "sets created_at and updated_at" do
      {:ok, char} = Character.new()
      assert %DateTime{} = char.created_at
      assert %DateTime{} = char.updated_at
    end

    test "sets version to 1" do
      {:ok, char} = Character.new()
      assert char.version == 1
    end
  end

  describe "new/1" do
    test "accepts custom attrs" do
      {:ok, char} = Character.new(%{name: "Bob", description: "A test character"})
      assert char.name == "Bob"
      assert char.description == "A test character"
    end

    test "preserves explicit id" do
      {:ok, char} = Character.new(%{id: "custom-id"})
      assert char.id == "custom-id"
    end

    test "handles string keys" do
      {:ok, char} = Character.new(%{"id" => "string-key-id"})
      assert char.id == "string-key-id"
    end

    test "validates nested personality" do
      {:ok, char} =
        Character.new(%{
          personality: %{
            traits: ["curious", %{name: "helpful", intensity: 0.8}],
            values: ["honesty"]
          }
        })

      assert length(char.personality.traits) == 2
    end
  end

  describe "new!/1" do
    test "returns character on success" do
      char = Character.new!(%{name: "Bob"})
      assert char.name == "Bob"
      assert is_binary(char.id)
    end

    test "raises ArgumentError on invalid data" do
      assert_raise ArgumentError, ~r/Invalid character/, fn ->
        Character.new!(%{id: ""})
      end
    end

    test "with no args creates valid character" do
      char = Character.new!()
      assert is_binary(char.id)
      assert char.version == 1
    end
  end
end
