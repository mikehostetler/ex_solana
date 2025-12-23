defmodule Jido.Character.Persistence.MemoryTest do
  use ExUnit.Case, async: false

  alias Jido.Character.Persistence.Memory
  alias Jido.Character.Test.SimpleCharacter

  setup do
    Memory.clear_all()
    :ok
  end

  describe "save/2" do
    test "saves a character" do
      {:ok, char} = SimpleCharacter.new(%{id: "test-1"})
      defn = SimpleCharacter.definition()

      assert {:ok, saved} = Memory.save(defn, char)
      assert saved.id == "test-1"
    end

    test "overwrites existing character with same id" do
      {:ok, char} = SimpleCharacter.new(%{id: "test-2", name: "First"})
      defn = SimpleCharacter.definition()

      {:ok, _} = Memory.save(defn, char)

      {:ok, updated} = SimpleCharacter.update(char, %{name: "Second"})
      {:ok, _} = Memory.save(defn, updated)

      {:ok, retrieved} = Memory.get(defn, "test-2")
      assert retrieved.name == "Second"
    end
  end

  describe "get/2" do
    test "retrieves a saved character" do
      {:ok, char} = SimpleCharacter.new(%{id: "get-1"})
      defn = SimpleCharacter.definition()

      {:ok, _} = Memory.save(defn, char)

      assert {:ok, retrieved} = Memory.get(defn, "get-1")
      assert retrieved.id == "get-1"
      assert retrieved.name == "Simple"
    end

    test "returns error for non-existent character" do
      defn = SimpleCharacter.definition()
      assert {:error, :not_found} = Memory.get(defn, "nonexistent")
    end
  end

  describe "delete/2" do
    test "deletes a character" do
      {:ok, char} = SimpleCharacter.new(%{id: "del-1"})
      defn = SimpleCharacter.definition()

      {:ok, _} = Memory.save(defn, char)
      assert :ok = Memory.delete(defn, "del-1")
      assert {:error, :not_found} = Memory.get(defn, "del-1")
    end

    test "succeeds even if character doesn't exist" do
      defn = SimpleCharacter.definition()
      assert :ok = Memory.delete(defn, "never-existed")
    end
  end

  describe "save/1 via macro-generated function" do
    test "saves using configured adapter" do
      {:ok, char} = SimpleCharacter.new(%{id: "macro-save"})

      assert {:ok, saved} = SimpleCharacter.save(char)
      assert saved.id == "macro-save"

      {:ok, retrieved} = Memory.get(SimpleCharacter.definition(), "macro-save")
      assert retrieved.id == "macro-save"
    end
  end
end
