defmodule ExSolana.Jito.SearcherClient do
  @moduledoc """
  Client for interacting with Jito's Searcher Service using gRPC.
  """

  use GenServer

  alias ExSolana.Jito.Bundle.BundleResult
  alias ExSolana.Jito.Searcher.ConnectedLeadersRegionedRequest
  alias ExSolana.Jito.Searcher.ConnectedLeadersRequest
  alias ExSolana.Jito.Searcher.GetRegionsRequest
  alias ExSolana.Jito.Searcher.GetTipAccountsRequest
  alias ExSolana.Jito.Searcher.NextScheduledLeaderRequest
  alias ExSolana.Jito.Searcher.SearcherService.Stub
  alias ExSolana.Jito.Searcher.SendBundleResponse
  alias ExSolana.Jito.Searcher.SubscribeBundleResultsRequest

  require Logger

  # Updated start_link to accept URL and params
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    url = Keyword.get(opts, :url)
    GenServer.start_link(__MODULE__, {url, opts}, name: name)
  end

  @impl true
  def init({url, opts}) do
    case ExSolana.Jito.new(url, opts) do
      {:ok, channel} ->
        bundle_table =
          case :ets.whereis(:bundles) do
            :undefined -> :ets.new(:bundles, [:set, :public, :named_table])
            existing_table -> existing_table
          end

        {:ok,
         %{
           channel: channel,
           url: url,
           opts: opts,
           bundle_results_stream: nil,
           bundle_table: bundle_table
         }}

      {:error, reason} ->
        Logger.error("Failed to connect to Jito: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  # Client API

  def send_bundle(pid, request) do
    GenServer.call(pid, {:send_bundle, request})
  end

  def get_next_scheduled_leader(pid, regions) do
    GenServer.call(pid, {:get_next_scheduled_leader, regions})
  end

  def get_connected_leaders(pid) do
    GenServer.call(pid, :get_connected_leaders)
  end

  def get_connected_leaders_regioned(pid, regions) do
    GenServer.call(pid, {:get_connected_leaders_regioned, regions})
  end

  def get_tip_accounts(pid) do
    GenServer.call(pid, :get_tip_accounts)
  end

  def get_regions(pid) do
    GenServer.call(pid, :get_regions)
  end

  def subscribe_bundle_results(pid) do
    GenServer.call(pid, :subscribe_bundle_results)
  end

  def get_bundle_status(pid, bundle_id) do
    GenServer.call(pid, {:get_bundle_status, bundle_id})
  end

  # Server callbacks

  @impl true
  def handle_call({:send_bundle, request}, _from, %{channel: channel} = state) do
    # request = %SendBundleRequest{bundle: bundle}

    case Stub.send_bundle(channel, request) do
      {:ok, %SendBundleResponse{uuid: uuid}} ->
        Logger.info("Inserting bundle result into ETS: #{inspect(uuid)}")
        :ets.insert(state.bundle_table, {uuid, :sent})
        {:reply, {:ok, uuid}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_next_scheduled_leader, regions}, _from, %{channel: channel} = state) do
    request = %NextScheduledLeaderRequest{regions: regions}
    {:ok, response} = Stub.get_next_scheduled_leader(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call(:get_connected_leaders, _from, %{channel: channel} = state) do
    request = %ConnectedLeadersRequest{}
    {:ok, response} = Stub.get_connected_leaders(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call({:get_connected_leaders_regioned, regions}, _from, %{channel: channel} = state) do
    request = %ConnectedLeadersRegionedRequest{regions: regions}
    {:ok, response} = Stub.get_connected_leaders_regioned(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call(:get_tip_accounts, _from, %{channel: channel} = state) do
    request = %GetTipAccountsRequest{}
    {:ok, response} = Stub.get_tip_accounts(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call(:get_regions, _from, %{channel: channel} = state) do
    request = %GetRegionsRequest{}
    {:ok, response} = Stub.get_regions(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call(:subscribe_bundle_results, _from, %{channel: channel} = state) do
    request = %SubscribeBundleResultsRequest{}

    case Stub.subscribe_bundle_results(channel, request) do
      {:ok, stream} ->
        Task.start_link(fn -> process_bundle_results(stream, self()) end)
        {:reply, :ok, %{state | bundle_results_stream: stream}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_bundle_status, bundle_id}, _from, state) do
    status =
      case :ets.lookup(state.bundle_table, bundle_id) do
        [{^bundle_id, status}] -> status
        [] -> :unknown
      end

    {:reply, status, state}
  end

  @impl true
  def handle_info({:bundle_result, %BundleResult{} = result}, state) do
    Logger.info("Storing bundle result in ETS: #{inspect(result)}")
    :ets.insert(state.bundle_table, {result.bundle_id, result.result})
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_data, _pid, _stream, :fin, data}, state) do
    handle_bundle_result(data, state)
  end

  @impl true
  def handle_info({:gun_data, _pid, _stream, :nofin, data}, state) do
    handle_bundle_result(data, state)
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    # Handle normal exit gracefully
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp handle_bundle_result(data, state) do
    case BundleResult.decode(data) do
      {:ok, bundle_result} ->
        Logger.info("Received bundle result: #{inspect(bundle_result)}")
        # Here you can add any additional processing for the bundle result
        {:noreply, state}

      {:error, error} ->
        Logger.error("Error decoding bundle result: #{inspect(error)}")
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{channel: channel, bundle_table: table}) do
    Logger.info("Terminating SearcherClient")
    :ets.delete(table)
    GRPC.Stub.disconnect(channel)
  end

  defp process_bundle_results(stream, pid) do
    Enum.each(stream, fn
      {:ok, result} ->
        Logger.info("Processing bundle result: #{inspect(result)}")
        send(pid, {:bundle_result, result})

      {:error, reason} ->
        Logger.error("Error processing bundle result: #{inspect(reason)}")
    end)
  end
end
