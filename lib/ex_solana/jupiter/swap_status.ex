defmodule ExSolana.Jupiter.SwapStatus do
  @moduledoc """
  Monitor and track Jupiter swap transaction status.

  This GenServer tracks the status of swap transactions by polling the Solana RPC
  for confirmation status. It automatically removes completed swaps after a period
  of time to prevent memory leaks.

  ## Usage

  First, start the SwapStatus server:

      {:ok, pid} = ExSolana.Jupiter.SwapStatus.start_link()

  Then track a swap transaction:

      :ok = ExSolana.Jupiter.SwapStatus.track("transaction_signature")

  Poll for status updates:

      case ExSolana.Jupiter.SwapStatus.get_status("transaction_signature") do
        {:ok, :completed} -> IO.puts("Swap completed successfully!")
        {:ok, {:failed, reason}} -> IO.puts("Swap failed: #{reason}")
        {:ok, :pending} -> IO.puts("Swap still pending...")
        {:error, :not_found} -> IO.puts("Swap not being tracked")
      end

  Stop tracking when done:

      :ok = ExSolana.Jupiter.SwapStatus.untrack("transaction_signature")

  ## Server Configuration

  You can configure the server options:

      {:ok, pid} = ExSolana.Jupiter.SwapStatus.start_link(
        name: :my_swap_tracker,
        check_interval: 3_000,  # Check every 3 seconds
        cleanup_after: 300_000  # Remove after 5 minutes
      )

  """

  use GenServer
  require Logger

  @type status :: :pending | :completed | {:failed, String.t()}

  @type swap_info :: %{
          signature: String.t(),
          status: status(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          attempts: non_neg_integer()
        }

  @type option :: {:name, atom()} | {:check_interval, pos_integer()} | {:cleanup_after, pos_integer()}

  @default_check_interval 5_000
  @default_cleanup_after 300_000

  # Client API

  @doc """
  Starts the SwapStatus GenServer.

  ## Options

  * `:name` - The name to register the GenServer. Defaults to `__MODULE__`
  * `:check_interval` - How often to check swap status (ms). Defaults to 5000
  * `:cleanup_after` - How long to keep completed swaps (ms). Defaults to 300000

  """
  @spec start_link([option]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {gen_opts, init_opts} =
      Keyword.split(opts, [:name, :debug, :timeout, :spawn_opt, :hibernate_after])

    name = Keyword.get(gen_opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, init_opts, Keyword.put(gen_opts, :name, name))
  end

  @doc """
  Track a swap transaction by signature.

  Returns `:ok` if the swap is now being tracked.
  Returns `{:error, reason}` if the signature is invalid.

  """
  @spec track(String.t()) :: :ok | {:error, term()}
  def track(signature) when is_binary(signature) do
    GenServer.call(__MODULE__, {:track, signature})
  end

  def track(_), do: {:error, :invalid_signature}

  @doc """
  Get the current status of a tracked swap.

  Returns:
  * `{:ok, :pending}` - Swap is still pending
  * `{:ok, :completed}` - Swap completed successfully
  * `{:ok, {:failed, reason}}` - Swap failed with reason
  * `{:error, :not_found}` - Swap is not being tracked

  """
  @spec get_status(String.t()) :: {:ok, status()} | {:error, :not_found}
  def get_status(signature) when is_binary(signature) do
    GenServer.call(__MODULE__, {:get_status, signature})
  end

  def get_status(_), do: {:error, :invalid_signature}

  @doc """
  Stop tracking a swap.

  Returns `:ok` if the swap was removed from tracking.
  Returns `{:error, :not_found}` if the swap was not being tracked.

  """
  @spec untrack(String.t()) :: :ok | {:error, :not_found}
  def untrack(signature) when is_binary(signature) do
    GenServer.call(__MODULE__, {:untrack, signature})
  end

  def untrack(_), do: {:error, :invalid_signature}

  @doc """
  Get all currently tracked swaps.

  Returns a map of transaction signatures to their status.

  """
  @spec list_tracked() :: %{String.t() => status()}
  def list_tracked do
    GenServer.call(__MODULE__, :list_tracked)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    cleanup_after = Keyword.get(opts, :cleanup_after, @default_cleanup_after)

    client = ExSolana.rpc_client()

    # Schedule periodic status checks
    schedule_status_check(check_interval)

    {:ok,
     %{
       tracked_swaps: %{},
       client: client,
       check_interval: check_interval,
       cleanup_after: cleanup_after
     }}
  end

  @impl true
  def handle_call({:track, signature}, _from, state) do
    swap_info = %{
      signature: signature,
      status: :pending,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      attempts: 0
    }

    new_swaps = Map.put(state.tracked_swaps, signature, swap_info)

    Logger.debug("Tracking Jupiter swap: #{signature}")

    {:reply, :ok, %{state | tracked_swaps: new_swaps}}
  end

  def handle_call({:get_status, signature}, _from, state) do
    case Map.get(state.tracked_swaps, signature) do
      nil ->
        {:reply, {:error, :not_found}, state}

      swap_info ->
        {:reply, {:ok, swap_info.status}, state}
    end
  end

  def handle_call({:untrack, signature}, _from, state) do
    case Map.get(state.tracked_swaps, signature) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _swap_info ->
        new_swaps = Map.delete(state.tracked_swaps, signature)
        Logger.debug("No longer tracking Jupiter swap: #{signature}")
        {:reply, :ok, %{state | tracked_swaps: new_swaps}}
    end
  end

  def handle_call(:list_tracked, _from, state) do
    tracked =
      Map.new(state.tracked_swaps, fn {sig, info} ->
        {sig, info.status}
      end)

    {:reply, tracked, state}
  end

  @impl true
  def handle_info(:check_statuses, state) do
    updated_swaps = check_all_swap_statuses(state.tracked_swaps, state.client)

    # Remove completed swaps after cleanup_after period
    now = DateTime.utc_now()
    cleanup_after_ms = state.cleanup_after

    swaps_to_keep =
      Enum.filter(updated_swaps, fn {_sig, info} ->
        DateTime.diff(now, info.updated_at) * 1000 < cleanup_after_ms or
          info.status == :pending
      end)

    # Log removed swaps
    removed_count = map_size(updated_swaps) - length(swaps_to_keep)
    if removed_count > 0 do
      Logger.debug("Cleaned up #{removed_count} completed Jupiter swap(s)")
    end

    schedule_status_check(state.check_interval)

    {:noreply, %{state | tracked_swaps: Map.new(swaps_to_keep)}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in SwapStatus: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helpers

  defp schedule_status_check(interval) do
    Process.send_after(self(), :check_statuses, interval)
  end

  defp check_all_swap_statuses(swaps, client) do
    Enum.map(swaps, fn {signature, swap_info} ->
      new_info = check_swap_status(signature, swap_info, client)
      {signature, new_info}
    end)
  end

  defp check_swap_status(signature, swap_info, client) do
    case ExSolana.RPC.send(
           client,
           ExSolana.RPC.Request.get_signature_statuses([signature])
         ) do
      {:ok, %{"result" => [status | _]}} when not is_nil(status) ->
        updated_info = update_swap_info(swap_info, status)
        updated_info

      {:ok, %{"result" => result}} when is_list(result) do
        # Status is nil, still pending
        swap_info

      {:error, reason} ->
        Logger.warning("Failed to check swap status for #{signature}: #{inspect(reason)}")
        swap_info

      {:ok, _} ->
        swap_info
    end
  end

  defp update_swap_info(swap_info, %{"confirmationStatus" => status, "err" => nil}) do
    new_status =
      case status do
        "confirmed" -> :completed
        "finalized" -> :completed
        _ -> :pending
      end

    %{swap_info | status: new_status, updated_at: DateTime.utc_now(), attempts: swap_info.attempts + 1}
  end

  defp update_swap_info(swap_info, %{"err" => error}) do
    %{swap_info | status: {:failed, inspect(error)}, updated_at: DateTime.utc_now(), attempts: swap_info.attempts + 1}
  end

  defp update_swap_info(swap_info, _status) do
    %{swap_info | updated_at: DateTime.utc_now(), attempts: swap_info.attempts + 1}
  end
end
