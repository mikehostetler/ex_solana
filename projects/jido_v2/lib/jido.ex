defmodule Jido do
  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  Version 2.0 - Complete rewrite.

  ## Component Discovery

  Jido provides a discovery system for finding registered components in the system:

      # Initialize discovery cache (usually done at startup)
      Jido.discovery_init()

      # List all actions with optional filtering
      Jido.list_actions(category: :utility, limit: 10)

      # Find a specific component by slug
      Jido.get_action_by_slug("abc123de")

  See `Jido.Discovery` for full documentation.
  """

  alias Jido.Discovery

  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  # Discovery lifecycle (namespaced to avoid future collisions)
  @doc """
  Initializes the discovery cache. Should be called during application startup.

  See `Jido.Discovery.init/0` for details.
  """
  defdelegate discovery_init(), to: Discovery, as: :init

  @doc """
  Forces a refresh of the discovery cache.

  See `Jido.Discovery.refresh/0` for details.
  """
  defdelegate discovery_refresh(), to: Discovery, as: :refresh

  @doc """
  Gets the last time the discovery cache was updated.

  See `Jido.Discovery.last_updated/0` for details.
  """
  defdelegate discovery_last_updated(), to: Discovery, as: :last_updated

  # Component listing (short names since these are core to Jido)
  @doc """
  Lists all Actions with optional filtering and pagination.

  See `Jido.Discovery.list_actions/1` for details.
  """
  defdelegate list_actions(opts \\ []), to: Discovery

  @doc """
  Lists all Sensors with optional filtering and pagination.

  See `Jido.Discovery.list_sensors/1` for details.
  """
  defdelegate list_sensors(opts \\ []), to: Discovery

  @doc """
  Lists all Agents with optional filtering and pagination.

  See `Jido.Discovery.list_agents/1` for details.
  """
  defdelegate list_agents(opts \\ []), to: Discovery

  @doc """
  Lists all Skills with optional filtering and pagination.

  See `Jido.Discovery.list_skills/1` for details.
  """
  defdelegate list_skills(opts \\ []), to: Discovery

  @doc """
  Lists all Demos with optional filtering and pagination.

  See `Jido.Discovery.list_demos/1` for details.
  """
  defdelegate list_demos(opts \\ []), to: Discovery

  # Component lookup by slug
  @doc """
  Retrieves an Action by its slug.

  See `Jido.Discovery.get_action_by_slug/1` for details.
  """
  defdelegate get_action_by_slug(slug), to: Discovery

  @doc """
  Retrieves a Sensor by its slug.

  See `Jido.Discovery.get_sensor_by_slug/1` for details.
  """
  defdelegate get_sensor_by_slug(slug), to: Discovery

  @doc """
  Retrieves an Agent by its slug.

  See `Jido.Discovery.get_agent_by_slug/1` for details.
  """
  defdelegate get_agent_by_slug(slug), to: Discovery

  @doc """
  Retrieves a Skill by its slug.

  See `Jido.Discovery.get_skill_by_slug/1` for details.
  """
  defdelegate get_skill_by_slug(slug), to: Discovery

  @doc """
  Retrieves a Demo by its slug.

  See `Jido.Discovery.get_demo_by_slug/1` for details.
  """
  defdelegate get_demo_by_slug(slug), to: Discovery
end
