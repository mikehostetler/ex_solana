defmodule ExSolana.RPC.BlockhashServer do
  @moduledoc """
  A GenServer that maintains a fresh blockhash for transaction building.

  Fetches the latest blockhash at regular intervals and provides it to callers.
  Useful for applications that need to build multiple transactions and want to
  avoid fetching the blockhash for each transaction.
  """
  use GenServer

  alias ExSolana.RPC

  require Logger

  @fetch_interval 60_000

  @doc """
  Returns a child specification for starting the Blockhash Server under a supervisor.

  ## Options

    * `:name` - The name to register the server process (default: ExSolana.RPC.BlockhashServer)
    * `:client` - An existing RPC client to use (required)
    * `:fetch_interval` - The interval in milliseconds between blockhash fetches (default: 60_000)

  ## Example

      children = [
        {ExSolana.RPC.BlockhashServer,
         name: MyApp.BlockhashServer, client: my_rpc_client, fetch_interval: 30_000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts a `ExSolana.RPC.BlockhashServer` process linked to the current process.

  ## Options

    * `:name` - The name to register the server process (optional)
    * `:client` - An existing RPC client to use (required)
    * `:fetch_interval` - The interval in milliseconds between blockhash fetches (default: 60_000)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    client = Keyword.fetch!(opts, :client)
    fetch_interval = Keyword.get(opts, :fetch_interval, @fetch_interval)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {client, fetch_interval}, name: name)
  end

  @doc """
  Gets the latest blockhash from the server.

  Returns the cached blockhash if available, or fetches a new one if the cache is empty.

  ## Returns

    * `{:ok, blockhash}` - The latest blockhash as a binary string
    * `{:error, reason}` - If fetching the blockhash fails
  """
  @spec get_latest_blockhash() :: {:ok, binary()} | {:error, any()}
  def get_latest_blockhash(server \\ __MODULE__) do
    GenServer.call(server, :get_latest_blockhash)
  end

  @doc """
  Gets the current state of the Blockhash Server (for testing purposes).

  Returns a map containing:
    * `:client` - The RPC client being used
    * `:blockhash` - The currently cached blockhash (may be nil)
    * `:fetch_interval` - The interval between fetches
    * `:last_fetch_time` - The timestamp of the last successful fetch
  """
  @spec get_state() :: map()
  def get_state(server \\ __MODULE__) do
    GenServer.call(server, :get_state)
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
