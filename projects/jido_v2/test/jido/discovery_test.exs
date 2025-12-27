defmodule JidoTest.DiscoveryTest do
  use ExUnit.Case
  alias Jido.Discovery

  @moduletag :capture_log

  setup do
    :ok = Discovery.init()
    :ok
  end

  describe "init/0" do
    test "initializes cache successfully" do
      assert :ok = Discovery.init()
      assert {:ok, _cache} = Discovery.__get_cache__()
    end
  end

  describe "refresh/0" do
    test "refreshes cache successfully" do
      assert :ok = Discovery.refresh()
      assert {:ok, _cache} = Discovery.__get_cache__()
    end
  end

  describe "last_updated/0" do
    test "returns last update time when cache exists" do
      :ok = Discovery.init()
      assert {:ok, %DateTime{}} = Discovery.last_updated()
    end

    test "returns error when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)
      assert {:error, :not_initialized} = Discovery.last_updated()
    end
  end

  describe "component discovery" do
    test "discovers actions with __action_metadata__ callback" do
      actions = Discovery.list_actions()

      assert Enum.any?(actions, &(&1.module == JidoTest.Fixtures.CoolAction))
      assert Enum.any?(actions, &(&1.module == JidoTest.Fixtures.AnotherAction))
    end

    test "discovers sensors with __sensor_metadata__ callback" do
      sensors = Discovery.list_sensors()

      assert Enum.any?(sensors, &(&1.module == JidoTest.Fixtures.MonitorSensor))
    end

    test "discovers agents with __agent_metadata__ callback" do
      agents = Discovery.list_agents()

      assert Enum.any?(agents, &(&1.module == JidoTest.Fixtures.SampleAgent))
    end

    test "discovers skills with __skill_metadata__ callback" do
      skills = Discovery.list_skills()

      assert Enum.any?(skills, &(&1.module == JidoTest.Fixtures.SampleSkill))
    end

    test "discovers demos with __jido_demo__ callback" do
      demos = Discovery.list_demos()

      assert Enum.any?(demos, &(&1.module == JidoTest.Fixtures.SampleDemo))
    end

    test "handles both map and keyword list metadata formats" do
      actions = Discovery.list_actions()

      cool_action = Enum.find(actions, &(&1.module == JidoTest.Fixtures.CoolAction))
      another_action = Enum.find(actions, &(&1.module == JidoTest.Fixtures.AnotherAction))

      assert cool_action.name == "cool_action"
      assert another_action.name == "another_action"
    end
  end

  describe "slug generation" do
    test "assigns deterministic slugs based on module name" do
      :ok = Discovery.init()
      actions = Discovery.list_actions()
      action = Enum.find(actions, &(&1.module == JidoTest.Fixtures.CoolAction))

      assert is_binary(action.slug)
      assert String.length(action.slug) == 8

      expected_slug =
        :sha256
        |> :crypto.hash(to_string(action.module))
        |> Base.url_encode64(padding: false)
        |> String.slice(0, 8)

      assert action.slug == expected_slug
    end
  end

  describe "get_by_slug functions" do
    test "returns nil when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)

      assert nil == Discovery.get_action_by_slug("any")
      assert nil == Discovery.get_sensor_by_slug("any")
      assert nil == Discovery.get_agent_by_slug("any")
      assert nil == Discovery.get_skill_by_slug("any")
      assert nil == Discovery.get_demo_by_slug("any")
    end

    test "returns nil for non-existent slugs" do
      :ok = Discovery.init()

      assert nil == Discovery.get_action_by_slug("nonexistent")
      assert nil == Discovery.get_sensor_by_slug("nonexistent")
      assert nil == Discovery.get_agent_by_slug("nonexistent")
      assert nil == Discovery.get_skill_by_slug("nonexistent")
      assert nil == Discovery.get_demo_by_slug("nonexistent")
    end

    test "get_action_by_slug finds the right action" do
      :ok = Discovery.init()

      action = Enum.find(Discovery.list_actions(), &(&1.module == JidoTest.Fixtures.CoolAction))
      assert action

      found = Discovery.get_action_by_slug(action.slug)
      assert found.module == JidoTest.Fixtures.CoolAction
    end

    test "get_sensor_by_slug finds the right sensor" do
      :ok = Discovery.init()

      sensor =
        Enum.find(Discovery.list_sensors(), &(&1.module == JidoTest.Fixtures.MonitorSensor))

      assert sensor

      found = Discovery.get_sensor_by_slug(sensor.slug)
      assert found.module == JidoTest.Fixtures.MonitorSensor
    end

    test "get_agent_by_slug finds the right agent" do
      :ok = Discovery.init()

      agent = Enum.find(Discovery.list_agents(), &(&1.module == JidoTest.Fixtures.SampleAgent))
      assert agent

      found = Discovery.get_agent_by_slug(agent.slug)
      assert found.module == JidoTest.Fixtures.SampleAgent
    end

    test "get_skill_by_slug finds the right skill" do
      :ok = Discovery.init()

      skill = Enum.find(Discovery.list_skills(), &(&1.module == JidoTest.Fixtures.SampleSkill))
      assert skill

      found = Discovery.get_skill_by_slug(skill.slug)
      assert found.module == JidoTest.Fixtures.SampleSkill
    end

    test "get_demo_by_slug finds the right demo" do
      :ok = Discovery.init()

      demo = Enum.find(Discovery.list_demos(), &(&1.module == JidoTest.Fixtures.SampleDemo))
      assert demo

      found = Discovery.get_demo_by_slug(demo.slug)
      assert found.module == JidoTest.Fixtures.SampleDemo
    end
  end

  describe "list functions" do
    test "returns empty list when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)

      assert [] == Discovery.list_actions()
      assert [] == Discovery.list_sensors()
      assert [] == Discovery.list_agents()
      assert [] == Discovery.list_skills()
      assert [] == Discovery.list_demos()
    end

    test "applies pagination options" do
      :ok = Discovery.init()

      assert length(Discovery.list_actions(limit: 1)) <= 1
      assert length(Discovery.list_sensors(limit: 1)) <= 1
      assert length(Discovery.list_agents(limit: 1)) <= 1
      assert length(Discovery.list_skills(limit: 1)) <= 1
      assert length(Discovery.list_demos(limit: 1)) <= 1

      all_actions = Discovery.list_actions()
      offset_actions = Discovery.list_actions(offset: 1)
      assert length(offset_actions) <= max(length(all_actions) - 1, 0)
    end

    test "filters by name" do
      :ok = Discovery.init()

      actions = Discovery.list_actions(name: "cool")
      assert Enum.all?(actions, &String.contains?(&1.name, "cool"))

      empty = Discovery.list_actions(name: "nonexistent_xyz")
      assert Enum.empty?(empty)
    end

    test "filters by category" do
      :ok = Discovery.init()

      utility_actions = Discovery.list_actions(category: :utility)
      assert Enum.all?(utility_actions, &(&1.category == :utility))

      monitoring_sensors = Discovery.list_sensors(category: :monitoring)
      assert Enum.all?(monitoring_sensors, &(&1.category == :monitoring))

      empty = Discovery.list_actions(category: :nonexistent)
      assert Enum.empty?(empty)
    end

    test "filters by tag" do
      :ok = Discovery.init()

      tagged_actions = Discovery.list_actions(tag: :cool)
      assert Enum.all?(tagged_actions, &(:cool in &1.tags))

      tagged_agents = Discovery.list_agents(tag: :worker)
      assert Enum.all?(tagged_agents, &(:worker in &1.tags))

      empty = Discovery.list_actions(tag: :nonexistent_tag)
      assert Enum.empty?(empty)
    end

    test "filters by description" do
      :ok = Discovery.init()

      actions = Discovery.list_actions(description: "cool stuff")
      assert Enum.all?(actions, &String.contains?(&1.description, "cool stuff"))
    end

    test "combines multiple filters" do
      :ok = Discovery.init()

      actions = Discovery.list_actions(category: :utility, tag: :cool)

      assert Enum.all?(actions, fn action ->
               action.category == :utility and :cool in action.tags
             end)
    end
  end

  describe "Jido module delegates" do
    test "discovery_init/0 delegates to Discovery.init/0" do
      assert :ok = Jido.discovery_init()
    end

    test "discovery_refresh/0 delegates to Discovery.refresh/0" do
      assert :ok = Jido.discovery_refresh()
    end

    test "discovery_last_updated/0 delegates to Discovery.last_updated/0" do
      Jido.discovery_init()
      assert {:ok, %DateTime{}} = Jido.discovery_last_updated()
    end

    test "list_actions/1 delegates to Discovery.list_actions/1" do
      Jido.discovery_init()
      actions = Jido.list_actions()
      assert Enum.any?(actions, &(&1.module == JidoTest.Fixtures.CoolAction))
    end

    test "get_action_by_slug/1 delegates to Discovery.get_action_by_slug/1" do
      Jido.discovery_init()
      action = Enum.find(Jido.list_actions(), &(&1.module == JidoTest.Fixtures.CoolAction))
      found = Jido.get_action_by_slug(action.slug)
      assert found.module == JidoTest.Fixtures.CoolAction
    end
  end
end
