defmodule ExSolana.RPC.BlockhashServer do
  @moduledoc false
  use GenServer

  alias ExSolana.RPC

  require Logger

  @fetch_interval 60_000

  # Client API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    client = Keyword.fetch!(opts, :client)
    fetch_interval = Keyword.get(opts, :fetch_interval, @fetch_interval)
    GenServer.start_link(__MODULE__, {client, fetch_interval}, name: __MODULE__)
  end

  @spec get_latest_blockhash() :: {:ok, binary()} | {:error, any()}
  def get_latest_blockhash do
    GenServer.call(__MODULE__, :get_latest_blockhash)
  end

  # For testing purposes
  @spec get_state() :: map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server Callbacks

  @impl true
  def init({client, fetch_interval}) do
    state = %{
      client: client,
      blockhash: nil,
      fetch_interval: fetch_interval,
      last_fetch_time: nil
    }

    send(self(), :fetch_blockhash)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_latest_blockhash, _from, %{blockhash: nil} = state) do
    case fetch_blockhash(state.client) do
      {:ok, blockhash} ->
        new_state = %{
          state
          | blockhash: blockhash,
            last_fetch_time: System.monotonic_time(:millisecond)
        }

        {:reply, {:ok, blockhash}, new_state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_latest_blockhash, _from, state) do
    {:reply, {:ok, state.blockhash}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:fetch_blockhash, state) do
    new_state =
      case fetch_blockhash(state.client) do
        {:ok, blockhash} ->
          %{state | blockhash: blockhash, last_fetch_time: System.monotonic_time(:millisecond)}

        {:error, reason} ->
          Logger.warning("Failed to fetch blockhash: #{inspect(reason)}")
          state
      end

    Process.send_after(self(), :fetch_blockhash, state.fetch_interval)
    {:noreply, new_state}
  end

  # Private Functions

  defp fetch_blockhash(client) when is_function(client, 0) do
    client.()
  end

  defp fetch_blockhash(client) do
    case RPC.send(client, RPC.Request.get_latest_blockhash()) do
      {:ok, %{"blockhash" => blockhash}} -> {:ok, blockhash}
      error -> error
    end
  end
end
