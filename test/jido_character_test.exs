defmodule Jido.CharacterTest do
  use ExUnit.Case, async: true

  # Ensure module is loaded before function_exported? checks
  require Jido.Character

  describe "module exports" do
    test "exports new/1" do
      Code.ensure_loaded!(Jido.Character)
      assert function_exported?(Jido.Character, :new, 1)
    end

    test "exports update/2" do
      assert function_exported?(Jido.Character, :update, 2)
    end

    test "exports validate/1" do
      assert function_exported?(Jido.Character, :validate, 1)
    end

    test "exports to_context/1" do
      assert function_exported?(Jido.Character, :to_context, 1)
    end

    test "exports to_context/2" do
      assert function_exported?(Jido.Character, :to_context, 2)
    end

    test "exports to_system_prompt/1" do
      assert function_exported?(Jido.Character, :to_system_prompt, 1)
    end

    test "exports to_system_prompt/2" do
      assert function_exported?(Jido.Character, :to_system_prompt, 2)
    end

    test "provides __using__/1 macro" do
      assert Keyword.has_key?(Jido.Character.__info__(:macros), :__using__)
    end
  end
end
