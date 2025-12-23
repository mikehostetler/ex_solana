defmodule Jido.BehaviorTree.Nodes.ActionTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Nodes.Action
  alias Jido.BehaviorTree.{Tick, Blackboard}

  # Define a simple test action
  defmodule SuccessAction do
    use Jido.Action,
      name: "success_action",
      description: "An action that always succeeds",
      schema: [
        input: [type: :string, required: false]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{result: "success", input: params[:input]}}
    end
  end

  defmodule FailureAction do
    use Jido.Action,
      name: "failure_action",
      description: "An action that always fails",
      schema: []

    @impl true
    def run(_params, _context) do
      {:error, "action failed"}
    end
  end

  describe "new/3" do
    test "creates an action node with module" do
      action = Action.new(SuccessAction)

      assert %Action{action_module: SuccessAction, params: %{}, context: %{}} = action
    end

    test "creates an action node with params" do
      action = Action.new(SuccessAction, %{input: "test"})

      assert action.params == %{input: "test"}
    end

    test "creates an action node with context" do
      action = Action.new(SuccessAction, %{}, %{user_id: 123})

      assert action.context == %{user_id: 123}
    end
  end

  describe "tick/2" do
    test "returns success when action succeeds" do
      action = Action.new(SuccessAction, %{input: "hello"})
      tick = Tick.new(Blackboard.new())

      {status, updated} = Action.tick(action, tick)

      assert status == :success
      assert updated.result == %{result: "success", input: "hello"}
    end

    test "returns error when action fails" do
      action = Action.new(FailureAction)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Action.tick(action, tick)

      assert {:error, _reason} = status
    end

    test "resolves blackboard values in params" do
      action = Action.new(SuccessAction, %{input: {:from_blackboard, :user_input}})
      blackboard = Blackboard.new(%{user_input: "from blackboard"})
      tick = Tick.new(blackboard)

      {status, updated} = Action.tick(action, tick)

      assert status == :success
      assert updated.result.input == "from blackboard"
    end
  end

  describe "halt/1" do
    test "clears the result" do
      action = %Action{
        action_module: SuccessAction,
        params: %{},
        context: %{},
        result: %{some: "result"}
      }

      halted = Action.halt(action)
      assert halted.result == nil
    end
  end

  describe "schema/0" do
    test "returns the Zoi schema" do
      schema = Action.schema()
      assert is_struct(schema, Zoi.Types.Struct)
    end
  end
end
