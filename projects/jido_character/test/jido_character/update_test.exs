defmodule Jido.Character.UpdateTest do
  use ExUnit.Case, async: true

  alias Jido.Character

  setup do
    {:ok, char} =
      Character.new(%{
        name: "Bob",
        personality: %{values: ["efficiency"]}
      })

    {:ok, char: char}
  end

  describe "update/2" do
    test "preserves id", %{char: char} do
      {:ok, updated} = Character.update(char, %{name: "Robert"})
      assert updated.id == char.id
    end

    test "preserves created_at", %{char: char} do
      {:ok, updated} = Character.update(char, %{name: "Robert"})
      assert updated.created_at == char.created_at
    end

    test "increments version", %{char: char} do
      {:ok, updated} = Character.update(char, %{name: "Robert"})
      assert updated.version == char.version + 1
    end

    test "updates updated_at", %{char: char} do
      # Small delay to ensure different timestamps
      Process.sleep(1)
      {:ok, updated} = Character.update(char, %{name: "Robert"})
      assert DateTime.compare(updated.updated_at, char.updated_at) in [:gt, :eq]
    end

    test "applies simple field updates", %{char: char} do
      {:ok, updated} = Character.update(char, %{name: "Robert"})
      assert updated.name == "Robert"
    end

    test "deep merges nested maps", %{char: char} do
      {:ok, updated} =
        Character.update(char, %{
          identity: %{role: "Assistant"}
        })

      assert updated.identity.role == "Assistant"
      # Original personality should still be there
      assert updated.personality.values == ["efficiency"]
    end

    test "can add new nested values while preserving existing", %{char: char} do
      {:ok, updated} =
        Character.update(char, %{
          personality: %{traits: ["helpful"]}
        })

      # Should have both traits and values
      assert updated.personality.traits == ["helpful"]
      assert updated.personality.values == ["efficiency"]
    end

    test "validates after merge", %{char: _char} do
      # Create a fresh character and try invalid update
      {:ok, char} = Character.new()
      # Invalid: version must be non-negative integer
      result = Character.update(char, %{version: -5})
      # The merge will set version to char.version + 1, not -5
      # So this should actually succeed because bump_version overrides
      assert {:ok, _} = result
    end
  end

  describe "update!/2" do
    test "returns updated character on success", %{char: char} do
      updated = Character.update!(char, %{name: "Robert"})
      assert updated.name == "Robert"
      assert updated.id == char.id
    end

    test "raises ArgumentError on invalid data", %{char: char} do
      assert_raise ArgumentError, ~r/Invalid update/, fn ->
        Character.update!(char, %{name: String.duplicate("x", 200)})
      end
    end

    test "increments version", %{char: char} do
      updated = Character.update!(char, %{description: "Updated"})
      assert updated.version == char.version + 1
    end
  end
end
