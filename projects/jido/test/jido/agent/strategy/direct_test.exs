defmodule JidoTest.Agent.Strategy.DirectTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.Direct
  alias Jido.Agent.Directive
  alias Jido.Agent.Internal
  alias Jido.Instruction

  # Test actions
  defmodule SimpleAction do
    use Jido.Action,
      name: "simple_action",
      schema: [
        value: [type: :integer, required: true]
      ]

    def run(%{value: value}, _context) do
      {:ok, %{result: value * 2}}
    end
  end

  defmodule ContextAwareAction do
    use Jido.Action,
      name: "context_aware_action"

    def run(_params, context) do
      state = Map.get(context, :state, %{})
      {:ok, %{saw_state: state}}
    end
  end

  defmodule FailingAction do
    use Jido.Action,
      name: "failing_action"

    def run(_params, _context) do
      {:error, "Intentional failure"}
    end
  end

  defmodule DirectiveAction do
    use Jido.Action,
      name: "directive_action"

    def run(%{directive_type: :emit}, _context) do
      {:ok, %{emitted: true}, Directive.emit(%{type: "test.event"})}
    end

    def run(%{directive_type: :schedule}, _context) do
      {:ok, %{scheduled: true}, Directive.schedule(1000, :tick)}
    end

    def run(%{directive_type: :stop}, _context) do
      {:ok, %{stopping: true}, Directive.stop(:shutdown)}
    end

    def run(%{directive_type: :multiple}, _context) do
      directives = [
        Directive.emit(%{type: "event.1"}),
        Directive.emit(%{type: "event.2"}),
        Directive.schedule(500, :reminder)
      ]

      {:ok, %{count: 3}, directives}
    end
  end

  defmodule SetStateAction do
    use Jido.Action,
      name: "set_state_action"

    def run(_params, _context) do
      {:ok, %{primary: "from_run"}, %Internal.SetState{attrs: %{internal: "from_set_state"}}}
    end
  end

  defmodule MixedEffectsAction do
    use Jido.Action,
      name: "mixed_effects_action"

    def run(_params, _context) do
      effects = [
        %Internal.SetState{attrs: %{internal_key: "value"}},
        Directive.emit(%{type: "mixed.event"})
      ]

      {:ok, %{mixed: true}, effects}
    end
  end

  describe "cmd/3 basic execution" do
    setup do
      agent = %Agent{
        id: "test-agent",
        name: "test",
        state: %{initial: true}
      }

      ctx = %{agent_module: __MODULE__, strategy_opts: []}
      {:ok, agent: agent, ctx: ctx}
    end

    test "executes single instruction and merges result", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: SimpleAction, params: %{value: 21}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.result == 42
      assert updated.state.initial == true
      assert directives == []
    end

    test "executes multiple instructions in sequence", %{agent: agent, ctx: ctx} do
      {:ok, inst1} = Instruction.new(%{action: SimpleAction, params: %{value: 5}})
      {:ok, inst2} = Instruction.new(%{action: SimpleAction, params: %{value: 10}})

      {updated, directives} = Direct.cmd(agent, [inst1, inst2], ctx)

      # Last instruction's result wins for overlapping keys
      assert updated.state.result == 20
      assert updated.state.initial == true
      assert directives == []
    end

    test "injects agent state into instruction context", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: ContextAwareAction, params: %{}})
      {updated, _directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.saw_state == %{initial: true}
    end

    test "returns error directive on instruction failure", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: FailingAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # Agent state unchanged on failure
      assert updated.state == agent.state
      # Error directive emitted
      assert [%Directive.Error{context: :instruction, error: error}] = directives
      assert error.message == "Instruction failed"
    end

    test "handles empty instruction list", %{agent: agent, ctx: ctx} do
      {updated, directives} = Direct.cmd(agent, [], ctx)

      assert updated == agent
      assert directives == []
    end
  end

  describe "cmd/3 with directives" do
    setup do
      agent = %Agent{id: "test", name: "test", state: %{}}
      ctx = %{agent_module: __MODULE__, strategy_opts: []}
      {:ok, agent: agent, ctx: ctx}
    end

    test "returns emit directive from action", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :emit}})

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.emitted == true
      assert [%Directive.Emit{signal: signal}] = directives
      assert signal.type == "test.event"
    end

    test "returns schedule directive from action", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :schedule}})

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.scheduled == true
      assert [%Directive.Schedule{delay_ms: 1000, message: :tick}] = directives
    end

    test "returns stop directive from action", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :stop}})

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.stopping == true
      assert [%Directive.Stop{reason: :shutdown}] = directives
    end

    test "returns multiple directives from action", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :multiple}})

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.count == 3
      assert length(directives) == 3

      assert [
               %Directive.Emit{signal: %{type: "event.1"}},
               %Directive.Emit{signal: %{type: "event.2"}},
               %Directive.Schedule{delay_ms: 500, message: :reminder}
             ] = directives
    end

    test "accumulates directives across multiple instructions", %{agent: agent, ctx: ctx} do
      {:ok, inst1} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :emit}})

      {:ok, inst2} =
        Instruction.new(%{action: DirectiveAction, params: %{directive_type: :schedule}})

      {_updated, directives} = Direct.cmd(agent, [inst1, inst2], ctx)

      assert length(directives) == 2
      assert [%Directive.Emit{}, %Directive.Schedule{}] = directives
    end
  end

  describe "cmd/3 with internal effects" do
    setup do
      agent = %Agent{id: "test", name: "test", state: %{existing: "value"}}
      ctx = %{agent_module: __MODULE__, strategy_opts: []}
      {:ok, agent: agent, ctx: ctx}
    end

    test "applies Internal.SetState to agent state", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: SetStateAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # Both run result and SetState applied
      assert updated.state.primary == "from_run"
      assert updated.state.internal == "from_set_state"
      assert updated.state.existing == "value"
      # SetState is internal, not returned as directive
      assert directives == []
    end

    test "separates internal effects from external directives", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: MixedEffectsAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # Run result merged
      assert updated.state.mixed == true
      # Internal SetState applied
      assert updated.state.internal_key == "value"
      # Only external directive returned
      assert [%Directive.Emit{signal: %{type: "mixed.event"}}] = directives
    end
  end

  describe "init/2 and tick/2 defaults" do
    test "init/2 returns agent unchanged with no directives" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      ctx = %{agent_module: __MODULE__, strategy_opts: []}

      {returned_agent, directives} = Direct.init(agent, ctx)

      assert returned_agent == agent
      assert directives == []
    end

    test "tick/2 returns agent unchanged with no directives" do
      agent = %Agent{id: "test", name: "test", state: %{}}
      ctx = %{agent_module: __MODULE__, strategy_opts: []}

      {returned_agent, directives} = Direct.tick(agent, ctx)

      assert returned_agent == agent
      assert directives == []
    end
  end

  describe "internal effects" do
    defmodule ReplaceStateAction do
      use Jido.Action, name: "replace_state_action"

      def run(_params, _context) do
        {:ok, %{from_run: true}, Internal.replace_state(%{replaced: true, fresh: "state"})}
      end
    end

    defmodule DeleteKeysAction do
      use Jido.Action, name: "delete_keys_action"

      def run(_params, _context) do
        {:ok, %{deleted: true}, Internal.delete_keys([:temp, :cache])}
      end
    end

    defmodule SetPathAction do
      use Jido.Action, name: "set_path_action"

      def run(%{path: path, value: value}, _context) do
        {:ok, %{path_set: true}, Internal.set_path(path, value)}
      end
    end

    defmodule DeletePathAction do
      use Jido.Action, name: "delete_path_action"

      def run(%{path: path}, _context) do
        {:ok, %{path_deleted: true}, Internal.delete_path(path)}
      end
    end

    setup do
      agent = %Agent{
        id: "test",
        name: "test",
        state: %{
          existing: "value",
          temp: "temporary",
          cache: %{data: "cached"},
          config: %{timeout: 1000, retries: 3}
        }
      }

      ctx = %{agent_module: __MODULE__, strategy_opts: []}
      {:ok, agent: agent, ctx: ctx}
    end

    test "ReplaceState replaces state wholesale", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: ReplaceStateAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # Run result is NOT merged (replace happens after)
      # The order is: apply_result (merge run result) then apply_effects
      # So from_run is merged first, then state is replaced
      assert updated.state == %{replaced: true, fresh: "state"}
      assert directives == []
    end

    test "DeleteKeys removes specified top-level keys", %{agent: agent, ctx: ctx} do
      {:ok, instruction} = Instruction.new(%{action: DeleteKeysAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      # Run result merged first
      assert updated.state.deleted == true
      # Then keys deleted
      refute Map.has_key?(updated.state, :temp)
      refute Map.has_key?(updated.state, :cache)
      # Other keys preserved
      assert updated.state.existing == "value"
      assert updated.state.config == %{timeout: 1000, retries: 3}
      assert directives == []
    end

    test "SetPath sets value at nested path", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{
          action: SetPathAction,
          params: %{path: [:config, :timeout], value: 5000}
        })

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.path_set == true
      assert updated.state.config.timeout == 5000
      # Other nested keys preserved
      assert updated.state.config.retries == 3
      assert directives == []
    end

    test "DeletePath removes value at nested path", %{agent: agent, ctx: ctx} do
      {:ok, instruction} =
        Instruction.new(%{
          action: DeletePathAction,
          params: %{path: [:config, :retries]}
        })

      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.path_deleted == true
      refute Map.has_key?(updated.state.config, :retries)
      # Other nested keys preserved
      assert updated.state.config.timeout == 1000
      assert directives == []
    end

    test "multiple internal effects applied in order", %{ctx: ctx} do
      # Start with empty state
      agent = %Agent{id: "test", name: "test", state: %{}}

      defmodule MultiEffectInternalAction do
        use Jido.Action, name: "multi_effect_internal"

        def run(_params, _context) do
          effects = [
            Internal.set_state(%{a: 1, b: 2}),
            Internal.set_path([:nested, :value], "deep"),
            Internal.delete_keys([:b])
          ]

          {:ok, %{ran: true}, effects}
        end
      end

      {:ok, instruction} = Instruction.new(%{action: MultiEffectInternalAction, params: %{}})
      {updated, directives} = Direct.cmd(agent, [instruction], ctx)

      assert updated.state.ran == true
      assert updated.state.a == 1
      refute Map.has_key?(updated.state, :b)
      assert updated.state.nested.value == "deep"
      assert directives == []
    end
  end
end
