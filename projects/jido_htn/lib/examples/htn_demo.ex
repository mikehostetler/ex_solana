defmodule JidoHTN.Demo do
  @moduledoc """
  Demonstration of a Jido Agent controlled via HTN planning.

  This demo shows:
  1. A parent agent with an HTN domain containing compound and primitive tasks
  2. Compound tasks that decompose into subtasks based on world state
  3. Primitive tasks that execute Jido Actions
  4. Integration with the Jido Agent Strategy system

  ## Running the Demo

      # In IEx:
      iex> JidoHTN.Demo.run()

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────┐
  │  DeliveryAgent (HTN Strategy)                          │
  │                                                         │
  │  Domain: "delivery_service"                            │
  │    └── root: "deliver_package"                         │
  │        ├── check_battery → recharge_cycle              │
  │        ├── move_to_pickup                              │
  │        ├── pickup_package                              │
  │        ├── move_to_destination                         │
  │        └── deliver_package                             │
  │                                                         │
  │  World State: %{                                       │
  │    location: :warehouse,                               │
  │    battery: 100,                                       │
  │    has_package: false,                                 │
  │    destination: :customer                              │
  │  }                                                     │
  └─────────────────────────────────────────────────────────┘
  ```
  """

  alias Jido.HTN.Domain, as: D

  # ===========================================================================
  # Actions - Primitive tasks execute these
  # ===========================================================================

  defmodule Actions do
    @moduledoc "Actions for the delivery demo"

    defmodule CheckBattery do
      @moduledoc "Check battery level and decide if recharge needed"
      use Jido.Action,
        name: "check_battery",
        description: "Checks the battery level",
        schema: []

      @impl true
      def run(_params, context) do
        battery = context.state[:battery] || 100
        {:ok, %{battery_checked: true, needs_recharge: battery < 30}}
      end
    end

    defmodule Recharge do
      @moduledoc "Recharge the battery"
      use Jido.Action,
        name: "recharge",
        description: "Recharges the battery to full",
        schema: []

      @impl true
      def run(_params, context) do
        current = context.state[:battery] || 0
        new_level = min(current + 50, 100)
        {:ok, %{battery: new_level, recharged: true}}
      end
    end

    defmodule MoveTo do
      @moduledoc "Move to a destination"
      use Jido.Action,
        name: "move_to",
        description: "Moves to a specified location",
        schema: [
          destination: [type: :atom, required: true, doc: "Target location"]
        ]

      @impl true
      def run(params, context) do
        dest = params.destination
        battery = context.state[:battery] || 100
        # Moving costs 10 battery
        new_battery = max(battery - 10, 0)
        {:ok, %{location: dest, battery: new_battery, moved_to: dest}}
      end
    end

    defmodule PickupPackage do
      @moduledoc "Pick up a package"
      use Jido.Action,
        name: "pickup_package",
        description: "Picks up a package at current location",
        schema: []

      @impl true
      def run(_params, context) do
        location = context.state[:location] || :unknown
        {:ok, %{has_package: true, picked_up_at: location}}
      end
    end

    defmodule DeliverPackage do
      @moduledoc "Deliver the package"
      use Jido.Action,
        name: "deliver_package",
        description: "Delivers the package at current location",
        schema: []

      @impl true
      def run(_params, context) do
        location = context.state[:location] || :unknown
        {:ok, %{has_package: false, delivered: true, delivered_at: location}}
      end
    end

    defmodule Log do
      @moduledoc "Log a message"
      use Jido.Action,
        name: "log",
        description: "Logs a message",
        schema: [
          message: [type: :string, required: true]
        ]

      @impl true
      def run(params, _context) do
        IO.puts("[LOG] #{params.message}")
        {:ok, %{logged: params.message}}
      end
    end
  end

  # ===========================================================================
  # Domain Definition
  # ===========================================================================

  defmodule DeliveryDomain do
    @moduledoc """
    HTN Domain for a delivery robot.

    Tasks:
    - deliver_package (root compound task)
      - check_and_handle_battery (compound - checks battery, recharges if needed)
      - move_to_pickup (primitive)
      - pickup (primitive)
      - move_to_destination (primitive)
      - deliver (primitive)
    """

    alias JidoHTN.Demo.Actions

    def domain do
      "delivery_service"
      |> D.new()
      # Root compound task - define first, then mark as root
      |> D.compound("deliver_package",
        methods: [
          %{
            name: "full_delivery",
            subtasks: [
              "check_and_handle_battery",
              "move_to_pickup",
              "pickup",
              "move_to_destination",
              "deliver",
              "log_complete"
            ]
          }
        ]
      )
      # Compound task for battery handling
      |> D.compound("check_and_handle_battery",
        methods: [
          # If battery is low, recharge first
          %{
            name: "needs_recharge",
            conditions: [&battery_low?/1],
            subtasks: ["log_low_battery", "recharge", "check_and_handle_battery"]
          },
          # If battery is OK, just check and continue
          %{
            name: "battery_ok",
            conditions: [&battery_ok?/1],
            subtasks: ["check_battery"]
          }
        ]
      )
      # Primitive tasks
      |> D.primitive("check_battery", {Actions.CheckBattery, []})
      |> D.primitive("recharge", {Actions.Recharge, []},
        preconditions: [],
        effects: [fn _result -> %{battery: 100} end]
      )
      |> D.primitive("log_low_battery", {Actions.Log, [message: "Battery low, recharging..."]})
      |> D.primitive("move_to_pickup", {Actions.MoveTo, [destination: :pickup_point]},
        preconditions: [&battery_ok?/1],
        effects: [fn _result -> %{location: :pickup_point} end]
      )
      |> D.primitive("pickup", {Actions.PickupPackage, []},
        preconditions: [&at_pickup?/1],
        effects: [fn _result -> %{has_package: true} end]
      )
      |> D.primitive("move_to_destination", {Actions.MoveTo, [destination: :customer]},
        preconditions: [&has_package?/1, &battery_ok?/1],
        effects: [fn _result -> %{location: :customer} end]
      )
      |> D.primitive("deliver", {Actions.DeliverPackage, []},
        preconditions: [&at_customer?/1, &has_package?/1],
        effects: [fn _result -> %{has_package: false, delivered: true} end]
      )
      |> D.primitive("log_complete", {Actions.Log, [message: "Delivery complete!"]})
      # Register allowed workflows
      |> D.allow("CheckBattery", Actions.CheckBattery)
      |> D.allow("Recharge", Actions.Recharge)
      |> D.allow("MoveTo", Actions.MoveTo)
      |> D.allow("PickupPackage", Actions.PickupPackage)
      |> D.allow("DeliverPackage", Actions.DeliverPackage)
      |> D.allow("Log", Actions.Log)
      |> D.root("deliver_package")
      |> D.build!()
    end

    # Predicates for conditions
    def battery_low?(%{battery: b}) when b < 30, do: true
    def battery_low?(_), do: false

    def battery_ok?(%{battery: b}) when b >= 30, do: true
    def battery_ok?(_), do: true

    def at_pickup?(%{location: :pickup_point}), do: true
    def at_pickup?(_), do: false

    def at_customer?(%{location: :customer}), do: true
    def at_customer?(_), do: false

    def has_package?(%{has_package: true}), do: true
    def has_package?(_), do: false
  end

  # ===========================================================================
  # Agent Definition
  # ===========================================================================

  defmodule DeliveryAgent do
    @moduledoc """
    A delivery robot agent controlled by HTN planning.

    Note: We use the Direct strategy here and run HTN planning manually
    since the HTN domain contains runtime functions (predicates) that
    cannot be compiled into the strategy configuration at compile-time.
    """
    use Jido.Agent,
      name: "delivery_agent",
      description: "A delivery robot that uses HTN planning to execute deliveries",
      schema: [
        location: [type: :atom, default: :warehouse],
        battery: [type: :integer, default: 100],
        has_package: [type: :boolean, default: false],
        delivered: [type: :boolean, default: false]
      ]

    alias Jido.HTN

    @doc """
    Run a delivery mission using HTN planning.

    Takes initial world state and plans + executes the delivery.
    """
    def deliver(agent, world_state \\ nil) do
      ws = world_state || agent.state
      domain = JidoHTN.Demo.DeliveryDomain.domain()

      case HTN.plan(domain, ws, root_tasks: ["deliver_package"]) do
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
        instruction = {action_mod, params_map}

        case cmd(ag, instruction) do
          {new_agent, new_dirs} ->
            {new_agent, dirs ++ new_dirs}
        end
      end)
    end
  end

  # ===========================================================================
  # Demo Runner
  # ===========================================================================

  @doc """
  Run the delivery demo.

  Creates a delivery agent and executes a full delivery mission.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("HTN-Controlled Jido Agent Demo")
    IO.puts(String.duplicate("=", 60))

    # Create the agent
    agent = DeliveryAgent.new()

    IO.puts("\n📦 Initial State:")
    IO.puts("   Location: #{agent.state.location}")
    IO.puts("   Battery: #{agent.state.battery}%")
    IO.puts("   Has Package: #{agent.state.has_package}")

    IO.puts("\n🚀 Starting delivery mission...\n")

    # Run the delivery
    {agent, directives} = DeliveryAgent.deliver(agent)

    IO.puts("\n✅ Mission Complete!")
    IO.puts("\n📦 Final State:")
    IO.puts("   Location: #{agent.state.location}")
    IO.puts("   Battery: #{agent.state.battery}%")
    IO.puts("   Has Package: #{agent.state.has_package}")
    IO.puts("   Delivered: #{agent.state[:delivered]}")

    # Show strategy snapshot
    snapshot = DeliveryAgent.strategy_snapshot(agent)
    IO.puts("\n📊 Strategy Snapshot:")
    IO.puts("   Status: #{snapshot.status}")
    IO.puts("   Done: #{snapshot.done?}")
    IO.puts("   Steps Executed: #{snapshot.details[:current_step]}")
    IO.puts("   Plan Length: #{length(snapshot.details[:plan] || [])}")

    if length(directives) > 0 do
      IO.puts("\n📤 Directives Emitted: #{length(directives)}")
    end

    IO.puts("\n" <> String.duplicate("=", 60))

    {agent, directives}
  end

  @doc """
  Run demo with low battery to show recharge behavior.
  """
  def run_low_battery do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("HTN Demo: Low Battery Scenario")
    IO.puts(String.duplicate("=", 60))

    # Create agent with low battery
    agent = DeliveryAgent.new(state: %{battery: 20})

    IO.puts("\n📦 Initial State (Low Battery!):")
    IO.puts("   Location: #{agent.state.location}")
    IO.puts("   Battery: #{agent.state.battery}%")

    IO.puts("\n🚀 Starting delivery mission with low battery...\n")

    # The HTN should plan to recharge first
    {agent, directives} = DeliveryAgent.deliver(agent)

    IO.puts("\n✅ Mission Complete!")
    IO.puts("\n📦 Final State:")
    IO.puts("   Location: #{agent.state.location}")
    IO.puts("   Battery: #{agent.state.battery}%")
    IO.puts("   Delivered: #{agent.state[:delivered]}")

    snapshot = DeliveryAgent.strategy_snapshot(agent)
    IO.puts("\n📊 Strategy Snapshot:")
    IO.puts("   Status: #{snapshot.status}")
    IO.puts("   Steps Executed: #{snapshot.details[:current_step]}")

    IO.puts("\n" <> String.duplicate("=", 60))

    {agent, directives}
  end
end
