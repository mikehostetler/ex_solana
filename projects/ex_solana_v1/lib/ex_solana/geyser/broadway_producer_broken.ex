# defmodule ExSolana.Geyser.Producer do
#   use GenStage
#   require Logger
#   alias Broadway.Message

#   defmodule State do
#     defstruct [:channel, :stream, :stream_request, :url, :token, :status]
#   end

#   def start_link(opts) do
#     GenStage.start_link(__MODULE__, opts)
#   end

#   @impl true
#   def init(opts) do
#     Logger.info("Initializing Geyser Producer with options: #{inspect(opts)}")

#     state = %State{
#       stream_request: opts[:stream_request],
#       url: opts[:url],
#       token: opts[:token],
#       status: :initialized
#     }

#     send(self(), :connect)
#     {:producer, state}
#   end

#   @impl true
#   def handle_demand(demand, %{status: :connected} = state) do
#     try do
#       {events, new_state} = fetch_events(demand, state)
#       {:noreply, events, new_state}
#     rescue
#       error ->
#         Logger.error("Error in handle_demand: #{inspect(error)}")
#         send(self(), :connect)
#         {:noreply, [], %{state | status: :disconnected}}
#     end
#   end

#   def handle_demand(_demand, state) do
#     {:noreply, [], state}
#   end

#   defp connect(%{url: url, token: token, stream_request: stream_request} = state) do
#     Logger.info("Attempting to connect to Solana Geyser")

#     with {:ok, channel} <- ExSolana.Geyser.new(url, token: token),
#          stream <- ExSolana.Geyser.Geyser.Stub.subscribe(channel),
#          :ok <- GRPC.Stub.send_request(stream, stream_request),
#          {:ok, reply_enum} <- GRPC.Stub.recv(stream) do
#       Logger.info("Successfully connected to Solana Geyser")
#       {:ok, %{state | channel: channel, stream: reply_enum, status: :connected}}
#     else
#       {:error, %GRPC.RPCError{} = error} ->
#         Logger.error("GRPC Error: #{inspect(error)}")
#         {:error, error}

#       error ->
#         Logger.error("Unexpected error during connection: #{inspect(error)}")
#         {:error, error}
#     end
#   end

#   @impl true
#   def handle_info(:connect, state) do
#     case connect(state) do
#       {:ok, new_state} ->
#         {:noreply, [], new_state}

#       {:error, reason} ->
#         Logger.warning("Failed to connect: #{inspect(reason)}. Retrying in 5 seconds.")

#         Process.send_after(self(), :connect, 5000)
#         {:noreply, [], %{state | status: :disconnected}}
#     end
#   end

#   defp fetch_events(demand, %{stream: stream} = state) do
#     events =
#       stream
#       |> Stream.take(demand)
#       |> Stream.flat_map(fn
#         {:ok, message} ->
#           [wrap_message(message)]

#         {:error, error} ->
#           Logger.warning("Error in stream: #{inspect(error)}", tag: "GeyserProducer")
#           []
#       end)
#       |> Enum.to_list()

#     {events, state}
#   end

#   defp wrap_message(data) do
#     %Message{
#       data: :erlang.term_to_binary(data),
#       acknowledger: {__MODULE__, :ack_id, :ack_data}
#     }
#   end

#   def ack(_, _, _), do: :ok
# end
