defmodule ExSolana.Geyser.DummyProducer do
  @moduledoc false
  use GenStage

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:cache_dir, :rate, :timer, :demand]
  end

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %State{
      cache_dir: Keyword.fetch!(opts, :cache_dir),
      rate: Keyword.get(opts, :rate, 1),
      demand: 0
    }

    {:producer, state, dispatcher: GenStage.BroadcastDispatcher}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    new_demand = demand + incoming_demand
    schedule_next_message(state)
    {:noreply, [], %{state | demand: new_demand}}
  end

  @impl true
  def handle_info(:produce_message, %{demand: demand} = state) when demand > 0 do
    case produce_message(state) do
      {:ok, message, new_state} ->
        schedule_next_message(new_state)
        {:noreply, [message], %{new_state | demand: demand - 1}}

      {:error, :no_messages} ->
        Logger.warning("No messages found in cache directory. Halting.", tag: "DummyProducer")
        {:stop, :normal, state}
    end
  end

  def handle_info(:produce_message, state) do
    schedule_next_message(state)
    {:noreply, [], state}
  end

  defp schedule_next_message(%{rate: rate}) do
    Process.send_after(self(), :produce_message, trunc(1000 / rate))
  end

  defp produce_message(%{cache_dir: cache_dir} = state) do
    case File.ls(cache_dir) do
      {:ok, []} ->
        {:error, :no_messages}

      {:ok, files} ->
        random_file = Enum.random(files)
        full_path = Path.join(cache_dir, random_file)

        case File.read(full_path) do
          {:ok, binary_data} ->
            message = %Broadway.Message{
              data: binary_data,
              acknowledger: {__MODULE__, :ack_id, :ack_data}
            }

            {:ok, message, state}

          {:error, reason} ->
            Logger.warning("Failed to read file #{full_path}: #{inspect(reason)}",
              tag: "DummyProducer"
            )

            produce_message(state)
        end

      {:error, reason} ->
        Logger.error("Failed to list files in cache directory: #{inspect(reason)}",
          tag: "DummyProducer"
        )

        {:error, :no_messages}
    end
  end

  def ack(_, _, _), do: :ok
end
