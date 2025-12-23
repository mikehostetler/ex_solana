defmodule Jido.Character.DefinitionTest do
  use ExUnit.Case, async: true

  alias Jido.Character.Definition

  describe "struct creation" do
    test "creates with required module field" do
      defn = %Definition{module: MyApp.TestCharacter}
      assert defn.module == MyApp.TestCharacter
    end

    test "has default empty extensions" do
      defn = %Definition{module: __MODULE__}
      assert defn.extensions == []
    end

    test "has default empty defaults map" do
      defn = %Definition{module: __MODULE__}
      assert defn.defaults == %{}
    end

    test "has default Memory adapter" do
      defn = %Definition{module: __MODULE__}
      assert defn.adapter == Jido.Character.Persistence.Memory
    end

    test "has default empty adapter_opts" do
      defn = %Definition{module: __MODULE__}
      assert defn.adapter_opts == []
    end

    test "accepts custom values" do
      defn = %Definition{
        module: __MODULE__,
        extensions: [:memory, :goals],
        defaults: %{name: "Test"},
        adapter: SomeAdapter,
        adapter_opts: [table: :test]
      }

      assert defn.extensions == [:memory, :goals]
      assert defn.defaults == %{name: "Test"}
      assert defn.adapter == SomeAdapter
      assert defn.adapter_opts == [table: :test]
    end
  end

  describe "enforce: true" do
    test "raises if module not provided" do
      assert_raise ArgumentError, fn ->
        struct!(Definition, %{})
      end
    end
  end

  describe "new/1" do
    test "creates definition with required module" do
      assert {:ok, defn} = Definition.new(%{module: __MODULE__})
      assert defn.module == __MODULE__
      assert defn.extensions == []
      assert defn.defaults == %{}
      assert defn.adapter == Jido.Character.Persistence.Memory
      assert defn.adapter_opts == []
    end

    test "creates definition with custom values" do
      attrs = %{
        module: __MODULE__,
        extensions: [:memory, :goals],
        defaults: %{name: "Test"},
        adapter: SomeAdapter,
        adapter_opts: [table: :test]
      }

      assert {:ok, defn} = Definition.new(attrs)
      assert defn.extensions == [:memory, :goals]
      assert defn.defaults == %{name: "Test"}
      assert defn.adapter == SomeAdapter
      assert defn.adapter_opts == [table: :test]
    end

    test "returns error for missing module" do
      assert {:error, _} = Definition.new(%{})
    end
  end

  describe "new!/1" do
    test "creates definition and returns struct directly" do
      defn = Definition.new!(%{module: __MODULE__})
      assert defn.module == __MODULE__
    end

    test "raises on invalid input" do
      assert_raise ArgumentError, fn ->
        Definition.new!(%{})
      end
    end
  end

  describe "schema/0" do
    test "returns the Zoi schema" do
      schema = Definition.schema()
      assert %Zoi.Types.Struct{} = schema
    end
  end
end
