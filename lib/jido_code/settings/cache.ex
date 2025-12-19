defmodule JidoCode.Settings.Cache do
  @moduledoc """
  GenServer-backed ETS cache for settings.

  This module owns the ETS table used by `JidoCode.Settings` to cache
  loaded settings. By starting in the supervision tree, it guarantees:

  1. Single ETS table creation (no race conditions)
  2. Proper table ownership and lifecycle
  3. Clean API for cache operations

  ## Usage

  This module is started automatically by `JidoCode.Application`.
  Use `JidoCode.Settings` functions to interact with settings - they
  will use this cache internally.

  ## Direct API (for testing/debugging)

      JidoCode.Settings.Cache.get()
      #=> {:ok, %{"provider" => "anthropic"}} | :miss

      JidoCode.Settings.Cache.put(%{"provider" => "anthropic"})
      #=> :ok

      JidoCode.Settings.Cache.clear()
      #=> :ok
  """

  use GenServer

  @table_name :jido_code_settings_cache
  @cache_key :settings

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the cache GenServer.

  ## Options

  - `:name` - Process name (default: `JidoCode.Settings.Cache`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the cached settings.

  ## Returns

  - `{:ok, settings}` - Settings found in cache
  - `:miss` - Cache is empty
  """
  @spec get() :: {:ok, map()} | :miss
  def get do
    case :ets.whereis(@table_name) do
      :undefined ->
        :miss

      _tid ->
        case :ets.lookup(@table_name, @cache_key) do
          [{@cache_key, settings}] -> {:ok, settings}
          [] -> :miss
        end
    end
  end

  @doc """
  Stores settings in the cache.

  ## Parameters

  - `settings` - Map of settings to cache

  ## Returns

  - `:ok` - Settings cached successfully
  """
  @spec put(map()) :: :ok
  def put(settings) when is_map(settings) do
    case :ets.whereis(@table_name) do
      :undefined ->
        # Table not ready yet, ignore silently
        :ok

      _tid ->
        :ets.insert(@table_name, {@cache_key, settings})
        :ok
    end
  end

  @doc """
  Clears the settings cache.

  ## Returns

  - `:ok` - Cache cleared
  """
  @spec clear() :: :ok
  def clear do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete(@table_name, @cache_key)
        :ok
    end
  end

  @doc """
  Returns the ETS table name used for caching.

  Useful for testing and debugging.
  """
  @spec table_name() :: atom()
  def table_name, do: @table_name

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create the ETS table owned by this process
    # Using :public so Settings module can read directly for performance
    :ets.new(@table_name, [:set, :public, :named_table])
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    # ETS table is automatically deleted when owner process terminates
    :ok
  end
end
