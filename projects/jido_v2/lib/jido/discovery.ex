defmodule Jido.Discovery do
  @moduledoc """
  Component registry system for discovering Jido artifacts in the system.

  Discovery provides efficient caching and lookup of system components like Actions,
  Sensors, Agents, Skills, and Demos. It acts as a service registry that helps
  different parts of your system find and interact with each other.

  ## Core Concepts

  ### Component Discovery

  Discovery works by scanning all loaded applications for components that implement
  Jido's metadata callbacks. It automatically finds and indexes:

  - **Actions** - Discrete units of work (via `__action_metadata__/0`)
  - **Sensors** - Event monitoring components (via `__sensor_metadata__/0`)
  - **Agents** - Autonomous workers (via `__agent_metadata__/0`)
  - **Skills** - Reusable capability packs (via `__skill_metadata__/0`)
  - **Demos** - Example implementations (via `__jido_demo__/0`)

  The module uses Erlang's `:persistent_term` for optimal lookup performance.

  ### Component Metadata

  Each discovered component includes the following metadata:

      %{
        module: MyApp.CoolAction,        # The actual module
        name: "cool_action",             # Human-readable name
        description: "Does cool stuff",  # What it does
        slug: "abc123de",                # Unique identifier (8-char hash)
        category: :utility,              # Broad classification
        tags: [:cool, :stuff]            # Searchable tags
      }

  ## Usage Examples

  ### Basic Component Lookup

      # Find a specific action by slug
      case Jido.Discovery.get_action_by_slug("abc123de") do
        %{module: module} ->
          {:ok, result} = module.run()
        nil ->
          # Handle missing action
      end

  ### Filtered Component Lists

      # List all monitoring sensors
      sensors = Jido.Discovery.list_sensors(
        category: :monitoring,
        tag: :metrics
      )

      # Get the first 10 utility actions
      actions = Jido.Discovery.list_actions(
        category: :utility,
        limit: 10
      )

  ### Cache Management

      # Initialize cache (usually done at startup)
      :ok = Jido.Discovery.init()

      # Force cache refresh if needed
      :ok = Jido.Discovery.refresh()

      # Check last update time
      {:ok, last_updated} = Jido.Discovery.last_updated()

  ## Filtering Options

  All list functions support these filters:

  - `:limit` - Maximum results to return
  - `:offset` - Results to skip (pagination)
  - `:name` - Filter by name (partial match)
  - `:description` - Filter by description (partial match)
  - `:category` - Filter by category (exact match)
  - `:tag` - Filter by tag (must have exact tag)
  """
  require Logger

  @cache_key :__jido_discovery_cache__
  @cache_version "2.0"

  @type component_type :: :action | :sensor | :agent | :skill | :demo

  @type component_metadata :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t(),
          category: atom() | nil,
          tags: [atom()] | nil
        }

  @type cache_entry :: %{
          version: String.t(),
          last_updated: DateTime.t(),
          actions: [component_metadata()],
          sensors: [component_metadata()],
          agents: [component_metadata()],
          skills: [component_metadata()],
          demos: [component_metadata()]
        }

  @doc """
  Initializes the discovery cache. Should be called during application startup.

  ## Returns

  - `:ok` if cache was initialized successfully
  - `{:error, :cache_init_failed}` if initialization failed
  """
  @spec init() :: :ok | {:error, :cache_init_failed}
  def init do
    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.debug("[Jido.Discovery] cache initialized successfully")
      :ok
    rescue
      e ->
        error = Jido.Error.Discovery.CacheInitFailed.exception(reason: e)
        Logger.warning("[Jido.Discovery] #{Exception.message(error)}")
        {:error, :cache_init_failed}
    end
  end

  @doc """
  Forces a refresh of the discovery cache.

  ## Returns

  - `:ok` if cache was refreshed successfully
  - `{:error, :cache_refresh_failed}` if refresh failed
  """
  @spec refresh() :: :ok | {:error, :cache_refresh_failed}
  def refresh do
    try do
      cache = build_cache()
      :persistent_term.put(@cache_key, cache)
      Logger.info("[Jido.Discovery] cache refreshed successfully")
      :ok
    rescue
      e ->
        error = Jido.Error.Discovery.CacheRefreshFailed.exception(reason: e)
        Logger.warning("[Jido.Discovery] #{Exception.message(error)}")
        {:error, :cache_refresh_failed}
    end
  end

  @doc """
  Gets the last time the cache was updated.

  ## Returns

  - `{:ok, datetime}` with the last update time
  - `{:error, :not_initialized}` if cache hasn't been initialized
  """
  @spec last_updated() :: {:ok, DateTime.t()} | {:error, :not_initialized}
  def last_updated do
    case get_cache() do
      {:ok, cache} -> {:ok, cache.last_updated}
      error -> error
    end
  end

  @doc """
  Retrieves an Action by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Action.

  ## Returns

  The Action metadata if found, otherwise `nil`.
  """
  @spec get_action_by_slug(String.t()) :: component_metadata() | nil
  def get_action_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.actions, fn action -> action.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Sensor by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Sensor.

  ## Returns

  The Sensor metadata if found, otherwise `nil`.
  """
  @spec get_sensor_by_slug(String.t()) :: component_metadata() | nil
  def get_sensor_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.sensors, fn sensor -> sensor.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves an Agent by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Agent.

  ## Returns

  The Agent metadata if found, otherwise `nil`.
  """
  @spec get_agent_by_slug(String.t()) :: component_metadata() | nil
  def get_agent_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.agents, fn agent -> agent.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Skill by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Skill.

  ## Returns

  The Skill metadata if found, otherwise `nil`.
  """
  @spec get_skill_by_slug(String.t()) :: component_metadata() | nil
  def get_skill_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.skills, fn skill -> skill.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Retrieves a Demo by its slug.

  ## Parameters

  - `slug`: A string representing the unique identifier of the Demo.

  ## Returns

  The Demo metadata if found, otherwise `nil`.
  """
  @spec get_demo_by_slug(String.t()) :: component_metadata() | nil
  def get_demo_by_slug(slug) do
    case get_cache() do
      {:ok, cache} -> Enum.find(cache.demos, fn demo -> demo.slug == slug end)
      _ -> nil
    end
  end

  @doc """
  Lists all Actions with optional filtering and pagination.

  ## Options

  - `:limit` - Maximum number of results to return
  - `:offset` - Number of results to skip before starting to return
  - `:name` - Filter Actions by name (partial match)
  - `:description` - Filter Actions by description (partial match)
  - `:category` - Filter Actions by category (exact match)
  - `:tag` - Filter Actions by tag (must have the exact tag)

  ## Returns

  A list of Action metadata.
  """
  @spec list_actions(keyword()) :: [component_metadata()]
  def list_actions(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.actions, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Sensors with optional filtering and pagination.

  ## Options

  - `:limit` - Maximum number of results to return
  - `:offset` - Number of results to skip before starting to return
  - `:name` - Filter Sensors by name (partial match)
  - `:description` - Filter Sensors by description (partial match)
  - `:category` - Filter Sensors by category (exact match)
  - `:tag` - Filter Sensors by tag (must have the exact tag)

  ## Returns

  A list of Sensor metadata.
  """
  @spec list_sensors(keyword()) :: [component_metadata()]
  def list_sensors(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.sensors, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Agents with optional filtering and pagination.

  ## Options

  - `:limit` - Maximum number of results to return
  - `:offset` - Number of results to skip before starting to return
  - `:name` - Filter Agents by name (partial match)
  - `:description` - Filter Agents by description (partial match)
  - `:category` - Filter Agents by category (exact match)
  - `:tag` - Filter Agents by tag (must have the exact tag)

  ## Returns

  A list of Agent metadata.
  """
  @spec list_agents(keyword()) :: [component_metadata()]
  def list_agents(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.agents, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Skills with optional filtering and pagination.

  ## Options

  - `:limit` - Maximum number of results to return
  - `:offset` - Number of results to skip before starting to return
  - `:name` - Filter Skills by name (partial match)
  - `:description` - Filter Skills by description (partial match)
  - `:category` - Filter Skills by category (exact match)
  - `:tag` - Filter Skills by tag (must have the exact tag)

  ## Returns

  A list of Skill metadata.
  """
  @spec list_skills(keyword()) :: [component_metadata()]
  def list_skills(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.skills, opts)
      _ -> []
    end
  end

  @doc """
  Lists all Demos with optional filtering and pagination.

  ## Options

  - `:limit` - Maximum number of results to return
  - `:offset` - Number of results to skip before starting to return
  - `:name` - Filter Demos by name (partial match)
  - `:description` - Filter Demos by description (partial match)
  - `:category` - Filter Demos by category (exact match)
  - `:tag` - Filter Demos by tag (must have the exact tag)

  ## Returns

  A list of Demo metadata.
  """
  @spec list_demos(keyword()) :: [component_metadata()]
  def list_demos(opts \\ []) do
    case get_cache() do
      {:ok, cache} -> filter_and_paginate(cache.demos, opts)
      _ -> []
    end
  end

  @doc false
  def __get_cache__, do: get_cache()

  defp get_cache do
    try do
      case :persistent_term.get(@cache_key) do
        %{version: @cache_version} = cache -> {:ok, cache}
        _ -> {:error, :not_initialized}
      end
    rescue
      ArgumentError -> {:error, :not_initialized}
    end
  end

  defp build_cache do
    %{
      version: @cache_version,
      last_updated: DateTime.utc_now(),
      actions: discover_components(:__action_metadata__),
      sensors: discover_components(:__sensor_metadata__),
      agents: discover_components(:__agent_metadata__),
      skills: discover_components(:__skill_metadata__),
      demos: discover_components(:__jido_demo__)
    }
  end

  defp discover_components(metadata_function) do
    all_applications()
    |> Enum.flat_map(&all_modules/1)
    |> Enum.filter(&has_metadata_function?(&1, metadata_function))
    |> Enum.map(fn module ->
      metadata = apply(module, metadata_function, [])
      module_name = to_string(module)

      slug =
        :sha256
        |> :crypto.hash(module_name)
        |> Base.url_encode64(padding: false)
        |> String.slice(0, 8)

      metadata = if Keyword.keyword?(metadata), do: Map.new(metadata), else: metadata

      metadata
      |> Map.put(:module, module)
      |> Map.put(:slug, slug)
    end)
  end

  defp filter_and_paginate(components, opts) do
    components
    |> filter_components(opts)
    |> paginate(opts)
  end

  defp filter_components(components, opts) do
    name = Keyword.get(opts, :name)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category)
    tag = Keyword.get(opts, :tag)

    Enum.filter(components, fn metadata ->
      matches_name?(metadata, name) and
        matches_description?(metadata, description) and
        matches_category?(metadata, category) and
        matches_tag?(metadata, tag)
    end)
  end

  defp paginate(components, opts) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit)

    components
    |> Enum.drop(offset)
    |> maybe_limit(limit)
  end

  defp all_applications do
    Application.loaded_applications() |> Enum.map(fn {app, _, _} -> app end)
  end

  defp all_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      :undefined -> []
    end
  end

  defp has_metadata_function?(module, function) do
    Code.ensure_loaded?(module) and function_exported?(module, function, 0)
  end

  defp matches_name?(_metadata, nil), do: true
  defp matches_name?(metadata, name), do: String.contains?(metadata[:name] || "", name)

  defp matches_description?(_metadata, nil), do: true

  defp matches_description?(metadata, description),
    do: String.contains?(metadata[:description] || "", description)

  defp matches_category?(_metadata, nil), do: true
  defp matches_category?(metadata, category), do: metadata[:category] == category

  defp matches_tag?(_metadata, nil), do: true
  defp matches_tag?(metadata, tag), do: is_list(metadata[:tags]) and tag in metadata[:tags]

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, limit) when is_integer(limit) and limit > 0, do: Enum.take(list, limit)
  defp maybe_limit(list, _), do: list
end
