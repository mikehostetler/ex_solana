defmodule ExSolana.Geyser.Producer do
  @moduledoc false
  use GenStage
  use ExSolana.Util.DebugTools, debug_enabled: false

  alias Broadway.Message

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :channel,
      :stream,
      :reply_enum,
      :stream_request,
      :url,
      :token,
      :previous_stream_request
    ]
  end

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %State{
      stream_request: opts[:stream_request],
      previous_stream_request: opts[:stream_request],
      url: opts[:url],
      token: opts[:token]
    }

    debug("Initialized producer", state: state)

    {:producer, state}
  end

  def update_stream_request(pid, new_request) do
    debug("Updating stream request", new_request: new_request)
    GenStage.cast(pid, {:update_stream_request, new_request})
  end

  @impl true
  def handle_cast({:update_stream_request, new_request}, state) do
    debug("Handling update stream request cast", new_request: new_request)

    {:ok, new_state} = update_subscription(state, new_request)
    debug("Subscription updated successfully", new_state: new_state)
    {:noreply, [], new_state}
  end

  @impl true
  def handle_demand(demand, state) do
    {events, new_state} = fetch_events(demand, state)
    {:noreply, events, new_state}
  end

  defp fetch_events(demand, %{channel: nil} = state) do
    debug("Fetching events with no channel", demand: demand, state: state)

    case connect(state) do
      {:ok, new_state} ->
        debug("Successfully connected, retrying fetch_events", new_state: new_state)
        fetch_events(demand, new_state)

      {:error, error} ->
        debug("Failed to connect", error: error)
        {[], state}
    end
  end

  defp fetch_events(demand, %{reply_enum: reply_enum} = state) do
    debug("Fetching events from reply_enum", demand: demand)

    events =
      reply_enum
      |> Stream.take(demand)
      |> Stream.flat_map(fn
        {:ok, message} ->
          debug("Received valid message", message: message)
          [wrap_message(message)]

        {:error, error} ->
          debug("Received error message", error: error)
          []
      end)
      |> Enum.to_list()

    debug("Fetched events", count: length(events))
    {events, state}
  end

  defp connect(%{url: url, token: token, stream_request: stream_request} = state) do
    debug("Connecting to Solana Geyser", url: url, token: token, stream_request: stream_request)

    with {:ok, channel} <- ExSolana.Geyser.new(url, token: token),
         stream = ExSolana.Geyser.Geyser.Stub.subscribe(channel),
         GRPC.Stub.send_request(stream, stream_request),
         {:ok, reply_enum} <- GRPC.Stub.recv(stream) do
      {:ok, %{state | channel: channel, stream: stream, reply_enum: reply_enum}}
    else
      error ->
        Logger.error("Failed to connect to Solana Geyser: #{inspect(error)}")
        {:error, error}
    end
  end

  defp update_subscription(%{stream: stream} = state, new_request) do
    debug("Updating subscription", new_request: new_request)
    GRPC.Stub.send_request(stream, new_request)
    {:ok, state}
  end

  defp wrap_message(data) do
    %Message{
      data: :erlang.term_to_binary(data),
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def ack(_, _, _), do: :ok
end
