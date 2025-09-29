defmodule ExSolana.Jito.BlockEngineClient do
  @moduledoc """
  Client for interacting with Jito's Block Engine using gRPC.
  """

  use GenServer

  alias ExSolana.Jito.BlockEngine.AccountsOfInterestRequest
  alias ExSolana.Jito.BlockEngine.BlockBuilderFeeInfoRequest
  alias ExSolana.Jito.BlockEngine.BlockEngineRelayer.Stub, as: RelayerStub
  alias ExSolana.Jito.BlockEngine.BlockEngineValidator.Stub, as: ValidatorStub
  alias ExSolana.Jito.BlockEngine.PacketBatchUpdate
  alias ExSolana.Jito.BlockEngine.ProgramsOfInterestRequest
  alias ExSolana.Jito.BlockEngine.SubscribeBundlesRequest
  alias ExSolana.Jito.BlockEngine.SubscribePacketsRequest

  require Logger

  def start_link(channel) do
    GenServer.start_link(__MODULE__, channel)
  end

  @impl true
  def init(channel) do
    {:ok, %{channel: channel, streams: %{}}}
  end

  # Client API

  def subscribe_packets(pid) do
    GenServer.call(pid, :subscribe_packets)
  end

  def subscribe_bundles(pid) do
    GenServer.call(pid, :subscribe_bundles)
  end

  def get_block_builder_fee_info(pid) do
    GenServer.call(pid, :get_block_builder_fee_info)
  end

  def subscribe_accounts_of_interest(pid) do
    GenServer.call(pid, :subscribe_accounts_of_interest)
  end

  def subscribe_programs_of_interest(pid) do
    GenServer.call(pid, :subscribe_programs_of_interest)
  end

  def start_expiring_packet_stream(pid) do
    GenServer.call(pid, :start_expiring_packet_stream)
  end

  def send_packet_batch_update(pid, update) do
    GenServer.cast(pid, {:send_packet_batch_update, update})
  end

  # Server callbacks

  @impl true
  def handle_call(:subscribe_packets, _from, %{channel: channel} = state) do
    request = %SubscribePacketsRequest{}
    {:ok, stream} = ValidatorStub.subscribe_packets(channel, request)
    {:reply, :ok, put_in(state, [:streams, :packets], stream)}
  end

  @impl true
  def handle_call(:subscribe_bundles, _from, %{channel: channel} = state) do
    request = %SubscribeBundlesRequest{}
    {:ok, stream} = ValidatorStub.subscribe_bundles(channel, request)
    {:reply, :ok, put_in(state, [:streams, :bundles], stream)}
  end

  @impl true
  def handle_call(:get_block_builder_fee_info, _from, %{channel: channel} = state) do
    request = %BlockBuilderFeeInfoRequest{}
    {:ok, response} = ValidatorStub.get_block_builder_fee_info(channel, request)
    {:reply, response, state}
  end

  @impl true
  def handle_call(:subscribe_accounts_of_interest, _from, %{channel: channel} = state) do
    request = %AccountsOfInterestRequest{}
    {:ok, stream} = RelayerStub.subscribe_accounts_of_interest(channel, request)
    {:reply, :ok, put_in(state, [:streams, :accounts_of_interest], stream)}
  end

  @impl true
  def handle_call(:subscribe_programs_of_interest, _from, %{channel: channel} = state) do
    request = %ProgramsOfInterestRequest{}
    {:ok, stream} = RelayerStub.subscribe_programs_of_interest(channel, request)
    {:reply, :ok, put_in(state, [:streams, :programs_of_interest], stream)}
  end

  @impl true
  def handle_call(:start_expiring_packet_stream, _from, %{channel: channel} = state) do
    {:ok, stream} = RelayerStub.start_expiring_packet_stream(channel)
    {:reply, :ok, put_in(state, [:streams, :expiring_packet], stream)}
  end

  @impl true
  def handle_cast({:send_packet_batch_update, update}, %{streams: %{expiring_packet: stream}} = state) do
    GRPC.Stub.send_request(stream, %PacketBatchUpdate{msg: {:batches, update}})
    {:noreply, state}
  end

  @impl true
  def handle_info({:gun_data, _pid, _stream, :fin, data}, state) do
    handle_stream_data(data, state)
  end

  @impl true
  def handle_info({:gun_data, _pid, _stream, :nofin, data}, state) do
    handle_stream_data(data, state)
  end

  defp handle_stream_data(data, state) do
    # Here you would implement the logic to decode the data based on the stream type
    # For example:
    {:ok, decoded_data} = decode_stream_data(data)
    Logger.info("Received stream data: #{inspect(decoded_data)}")
    # Process the decoded data as needed
    {:noreply, state}
  end

  defp decode_stream_data(data) do
    # Implement the decoding logic here based on the expected message types
    # You might need to pattern match on the data to determine which type of message it is
    # and use the appropriate decode function
    {:ok, data}
  end
end
