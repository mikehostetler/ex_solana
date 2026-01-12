defmodule ExSolana.Geyser.YellowstoneClient do
  @moduledoc """
  GenServer-based client for interacting with the Yellowstone Geyser gRPC service.
  """

  use GenServer

  alias ExSolana.Geyser.GetBlockHeightRequest
  alias ExSolana.Geyser.GetLatestBlockhashRequest
  alias ExSolana.Geyser.GetSlotRequest
  alias ExSolana.Geyser.GetVersionRequest
  alias ExSolana.Geyser.Geyser.Stub
  alias ExSolana.Geyser.IsBlockhashValidRequest
  alias ExSolana.Geyser.PingRequest

  require Logger

  # Client API

  @doc """
  Starts the YellowstoneClient GenServer.

  ## Parameters

  - url: The URL of the Yellowstone Geyser service
  - token: The authentication token
  - opts: Additional options for the gRPC connection

  ## Returns

  A tuple containing :ok and the pid of the started GenServer, or :error and the reason.
  """
  def start_link(url, token, opts \\ []) do
    GenServer.start_link(__MODULE__, {url, token, opts})
  end

  @doc """
  Subscribes to updates from the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - request: The SubscribeRequest struct

  ## Returns

  A stream of SubscribeUpdate structs.
  """
  def subscribe(pid, request) do
    GenServer.call(pid, {:subscribe, request})
  end

  def unsubscribe(pid) do
    GenServer.cast(pid, :unsubscribe)
  end

  @doc """
  Sends a ping to the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - count: The ping count

  ## Returns

  A PongResponse struct.
  """
  def ping(pid, count) do
    GenServer.call(pid, {:ping, count})
  end

  @doc """
  Gets the latest blockhash from the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - commitment: The commitment level (optional)

  ## Returns

  A GetLatestBlockhashResponse struct.
  """
  def get_latest_blockhash(pid, commitment \\ nil) do
    GenServer.call(pid, {:get_latest_blockhash, commitment})
  end

  @doc """
  Gets the current block height from the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - commitment: The commitment level (optional)

  ## Returns

  A GetBlockHeightResponse struct.
  """
  def get_block_height(pid, commitment \\ nil) do
    GenServer.call(pid, {:get_block_height, commitment})
  end

  @doc """
  Gets the current slot from the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - commitment: The commitment level (optional)

  ## Returns

  A GetSlotResponse struct.
  """
  def get_slot(pid, commitment \\ nil) do
    GenServer.call(pid, {:get_slot, commitment})
  end

  @doc """
  Checks if a blockhash is valid.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer
  - blockhash: The blockhash to check
  - commitment: The commitment level (optional)

  ## Returns

  An IsBlockhashValidResponse struct.
  """
  def is_blockhash_valid(pid, blockhash, commitment \\ nil) do
    GenServer.call(pid, {:is_blockhash_valid, blockhash, commitment})
  end

  @doc """
  Gets the version of the Yellowstone Geyser service.

  ## Parameters

  - pid: The pid of the YellowstoneClient GenServer

  ## Returns

  A GetVersionResponse struct.
  """
  def get_version(pid) do
    GenServer.call(pid, :get_version)
  end

  # Server Callbacks

  @impl true
  def init({url, token, opts}) do
    case ExSolana.Geyser.new(url, Keyword.put(opts, :token, token)) do
      {:ok, channel} ->
        {:ok, %{channel: channel, url: url, token: token, opts: opts, subscription: nil}}

      {:error, reason} ->
        Logger.error("Failed to connect to Yellowstone Geyser service: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast(:unsubscribe, %{subscription: subscription} = state)
      when not is_nil(subscription) do
    Task.shutdown(subscription)
    {:noreply, %{state | subscription: nil}}
  end

  @impl true
  def handle_cast(:unsubscribe, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, result}, %{subscription: %Task{ref: ref}} = state) do
    # The Task completed
    Logger.info("Subscription task completed: #{inspect(result)}")
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | subscription: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{subscription: %Task{ref: ref}} = state) do
    # The Task died
    Logger.warning("Subscription task died: #{inspect(reason)}")
    {:noreply, %{state | subscription: nil}}
  end

  @impl true
  def handle_call({:subscribe, request}, _from, %{channel: channel, subscription: nil} = state) do
    Logger.info("Initiating subscription to Yellowstone Geyser service")

    stream = Stub.subscribe(channel)

    case GRPC.Stub.send_request(stream, request) do
      %GRPC.Client.Stream{} = updated_stream ->
        Logger.info("Request sent successfully")

        # Start a Task to manage the stream
        task = Task.async(fn -> manage_stream(updated_stream) end)

        {:reply, {:ok, task}, %{state | subscription: task}}

      error ->
        Logger.error("Failed to send request: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, _request}, _from, %{subscription: subscription} = state)
      when not is_nil(subscription) do
    {:reply, {:error, :already_subscribed}, state}
  end

  @impl true
  def handle_call({:ping, count}, _from, %{channel: channel} = state) do
    {:reply, Stub.ping(channel, struct(PingRequest, count: count)), state}
  end

  @impl true
  def handle_call({:get_latest_blockhash, commitment}, _from, %{channel: channel} = state) do
    {:reply,
     Stub.get_latest_blockhash(
       channel,
       struct(GetLatestBlockhashRequest, commitment: commitment)
     ), state}
  end

  @impl true
  def handle_call({:get_block_height, commitment}, _from, %{channel: channel} = state) do
    {:reply,
     Stub.get_block_height(channel, struct(GetBlockHeightRequest, commitment: commitment)), state}
  end

  @impl true
  def handle_call({:get_slot, commitment}, _from, %{channel: channel} = state) do
    {:reply, Stub.get_slot(channel, struct(GetSlotRequest, commitment: commitment)), state}
  end

  @impl true
  def handle_call(
        {:is_blockhash_valid, blockhash, commitment},
        _from,
        %{channel: channel} = state
      ) do
    {:reply,
     Stub.is_blockhash_valid(
       channel,
       struct(IsBlockhashValidRequest, blockhash: blockhash, commitment: commitment)
     ), state}
  end

  @impl true
  def handle_call(:get_version, _from, %{channel: channel} = state) do
    {:reply, Stub.get_version(channel, struct(GetVersionRequest)), state}
  end

  @impl true
  def terminate(_reason, %{channel: channel, subscription: subscription}) do
    Logger.info("Terminating YellowstoneClient")
    if subscription, do: Task.shutdown(subscription)
    GRPC.Stub.disconnect(channel)
  end

  defp manage_stream(stream) do
    case GRPC.Stub.recv(stream) do
      {:ok, reply_enum} ->
        Logger.info("Successfully subscribed to Yellowstone Geyser service")

        Stream.run(
          Stream.each(reply_enum, fn
            {:ok, reply} ->
              Logger.info("Received message: #{inspect(reply)}")

            {:error, error} ->
              Logger.error("Error in stream: #{inspect(error)}")

            {:trailers, trailers} ->
              Logger.info("Received trailers: #{inspect(trailers)}")
          end)
        )

      {:error, error} ->
        Logger.error("Failed to receive from Yellowstone Geyser service: #{inspect(error)}")
        {:error, error}
    end
  end
end
