defmodule CodeMapper.Cache do
  @moduledoc """
  Simple DETS-based cache for CodeMapper results.
  
  Stores parsed file results keyed by file path + mtime to avoid:
  - Re-parsing unchanged files
  - Re-running LLM calls on cached content
  
  Cache is stored in .code_mapper_cache in the target directory.
  """

  use GenServer
  require Logger

  @cache_version 1

  # Client API

  def start_link(opts \\ []) do
    cache_dir = Keyword.get(opts, :cache_dir, File.cwd!())
    GenServer.start_link(__MODULE__, cache_dir, name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__, :normal)
  catch
    :exit, _ -> :ok
  end

  @doc "Get cached result for a file, returns nil if not cached or stale"
  def get(path) do
    GenServer.call(__MODULE__, {:get, path})
  catch
    :exit, _ -> nil
  end

  @doc "Store parsed result for a file"
  def put(path, result) do
    GenServer.call(__MODULE__, {:put, path, result})
  catch
    :exit, _ -> :ok
  end

  @doc "Get cache stats"
  def stats do
    GenServer.call(__MODULE__, :stats)
  catch
    :exit, _ -> %{hits: 0, misses: 0, entries: 0}
  end

  @doc "Clear the cache"
  def clear do
    GenServer.call(__MODULE__, :clear)
  catch
    :exit, _ -> :ok
  end

  # Server Implementation

  @impl true
  def init(cache_dir) do
    cache_file = Path.join(cache_dir, ".code_mapper_cache")
    
    case :dets.open_file(:code_mapper_cache, file: String.to_charlist(cache_file), type: :set) do
      {:ok, table} ->
        state = %{
          table: table,
          cache_file: cache_file,
          hits: 0,
          misses: 0
        }
        Logger.debug("[Cache] Opened cache at #{cache_file}")
        {:ok, state}
        
      {:error, reason} ->
        Logger.warning("[Cache] Failed to open cache: #{inspect(reason)}, using ETS fallback")
        table = :ets.new(:code_mapper_cache, [:set, :public])
        {:ok, %{table: table, cache_file: nil, hits: 0, misses: 0, ets_fallback: true}}
    end
  end

  @impl true
  def handle_call({:get, path}, _from, state) do
    case get_file_mtime(path) do
      {:ok, mtime} ->
        key = cache_key(path, mtime)
        
        result = 
          if state[:ets_fallback] do
            case :ets.lookup(state.table, key) do
              [{^key, cached}] -> cached
              [] -> nil
            end
          else
            case :dets.lookup(state.table, key) do
              [{^key, cached}] -> cached
              [] -> nil
            end
          end
        
        if result do
          {:reply, {:ok, result.result}, %{state | hits: state.hits + 1}}
        else
          {:reply, nil, %{state | misses: state.misses + 1}}
        end
        
      :error ->
        {:reply, nil, %{state | misses: state.misses + 1}}
    end
  end

  @impl true
  def handle_call({:put, path, result}, _from, state) do
    case get_file_mtime(path) do
      {:ok, mtime} ->
        key = cache_key(path, mtime)
        entry = %{
          version: @cache_version,
          path: path,
          mtime: mtime,
          result: result,
          cached_at: System.system_time(:second)
        }
        
        if state[:ets_fallback] do
          :ets.insert(state.table, {key, entry})
        else
          :dets.insert(state.table, {key, entry})
        end
        
        {:reply, :ok, state}
        
      :error ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    count = 
      if state[:ets_fallback] do
        :ets.info(state.table, :size)
      else
        :dets.info(state.table, :size) || 0
      end
    
    stats = %{
      hits: state.hits,
      misses: state.misses,
      entries: count,
      hit_rate: if(state.hits + state.misses > 0, 
        do: Float.round(state.hits / (state.hits + state.misses) * 100, 1),
        else: 0.0)
    }
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    if state[:ets_fallback] do
      :ets.delete_all_objects(state.table)
    else
      :dets.delete_all_objects(state.table)
    end
    {:reply, :ok, %{state | hits: 0, misses: 0}}
  end

  @impl true
  def terminate(_reason, state) do
    unless state[:ets_fallback] do
      :dets.close(state.table)
    end
    :ok
  end

  # Helpers

  defp cache_key(path, mtime) do
    {:v, @cache_version, path, mtime}
  end

  defp get_file_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> {:ok, mtime}
      _ -> :error
    end
  end
end
