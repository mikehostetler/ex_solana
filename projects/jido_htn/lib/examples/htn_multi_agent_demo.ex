defmodule JidoHTN.MultiAgentDemo do
  @moduledoc """
  Demonstration of HTN-controlled agents that delegate to child agents.

  This demo shows:
  1. A coordinator agent with an HTN domain
  2. Tasks that spawn child agents using SpawnAgent directives
  3. The child agents execute their own work

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────┐
  │  CoordinatorAgent (HTN Planning)                       │
  │                                                         │
  │  HTN Domain: "order_fulfillment"                       │
  │    └── root: "fulfill_order"                           │
  │        ├── validate_order                              │
  │        ├── spawn_picker_agent  ──────┐                 │
  │        ├── spawn_packer_agent  ──────┼─► Child Agents  │
  │        └── finalize_order            │                 │
  │                                       │                 │
  └───────────────────────────────────────┼─────────────────┘
                                          │
           ┌──────────────────────────────┴──────────┐
           ▼                                         ▼
  ┌─────────────────────┐                 ┌─────────────────────┐
  │   PickerAgent       │                 │   PackerAgent       │
  │   (Simple Agent)    │                 │   (Simple Agent)    │
  │                     │                 │                     │
  │   Picks items       │                 │   Packs items       │
  └─────────────────────┘                 └─────────────────────┘
  ```

  ## Running the Demo

      iex> JidoHTN.MultiAgentDemo.run()

  Note: This demo focuses on showing how HTN planning can produce SpawnAgent
  directives. In a real system, you'd use AgentServer to actually spawn
  and manage the child agents.
  """

  alias Jido.HTN.Domain, as: D
  alias Jido.Agent.Directive

  # ===========================================================================
  # Actions
  # ===========================================================================

  defmodule Actions do
    @moduledoc "Actions for the multi-agent demo"

    defmodule ValidateOrder do
      @moduledoc "Validate an incoming order"
      use Jido.Action,
        name: "validate_order",
        description: "Validates the order data",
        schema: []

      @impl true
      def run(_params, context) do
        order_id = context.state[:order_id] || "ORD-#{:rand.uniform(10000)}"
        items = context.state[:items] || [:widget, :gadget]

        IO.puts("📋 Validating order #{order_id} with items: #{inspect(items)}")

        {:ok,
         %{
           order_validated: true,
           order_id: order_id,
           items: items,
           validation_time: DateTime.utc_now()
         }}
      end
    end

    defmodule SpawnPickerAgent do
      @moduledoc "Spawn a picker agent to pick items"
      use Jido.Action,
        name: "spawn_picker",
        description: "Spawns a picker agent",
        schema: []

      @impl true
      def run(_params, context) do
        order_id = context.state[:order_id]
        items = context.state[:items]

        IO.puts("🤖 Spawning PickerAgent for order #{order_id}")

        spawn_directive = %Directive.SpawnAgent{
          agent: JidoHTN.MultiAgentDemo.PickerAgent,
          tag: {:picker, order_id},
          opts: %{
            initial_state: %{
              order_id: order_id,
              items_to_pick: items
            }
          },
          meta: %{parent_order: order_id}
        }

        {:ok, %{picker_spawned: true, picker_tag: {:picker, order_id}}, [spawn_directive]}
      end
    end

    defmodule SpawnPackerAgent do
      @moduledoc "Spawn a packer agent to pack items"
      use Jido.Action,
        name: "spawn_packer",
        description: "Spawns a packer agent",
        schema: []

      @impl true
      def run(_params, context) do
        order_id = context.state[:order_id]

        IO.puts("📦 Spawning PackerAgent for order #{order_id}")

        spawn_directive = %Directive.SpawnAgent{
          agent: JidoHTN.MultiAgentDemo.PackerAgent,
          tag: {:packer, order_id},
          opts: %{
            initial_state: %{
              order_id: order_id
            }
          },
          meta: %{parent_order: order_id}
        }

        {:ok, %{packer_spawned: true, packer_tag: {:packer, order_id}}, [spawn_directive]}
      end
    end

    defmodule FinalizeOrder do
      @moduledoc "Finalize the order"
      use Jido.Action,
        name: "finalize_order",
        description: "Finalizes the order processing",
        schema: []

      @impl true
      def run(_params, context) do
        order_id = context.state[:order_id]

        IO.puts("✅ Order #{order_id} submitted for fulfillment")

        {:ok,
         %{
           order_finalized: true,
           status: :in_progress,
           finalized_at: DateTime.utc_now()
         }}
      end
    end

    defmodule PickItems do
      @moduledoc "Pick items from inventory"
      use Jido.Action,
        name: "pick_items",
        description: "Picks items from inventory",
        schema: []

      @impl true
      def run(_params, context) do
        items = context.state[:items_to_pick] || []
        order_id = context.state[:order_id]

        IO.puts("  🔍 Picker: Finding items #{inspect(items)} for order #{order_id}")

        {:ok, %{items_picked: items, pick_complete: true}}
      end
    end

    defmodule PackItems do
      @moduledoc "Pack items into a box"
      use Jido.Action,
        name: "pack_items",
        description: "Packs items into shipping container",
        schema: []

      @impl true
      def run(_params, context) do
        order_id = context.state[:order_id]

        IO.puts("  📦 Packer: Packing items for order #{order_id}")

        {:ok, %{items_packed: true, package_weight: 2.5}}
      end
    end
  end

  # ===========================================================================
  # HTN Domain
  # ===========================================================================

  defmodule OrderFulfillmentDomain do
    @moduledoc """
    HTN Domain for order fulfillment with child agent spawning.
    """

    alias JidoHTN.MultiAgentDemo.Actions

    def domain do
      "order_fulfillment"
      |> D.new()
      |> D.compound("fulfill_order",
        methods: [
          %{
            name: "standard_fulfillment",
            subtasks: [
              "validate_order",
              "spawn_picker",
              "spawn_packer",
              "finalize_order"
            ]
          }
        ]
      )
      |> D.primitive("validate_order", {Actions.ValidateOrder, []})
      |> D.primitive("spawn_picker", {Actions.SpawnPickerAgent, []})
      |> D.primitive("spawn_packer", {Actions.SpawnPackerAgent, []})
      |> D.primitive("finalize_order", {Actions.FinalizeOrder, []})
      |> D.allow("ValidateOrder", Actions.ValidateOrder)
      |> D.allow("SpawnPickerAgent", Actions.SpawnPickerAgent)
      |> D.allow("SpawnPackerAgent", Actions.SpawnPackerAgent)
      |> D.allow("FinalizeOrder", Actions.FinalizeOrder)
      |> D.root("fulfill_order")
      |> D.build!()
    end
  end

  # ===========================================================================
  # Agent Definitions
  # ===========================================================================

  defmodule CoordinatorAgent do
    @moduledoc "Coordinator agent that uses HTN planning for order fulfillment"
    use Jido.Agent,
      name: "coordinator_agent",
      description: "Coordinates order fulfillment using HTN planning",
      schema: [
        order_id: [type: :string, required: false],
        items: [type: {:list, :atom}, required: false]
      ]

    alias Jido.HTN
    alias JidoHTN.MultiAgentDemo.OrderFulfillmentDomain

    def fulfill_order(agent, order_id, items) do
      world_state = %{order_id: order_id, items: items}
      domain = OrderFulfillmentDomain.domain()

      case HTN.plan(domain, world_state, root_tasks: ["fulfill_order"]) do
        {:ok, plan, _mtr} ->
          execute_plan(agent, plan)

        {:ok, plan} ->
          execute_plan(agent, plan)

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp execute_plan(agent, plan) do
      Enum.reduce(plan, {agent, []}, fn {action_mod, params_kw}, {ag, dirs} ->
        params_map = Enum.into(params_kw || [], %{})

        case cmd(ag, {action_mod, params_map}) do
          {new_agent, new_dirs} ->
            {new_agent, dirs ++ new_dirs}
        end
      end)
    end
  end

  defmodule PickerAgent do
    @moduledoc "Child agent that picks items"
    use Jido.Agent,
      name: "picker_agent",
      description: "Picks items from inventory",
      schema: [
        order_id: [type: :string, required: false],
        items_to_pick: [type: {:list, :atom}, required: false]
      ]

    alias JidoHTN.MultiAgentDemo.Actions

    def pick(agent) do
      cmd(agent, Actions.PickItems)
    end
  end

  defmodule PackerAgent do
    @moduledoc "Child agent that packs items"
    use Jido.Agent,
      name: "packer_agent",
      description: "Packs items for shipping",
      schema: [
        order_id: [type: :string, required: false]
      ]

    alias JidoHTN.MultiAgentDemo.Actions

    def pack(agent) do
      cmd(agent, Actions.PackItems)
    end
  end

  # ===========================================================================
  # Demo Runner
  # ===========================================================================

  @doc """
  Run the multi-agent demo.

  Shows how HTN planning produces SpawnAgent directives that would
  create child agents in a real system.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("HTN Multi-Agent Demo: Order Fulfillment")
    IO.puts(String.duplicate("=", 70))

    # Create the coordinator agent
    coordinator = CoordinatorAgent.new()
    order_id = "ORD-#{:rand.uniform(10000)}"
    items = [:widget_a, :gadget_b, :component_c]

    IO.puts("\n📦 Order Details:")
    IO.puts("   Order ID: #{order_id}")
    IO.puts("   Items: #{inspect(items)}")

    IO.puts("\n🚀 Starting order fulfillment via HTN planning...\n")

    # Run the fulfillment
    {coordinator, directives} = CoordinatorAgent.fulfill_order(coordinator, order_id, items)

    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("📊 Results")
    IO.puts(String.duplicate("-", 70))

    IO.puts("\n📦 Coordinator Final State:")
    IO.puts("   Order ID: #{coordinator.state[:order_id]}")
    IO.puts("   Items: #{inspect(coordinator.state[:items])}")
    IO.puts("   Order Validated: #{coordinator.state[:order_validated]}")
    IO.puts("   Picker Spawned: #{coordinator.state[:picker_spawned]}")
    IO.puts("   Packer Spawned: #{coordinator.state[:packer_spawned]}")
    IO.puts("   Order Finalized: #{coordinator.state[:order_finalized]}")

    IO.puts("\n📤 Directives Produced:")

    spawn_directives =
      directives
      |> Enum.filter(fn
        %Directive.SpawnAgent{} -> true
        _ -> false
      end)

    if Enum.empty?(spawn_directives) do
      IO.puts("   (no SpawnAgent directives)")
    else
      Enum.each(spawn_directives, fn dir ->
        IO.puts("   • SpawnAgent: #{inspect(dir.agent)}")
        IO.puts("     Tag: #{inspect(dir.tag)}")
        IO.puts("     Meta: #{inspect(dir.meta)}")
      end)
    end

    IO.puts("\n💡 In a real system with AgentServer:")
    IO.puts("   - These directives would spawn actual child agents")
    IO.puts("   - Parent monitors children via the tag")
    IO.puts("   - Children can emit signals back to parent")

    # Demo the child agents independently
    IO.puts("\n" <> String.duplicate("-", 70))
    IO.puts("🔧 Simulating Child Agent Execution")
    IO.puts(String.duplicate("-", 70))

    picker = PickerAgent.new(state: %{order_id: order_id, items_to_pick: items})
    {picker, _} = PickerAgent.pick(picker)

    packer = PackerAgent.new(state: %{order_id: order_id})
    {updated_packer, _} = PackerAgent.pack(packer)

    IO.puts("\n   Picker state: items_picked = #{inspect(picker.state[:items_picked])}")
    IO.puts("   Packer state: items_packed = #{updated_packer.state[:items_packed]}")

    IO.puts("\n" <> String.duplicate("=", 70))

    {coordinator, directives}
  end
end
