defmodule JidoTest.HTN.Domain.VisualizeTest do
  use ExUnit.Case, async: true

  alias Jido.HTN.Domain
  alias Jido.HTN.Visualize

  defmodule TestAction do
    @moduledoc false
    def run(_params, _state, _context), do: {:ok, %{}}
  end

  defmodule TestPredicates do
    @moduledoc false
    def has_balance?(state), do: state.balance > 0
    def is_ready?(state), do: state.ready == true
    def check_status(state), do: state.status == :active
  end

  defmodule TestTransformers do
    @moduledoc false
    def add_amount(state), do: Map.update(state, :amount, 0, &(&1 + 10))
    def reset_state(state), do: %{state | status: :reset}
  end

  describe "generate_mermaid/1" do
    test "generates basic mermaid diagram" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "graph TD"
      assert result =~ "node_root"
      assert result =~ "node_task1"
    end

    test "labels edges with string callback names" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("balance_check", fn state -> state.balance > 0 end)
        |> Domain.compound("root",
          methods: [
            %{conditions: ["balance_check"], subtasks: ["task1"]}
          ]
        )
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "node_root -->|\"balance_check\"| node_task1"
    end

    test "labels edges with named function references (module.function/arity)" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{conditions: [&TestPredicates.has_balance?/1], subtasks: ["task1"]}
          ]
        )
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~
               "node_root -->|\"JidoTest.HTN.Domain.VisualizeTest.TestPredicates.has_balance?/1\"| node_task1"
    end

    test "labels edges with [anon_cond] for anonymous functions" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{conditions: [fn state -> state.balance > 0 end], subtasks: ["task1"]}
          ]
        )
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "[anon_cond]"
    end

    test "handles multiple conditions with mixed types" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("custom_check", fn state -> state.valid end)
        |> Domain.compound("root",
          methods: [
            %{
              conditions: [
                "custom_check",
                &TestPredicates.is_ready?/1,
                fn state -> state.status == :ok end
              ],
              subtasks: ["task1"]
            }
          ]
        )
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "custom_check"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestPredicates.is_ready?/1"
      assert result =~ "[anon_cond]"
    end

    test "labels preconditions with named functions" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction, preconditions: [&TestPredicates.check_status/1])
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Preconditions"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestPredicates.check_status/1"
    end

    test "labels effects with named functions" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction, effects: [&TestTransformers.add_amount/1])
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Effects"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestTransformers.add_amount/1"
    end

    test "labels preconditions with string callbacks" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("ready_check", fn state -> state.ready end)
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction, preconditions: [fn state -> state.ready end])
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Preconditions"
      # The function is shown as its compiled name, not as "ready_check"
      assert result =~ "Preconditions:<br/>"
    end

    test "labels effects with string callbacks" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.callback("update_state", fn state -> Map.put(state, :updated, true) end)
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction, effects: [fn state -> Map.put(state, :updated, true) end])
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Effects"
      # The function is shown as its compiled name, not as "update_state"
      assert result =~ "Effects:<br/>"
    end

    test "labels anonymous preconditions with [anon_cond]" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction,
          preconditions: [fn state -> state.value > 100 end]
        )
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Preconditions"
      assert result =~ "[anon_cond]"
    end

    test "labels anonymous effects with [anon_cond]" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction,
          effects: [fn state -> Map.put(state, :processed, true) end]
        )
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Effects"
      assert result =~ "[anon_cond]"
    end

    test "includes legend with anonymous function explanation" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root", methods: [%{subtasks: ["task1"]}])
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "Legend"
      assert result =~ "[anon_cond] = Anonymous Function"
    end

    test "handles complex domain with multiple task types" do
      domain =
        "Complex Domain"
        |> Domain.new()
        |> Domain.callback("registered_check", fn state -> state.registered end)
        |> Domain.compound("root",
          methods: [
            %{conditions: ["registered_check"], subtasks: ["process"]},
            %{conditions: [&TestPredicates.has_balance?/1], subtasks: ["fallback"]}
          ]
        )
        |> Domain.compound("process",
          methods: [
            %{
              conditions: [fn state -> state.priority == :high end],
              subtasks: ["high_priority_task"]
            }
          ]
        )
        |> Domain.primitive("high_priority_task", TestAction,
          preconditions: [&TestPredicates.is_ready?/1],
          effects: [&TestTransformers.reset_state/1]
        )
        |> Domain.primitive("fallback", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "registered_check"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestPredicates.has_balance?/1"
      assert result =~ "[anon_cond]"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestPredicates.is_ready?/1"
      assert result =~ "JidoTest.HTN.Domain.VisualizeTest.TestTransformers.reset_state/1"
    end

    test "handles empty conditions gracefully" do
      domain =
        "Test Domain"
        |> Domain.new()
        |> Domain.compound("root",
          methods: [
            %{conditions: [], subtasks: ["task1"]}
          ]
        )
        |> Domain.primitive("task1", TestAction)
        |> Domain.build!()

      result = Visualize.generate_mermaid(domain)

      assert result =~ "graph TD"
      assert result =~ "node_root"
      assert result =~ "node_task1"
    end
  end
end
