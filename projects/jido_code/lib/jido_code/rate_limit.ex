defmodule JidoCode.RateLimit do
  @moduledoc """
  Simple ETS-based rate limiting for session operations.

  Implements sliding window rate limiting to prevent abuse of expensive
  operations like session resume. Uses GenServer for periodic cleanup of
  expired entries.

  ## Configuration

  Rate limits can be configured per operation type in application config:

      config :jido_code, :rate_limits,
        resume: [limit: 5, window_seconds: 60]

  ## Example

      iex> RateLimit.check_rate_limit(:resume, "session-123")
      :ok

      iex> # After 5 attempts within 60 seconds...
      iex> RateLimit.check_rate_limit(:resume, "session-123")
      {:error, :rate_limit_exceeded, 45}  # 45 seconds until reset
  """

  use GenServer
  require Logger

  @table_name :jido_code_rate_limits

  ## Client API

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Checks if an operation is allowed under the per-session rate limit.

  Returns `:ok` if the operation is allowed, or an error tuple with
  retry-after time if the rate limit has been exceeded.

  Note: This only checks per-session limits. For operations that need
  global rate limiting, use check_global_rate_limit/1 in addition.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)
  - `key` - The unique identifier (e.g., session_id)

  ## Returns

  - `:ok` - Operation is allowed
  - `{:error, :rate_limit_exceeded, retry_after_seconds}` - Rate limit exceeded

  ## Examples

      iex> RateLimit.check_rate_limit(:resume, "abc-123")
      :ok

      iex> # After exceeding limit...
      iex> RateLimit.check_rate_limit(:resume, "abc-123")
      {:error, :rate_limit_exceeded, 30}
  """
  @spec check_rate_limit(atom(), String.t()) ::
          :ok | {:error, :rate_limit_exceeded, pos_integer()}
  def check_rate_limit(operation, key) when is_atom(operation) and is_binary(key) do
    limits = get_limits(operation)
    now = System.system_time(:second)
    lookup_key = {operation, key}

    # Get all timestamps for this key
    timestamps =
      case :ets.lookup(@table_name, lookup_key) do
        [{^lookup_key, ts}] -> ts
        [] -> []
      end

    # Filter to timestamps within the window
    window_start = now - limits.window_seconds
    recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

    # Check if limit exceeded
    if length(recent_timestamps) >= limits.limit do
      # Calculate retry-after time
      oldest_recent = Enum.min(recent_timestamps)
      retry_after = oldest_recent + limits.window_seconds - now

      {:error, :rate_limit_exceeded, max(retry_after, 1)}
    else
      :ok
    end
  end

  @doc """
  Checks if an operation is allowed under the global rate limit.

  Global rate limits apply across all sessions/keys to prevent bypass attacks
  where an attacker creates multiple sessions to circumvent per-session limits.

  Returns `:ok` if the operation is allowed, or an error tuple with
  retry-after time if the global rate limit has been exceeded.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)

  ## Returns

  - `:ok` - Operation is allowed globally
  - `{:error, :rate_limit_exceeded, retry_after_seconds}` - Global rate limit exceeded

  ## Examples

      iex> RateLimit.check_global_rate_limit(:resume)
      :ok

      iex> # After exceeding global limit...
      iex> RateLimit.check_global_rate_limit(:resume)
      {:error, :rate_limit_exceeded, 30}
  """
  @spec check_global_rate_limit(atom()) :: :ok | {:error, :rate_limit_exceeded, pos_integer()}
  def check_global_rate_limit(operation) when is_atom(operation) do
    limits = get_global_limits(operation)

    # If no global limit configured, allow operation
    if limits == :none do
      :ok
    else
      now = System.system_time(:second)
      lookup_key = {:global, operation}

      # Get all timestamps for this global key
      timestamps =
        case :ets.lookup(@table_name, lookup_key) do
          [{^lookup_key, ts}] -> ts
          [] -> []
        end

      # Filter to timestamps within the window
      window_start = now - limits.window_seconds
      recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

      # Check if global limit exceeded
      if length(recent_timestamps) >= limits.limit do
        # Calculate retry-after time
        oldest_recent = Enum.min(recent_timestamps)
        retry_after = oldest_recent + limits.window_seconds - now

        {:error, :rate_limit_exceeded, max(retry_after, 1)}
      else
        :ok
      end
    end
  end

  @doc """
  Records an attempt for per-session rate limiting tracking.

  Should be called after a successful operation to track it for rate limiting.
  For operations with global rate limiting, also call record_global_attempt/1.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)
  - `key` - The unique identifier (e.g., session_id)

  ## Examples

      iex> RateLimit.record_attempt(:resume, "abc-123")
      :ok
  """
  @spec record_attempt(atom(), String.t()) :: :ok
  def record_attempt(operation, key) when is_atom(operation) and is_binary(key) do
    now = System.system_time(:second)
    lookup_key = {operation, key}
    limits = get_limits(operation)

    # Get current timestamps or initialize empty list
    timestamps =
      case :ets.lookup(@table_name, lookup_key) do
        [{^lookup_key, ts}] -> ts
        [] -> []
      end

    # Prepend new timestamp and bound list to prevent unbounded growth
    # Cap at 2x limit to maintain recent history while preventing memory leaks
    max_entries = limits.limit * 2

    updated_timestamps =
      [now | timestamps]
      |> Enum.take(max_entries)

    # Store updated list
    :ets.insert(@table_name, {lookup_key, updated_timestamps})

    :ok
  end

  @doc """
  Records an attempt for global rate limiting tracking.

  Should be called after a successful operation to track it globally.
  This prevents bypass attacks where multiple sessions are created to
  circumvent per-session rate limits.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)

  ## Examples

      iex> RateLimit.record_global_attempt(:resume)
      :ok
  """
  @spec record_global_attempt(atom()) :: :ok
  def record_global_attempt(operation) when is_atom(operation) do
    limits = get_global_limits(operation)

    # If no global limit configured, skip recording
    if limits == :none do
      :ok
    else
      now = System.system_time(:second)
      lookup_key = {:global, operation}

      # Get current timestamps or initialize empty list
      timestamps =
        case :ets.lookup(@table_name, lookup_key) do
          [{^lookup_key, ts}] -> ts
          [] -> []
        end

      # Prepend new timestamp and bound list
      max_entries = limits.limit * 2

      updated_timestamps =
        [now | timestamps]
        |> Enum.take(max_entries)

      # Store updated list
      :ets.insert(@table_name, {lookup_key, updated_timestamps})

      :ok
    end
  end

  @doc """
  Atomically checks rate limit and records attempt if allowed.

  This is the recommended function to use as it prevents TOCTOU (Time-of-Check-Time-of-Use)
  race conditions that can occur when check_rate_limit/2 and record_attempt/2 are called
  separately.

  ## Parameters

  - `operation` - The operation type (`:resume`, etc.)
  - `key` - The unique identifier (e.g., session_id)

  ## Returns

  - `:ok` - Operation allowed and attempt recorded
  - `{:error, :rate_limit_exceeded, retry_after}` - Rate limit exceeded

  ## Examples

      iex> RateLimit.check_and_record_attempt(:resume, "abc-123")
      :ok

      iex> # After 5 attempts in quick succession...
      iex> RateLimit.check_and_record_attempt(:resume, "abc-123")
      {:error, :rate_limit_exceeded, 45}
  """
  @spec check_and_record_attempt(atom(), String.t()) ::
          :ok | {:error, :rate_limit_exceeded, pos_integer()}
  def check_and_record_attempt(operation, key) when is_atom(operation) and is_binary(key) do
    limits = get_limits(operation)
    now = System.system_time(:second)
    lookup_key = {operation, key}

    # Get current timestamps or initialize empty list
    timestamps =
      case :ets.lookup(@table_name, lookup_key) do
        [{^lookup_key, ts}] -> ts
        [] -> []
      end

    # Filter to timestamps within the window
    window_start = now - limits.window_seconds
    recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

    # Check if limit exceeded
    if length(recent_timestamps) >= limits.limit do
      # Calculate retry-after time
      oldest_recent = Enum.min(recent_timestamps)
      retry_after = oldest_recent + limits.window_seconds - now

      {:error, :rate_limit_exceeded, max(retry_after, 1)}
    else
      # Atomically record the attempt
      # Prepend new timestamp and bound list
      max_entries = limits.limit * 2

      updated_timestamps =
        [now | timestamps]
        |> Enum.take(max_entries)

      :ets.insert(@table_name, {lookup_key, updated_timestamps})

      :ok
    end
  end

  @doc """
  Resets rate limit for a specific key.

  Useful for testing or administrative overrides.

  ## Examples

      iex> RateLimit.reset(:resume, "abc-123")
      :ok
  """
  @spec reset(atom(), String.t()) :: :ok
  def reset(operation, key) when is_atom(operation) and is_binary(key) do
    :ets.delete(@table_name, {operation, key})
    :ok
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for rate limit tracking
    :ets.new(@table_name, [:named_table, :public, :set])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("[RateLimit] Initialized with table #{@table_name}")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp get_limits(operation) do
    config_limits = Application.get_env(:jido_code, :rate_limits, [])
    operation_config = Keyword.get(config_limits, operation)

    case operation_config do
      nil ->
        # Use default
        default_limits()
        |> Map.get(operation, %{limit: 10, window_seconds: 60})

      config when is_list(config) ->
        %{
          limit: Keyword.get(config, :limit, 10),
          window_seconds: Keyword.get(config, :window_seconds, 60)
        }

      config when is_map(config) ->
        config
    end
  end

  # Returns default rate limits (configurable via runtime.exs)
  defp default_limits do
    %{
      resume: %{limit: 5, window_seconds: 60}
    }
  end

  defp get_global_limits(operation) do
    config_limits = Application.get_env(:jido_code, :global_rate_limits, [])
    operation_config = Keyword.get(config_limits, operation)

    case operation_config do
      nil ->
        # Use default global limits
        default_global_limits()
        |> Map.get(operation, :none)

      false ->
        # Explicitly disabled
        :none

      config when is_list(config) ->
        %{
          limit: Keyword.get(config, :limit, 20),
          window_seconds: Keyword.get(config, :window_seconds, 60)
        }

      config when is_map(config) ->
        config
    end
  end

  # Returns default global rate limits (configurable via runtime.exs)
  # Global limits should be higher than per-session limits to allow
  # legitimate multi-session use while preventing abuse
  defp default_global_limits do
    %{
      # Allow 20 resumes per minute across all sessions (vs 5 per session)
      resume: %{limit: 20, window_seconds: 60}
    }
  end

  # Returns cleanup interval (configurable via runtime.exs)
  defp cleanup_interval do
    Application.get_env(:jido_code, :rate_limits, [])
    |> Keyword.get(:cleanup_interval, :timer.minutes(1))
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, cleanup_interval())
  end

  defp cleanup_expired_entries do
    now = System.system_time(:second)

    # Iterate through all entries and remove expired timestamps
    :ets.foldl(
      fn {{operation, _key} = lookup_key, timestamps}, acc ->
        limits = get_limits(operation)
        window_start = now - limits.window_seconds

        # Keep only timestamps within the window
        recent_timestamps = Enum.filter(timestamps, fn ts -> ts > window_start end)

        if Enum.empty?(recent_timestamps) do
          # No recent attempts, delete the entry
          :ets.delete(@table_name, lookup_key)
        else
          # Update with filtered timestamps
          :ets.insert(@table_name, {lookup_key, recent_timestamps})
        end

        acc
      end,
      nil,
      @table_name
    )

    :ok
  end
end
