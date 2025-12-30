defmodule JidoTest.Agent.InternalTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Internal
  alias Jido.Agent.Internal.{SetState, ReplaceState, DeleteKeys, SetPath, DeletePath}

  describe "SetState struct" do
    test "creates a SetState effect with attrs" do
      effect = %SetState{attrs: %{key: "value"}}

      assert effect.attrs == %{key: "value"}
    end

    test "has schema defined" do
      schema = SetState.schema()
      assert schema
    end
  end

  describe "ReplaceState struct" do
    test "creates a ReplaceState effect with state" do
      effect = %ReplaceState{state: %{new: "state"}}

      assert effect.state == %{new: "state"}
    end

    test "has schema defined" do
      schema = ReplaceState.schema()
      assert schema
    end
  end

  describe "DeleteKeys struct" do
    test "creates a DeleteKeys effect with keys list" do
      effect = %DeleteKeys{keys: [:key1, :key2]}

      assert effect.keys == [:key1, :key2]
    end

    test "has schema defined" do
      schema = DeleteKeys.schema()
      assert schema
    end
  end

  describe "SetPath struct" do
    test "creates a SetPath effect with path and value" do
      effect = %SetPath{path: [:config, :timeout], value: 5000}

      assert effect.path == [:config, :timeout]
      assert effect.value == 5000
    end

    test "has schema defined" do
      schema = SetPath.schema()
      assert schema
    end
  end

  describe "DeletePath struct" do
    test "creates a DeletePath effect with path" do
      effect = %DeletePath{path: [:temp, :cache]}

      assert effect.path == [:temp, :cache]
    end

    test "has schema defined" do
      schema = DeletePath.schema()
      assert schema
    end
  end

  describe "set_state/1" do
    test "creates SetState effect from map" do
      effect = Internal.set_state(%{status: :running})

      assert %SetState{attrs: %{status: :running}} = effect
    end
  end

  describe "replace_state/1" do
    test "creates ReplaceState effect from map" do
      effect = Internal.replace_state(%{fresh: "state"})

      assert %ReplaceState{state: %{fresh: "state"}} = effect
    end
  end

  describe "delete_keys/1" do
    test "creates DeleteKeys effect from list" do
      effect = Internal.delete_keys([:temp, :cache])

      assert %DeleteKeys{keys: [:temp, :cache]} = effect
    end
  end

  describe "set_path/2" do
    test "creates SetPath effect from path and value" do
      effect = Internal.set_path([:config, :timeout], 3000)

      assert %SetPath{path: [:config, :timeout], value: 3000} = effect
    end
  end

  describe "delete_path/1" do
    test "creates DeletePath effect from path" do
      effect = Internal.delete_path([:temp, :data])

      assert %DeletePath{path: [:temp, :data]} = effect
    end
  end
end
