defmodule JidoTest.Fixtures do
  @moduledoc """
  Test fixtures for Jido.Discovery tests.

  These modules define various metadata callbacks to be discovered during tests.
  """
end

defmodule JidoTest.Fixtures.CoolAction do
  @moduledoc false

  def __action_metadata__ do
    %{
      name: "cool_action",
      description: "Does cool stuff",
      category: :utility,
      tags: [:cool, :stuff]
    }
  end
end

defmodule JidoTest.Fixtures.AnotherAction do
  @moduledoc false

  def __action_metadata__ do
    [
      name: "another_action",
      description: "Another action for testing",
      category: :processing,
      tags: [:test]
    ]
  end
end

defmodule JidoTest.Fixtures.MonitorSensor do
  @moduledoc false

  def __sensor_metadata__ do
    %{
      name: "monitor_sensor",
      description: "Monitors something",
      category: :monitoring,
      tags: [:metrics]
    }
  end
end

defmodule JidoTest.Fixtures.SampleAgent do
  @moduledoc false

  def __agent_metadata__ do
    [
      name: "sample_agent",
      description: "Does agent things",
      category: :business,
      tags: [:worker]
    ]
  end
end

defmodule JidoTest.Fixtures.SampleSkill do
  @moduledoc false

  def __skill_metadata__ do
    %{
      name: "sample_skill",
      description: "Provides skills",
      category: :capability,
      tags: [:skill]
    }
  end
end

defmodule JidoTest.Fixtures.SampleDemo do
  @moduledoc false

  def __jido_demo__ do
    %{
      name: "sample_demo",
      description: "Demonstrates something",
      category: :example,
      tags: [:demo]
    }
  end
end
