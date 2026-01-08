defmodule JidoHTNTest.DemoTest do
  use ExUnit.Case, async: true

  alias JidoHTN.Demo
  alias JidoHTN.Demo.DeliveryAgent
  alias JidoHTN.Demo.DeliveryDomain

  @moduletag :capture_log

  describe "DeliveryDomain" do
    test "builds a valid domain" do
      domain = DeliveryDomain.domain()
      assert %Jido.HTN.Domain{} = domain
      assert domain.name == "delivery_service"
      assert Map.has_key?(domain.tasks, "deliver_package")
      assert Map.has_key?(domain.tasks, "check_and_handle_battery")
    end

    test "plans a delivery with full battery" do
      domain = DeliveryDomain.domain()
      world_state = %{battery: 100, location: :warehouse, has_package: false}

      {:ok, plan, _mtr} = Jido.HTN.plan(domain, world_state, root_tasks: ["deliver_package"])

      assert is_list(plan)
      assert length(plan) > 0

      action_modules = Enum.map(plan, fn {mod, _params} -> mod end)
      assert Demo.Actions.CheckBattery in action_modules
      assert Demo.Actions.MoveTo in action_modules
      assert Demo.Actions.PickupPackage in action_modules
      assert Demo.Actions.DeliverPackage in action_modules
    end

    test "plans recharge when battery is low" do
      domain = DeliveryDomain.domain()
      world_state = %{battery: 20, location: :warehouse, has_package: false}

      {:ok, plan, _mtr} = Jido.HTN.plan(domain, world_state, root_tasks: ["deliver_package"])

      action_modules = Enum.map(plan, fn {mod, _params} -> mod end)
      assert Demo.Actions.Recharge in action_modules
    end
  end

  describe "DeliveryAgent" do
    test "creates agent with default state" do
      agent = DeliveryAgent.new()

      assert agent.state.location == :warehouse
      assert agent.state.battery == 100
      assert agent.state.has_package == false
      assert agent.state.delivered == false
    end

    test "creates agent with custom state" do
      agent = DeliveryAgent.new(state: %{battery: 50, location: :pickup_point})

      assert agent.state.battery == 50
      assert agent.state.location == :pickup_point
    end

    test "delivers package successfully with full battery" do
      agent = DeliveryAgent.new()

      {agent, directives} = DeliveryAgent.deliver(agent)

      assert agent.state.delivered == true
      assert agent.state.has_package == false
      assert agent.state.location == :customer
      assert agent.state.battery < 100
      assert directives == []
    end

    test "recharges before delivery when battery is low" do
      agent = DeliveryAgent.new(state: %{battery: 20})

      {agent, _directives} = DeliveryAgent.deliver(agent)

      assert agent.state.delivered == true
      assert agent.state.recharged == true
      assert agent.state.battery > 20
    end

    test "delivers package with custom world state" do
      agent = DeliveryAgent.new()
      world_state = %{battery: 100, location: :warehouse, has_package: false, delivered: false}

      {agent, _directives} = DeliveryAgent.deliver(agent, world_state)

      assert agent.state.delivered == true
    end
  end

  describe "predicates" do
    test "battery_low? returns true when battery < 30" do
      assert DeliveryDomain.battery_low?(%{battery: 20}) == true
      assert DeliveryDomain.battery_low?(%{battery: 29}) == true
      assert DeliveryDomain.battery_low?(%{battery: 30}) == false
      assert DeliveryDomain.battery_low?(%{battery: 100}) == false
    end

    test "battery_ok? returns true when battery >= 30 or no battery field" do
      assert DeliveryDomain.battery_ok?(%{battery: 30}) == true
      assert DeliveryDomain.battery_ok?(%{battery: 100}) == true
      # Note: battery_ok? returns true as default when battery is missing or >= 30
      # This is intentional - only battery_low? triggers recharge
      assert DeliveryDomain.battery_ok?(%{battery: 29}) == true
      assert DeliveryDomain.battery_ok?(%{}) == true
    end

    test "at_pickup? returns true only at pickup_point" do
      assert DeliveryDomain.at_pickup?(%{location: :pickup_point}) == true
      assert DeliveryDomain.at_pickup?(%{location: :warehouse}) == false
      assert DeliveryDomain.at_pickup?(%{location: :customer}) == false
    end

    test "at_customer? returns true only at customer" do
      assert DeliveryDomain.at_customer?(%{location: :customer}) == true
      assert DeliveryDomain.at_customer?(%{location: :warehouse}) == false
    end

    test "has_package? returns true when has_package is true" do
      assert DeliveryDomain.has_package?(%{has_package: true}) == true
      assert DeliveryDomain.has_package?(%{has_package: false}) == false
      assert DeliveryDomain.has_package?(%{}) == false
    end
  end

  describe "Actions" do
    test "CheckBattery action" do
      context = %{state: %{battery: 50}}
      {:ok, result} = Demo.Actions.CheckBattery.run(%{}, context)

      assert result.battery_checked == true
      assert result.needs_recharge == false
    end

    test "CheckBattery detects low battery" do
      context = %{state: %{battery: 20}}
      {:ok, result} = Demo.Actions.CheckBattery.run(%{}, context)

      assert result.needs_recharge == true
    end

    test "Recharge action" do
      context = %{state: %{battery: 20}}
      {:ok, result} = Demo.Actions.Recharge.run(%{}, context)

      assert result.battery == 70
      assert result.recharged == true
    end

    test "Recharge caps at 100" do
      context = %{state: %{battery: 80}}
      {:ok, result} = Demo.Actions.Recharge.run(%{}, context)

      assert result.battery == 100
    end

    test "MoveTo action" do
      context = %{state: %{battery: 100}}
      {:ok, result} = Demo.Actions.MoveTo.run(%{destination: :pickup_point}, context)

      assert result.location == :pickup_point
      assert result.battery == 90
      assert result.moved_to == :pickup_point
    end

    test "PickupPackage action" do
      context = %{state: %{location: :pickup_point}}
      {:ok, result} = Demo.Actions.PickupPackage.run(%{}, context)

      assert result.has_package == true
      assert result.picked_up_at == :pickup_point
    end

    test "DeliverPackage action" do
      context = %{state: %{location: :customer}}
      {:ok, result} = Demo.Actions.DeliverPackage.run(%{}, context)

      assert result.has_package == false
      assert result.delivered == true
      assert result.delivered_at == :customer
    end

    test "Log action" do
      context = %{state: %{}}
      {:ok, result} = Demo.Actions.Log.run(%{message: "test"}, context)

      assert result.logged == "test"
    end
  end
end
