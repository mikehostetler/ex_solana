defmodule JidoTest.SkillTestAction do
  @moduledoc false
  use Jido.Action,
    name: "skill_test_action",
    schema: []

  def run(_params, _context), do: {:ok, %{}}
end

defmodule JidoTest.SkillTestAnotherAction do
  @moduledoc false
  use Jido.Action,
    name: "skill_test_another_action",
    schema: [value: [type: :integer, default: 0]]

  def run(%{value: value}, _context), do: {:ok, %{value: value}}
end

defmodule JidoTest.NotAnActionModule do
  @moduledoc false
  def some_function, do: :ok
end

defmodule JidoTest.TestActions do
  @moduledoc false

  alias Jido.Action
  alias Jido.Agent.{Directive, Internal}

  defmodule BasicAction do
    @moduledoc false
    use Action,
      name: "basic_action",
      description: "A basic action for testing",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      {:ok, %{value: value}}
    end
  end

  defmodule NoSchema do
    @moduledoc false
    use Action,
      name: "no_schema",
      description: "Action with no schema"

    def run(%{value: value}, _context), do: {:ok, %{result: value + 2}}
    def run(_params, _context), do: {:ok, %{result: "No params"}}
  end

  defmodule Add do
    @moduledoc false
    use Action,
      name: "add",
      description: "Adds amount to value",
      schema: [
        value: [type: :integer, required: true],
        amount: [type: :integer, default: 1]
      ]

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{value: value + amount}}
    end
  end

  defmodule EmitAction do
    @moduledoc false
    use Action,
      name: "emit_action",
      description: "Action that returns an emit effect"

    def run(_params, _context) do
      signal = %{type: "test.emitted", data: %{value: 42}}
      {:ok, %{emitted: true}, Directive.emit(signal)}
    end
  end

  defmodule MultiEffectAction do
    @moduledoc false
    use Action,
      name: "multi_effect_action",
      description: "Action that returns multiple effects"

    def run(_params, _context) do
      effects = [
        Directive.emit(%{type: "event.1"}),
        Directive.schedule(1000, :check)
      ]

      {:ok, %{triggered: true}, effects}
    end
  end

  defmodule SetStateAction do
    @moduledoc false
    use Action,
      name: "set_state_action",
      description: "Action that uses Internal.SetState"

    def run(_params, _context) do
      {:ok, %{primary: "result"}, %Internal.SetState{attrs: %{extra: "state"}}}
    end
  end

  defmodule ReplaceStateAction do
    @moduledoc false
    use Action,
      name: "replace_state_action",
      description: "Action that uses Internal.ReplaceState"

    def run(_params, _context) do
      {:ok, %{}, %Internal.ReplaceState{state: %{replaced: true, fresh: "state"}}}
    end
  end

  defmodule DeleteKeysAction do
    @moduledoc false
    use Action,
      name: "delete_keys_action",
      description: "Action that uses Internal.DeleteKeys"

    def run(_params, _context) do
      {:ok, %{}, %Internal.DeleteKeys{keys: [:to_delete, :also_delete]}}
    end
  end

  defmodule SetPathAction do
    @moduledoc false
    use Action,
      name: "set_path_action",
      description: "Action that uses Internal.SetPath"

    def run(_params, _context) do
      {:ok, %{}, %Internal.SetPath{path: [:nested, :deep, :value], value: 42}}
    end
  end

  defmodule DeletePathAction do
    @moduledoc false
    use Action,
      name: "delete_path_action",
      description: "Action that uses Internal.DeletePath"

    def run(_params, _context) do
      {:ok, %{}, %Internal.DeletePath{path: [:nested, :to_remove]}}
    end
  end
end
