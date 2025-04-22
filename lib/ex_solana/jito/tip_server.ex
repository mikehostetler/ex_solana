defmodule ExSolana.Jito.TipServer do
  @moduledoc """
  A WebSocket client for receiving and caching Jito Tip signals.

  This module connects to the Jito Tip stream, caches the latest tip data,
  and provides an API for other processes to retrieve the cached tip amounts.

  ## Usage

      {:ok, _pid} = ExSolana.Jito.TipServer.start_link()

      # Wait a moment for data to be received
      :timer.sleep(1000)

      case ExSolana.Jito.TipServer.get_latest_tips() do
        {:ok, tips} ->
          IO.inspect(tips, label: "Latest Jito Tips")
        {:error, reason} ->
          IO.puts("Failed to get latest tips: \#{inspect(reason)}")
      end

  """

  use WebSockex

  require Logger

  @typedoc """
  Jito tip data structure.

  All values are in SOL (not lamports).
  """
  @type tip_data :: %{
          landed_tips_25th_percentile: number(),
          landed_tips_50th_percentile: number(),
          landed_tips_75th_percentile: number(),
          landed_tips_95th_percentile: number(),
          landed_tips_99th_percentile: number(),
          ema_landed_tips_50th_percentile: number()
        }

  @websockex Application.compile_env(:ex_solana, :websockex, WebSockex)
  @jito_tip_stream "ws://bundles-api-rest.jito.wtf/api/v1/bundles/tip_stream"
  @default_reconnect_interval 5000

  @doc """
  Returns a child specification for starting the TipServer under a supervisor.

  ## Options

    * `:reconnect_interval` - The interval in milliseconds to wait before
      attempting to reconnect after a disconnection. Defaults to 5000ms.

  ## Example

      children = [
        {ExSolana.Jito.TipServer, reconnect_interval: 10_000}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts the Jito Tip server.

  ## Options

    * `:reconnect_interval` - The interval in milliseconds to wait before
      attempting to reconnect after a disconnection. Defaults to 5000ms.

  ## Returns

    * `{:ok, pid}` if the server started successfully
    * `{:error, reason}` if the server failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    state = %{
      latest_tips: nil,
      reconnect_interval: Keyword.get(opts, :reconnect_interval, @default_reconnect_interval)
    }

    @websockex.start_link(@jito_tip_stream, __MODULE__, state, name: __MODULE__)
  end

  @doc """
  Retrieves the latest cached tip data.

  ## Returns

    * `{:ok, tip_data()}` if tip data is available
    * `{:error, :no_data_yet}` if no data has been received yet
    * `{:error, :unavailable}` if the server is not running or encountered an error
  """
  @spec get_latest_tips() :: {:ok, tip_data()} | {:error, :no_data_yet | :unavailable}
  def get_latest_tips do
    case :sys.get_state(__MODULE__) do
      %{latest_tips: nil} -> {:error, :no_data_yet}
      %{latest_tips: tips} -> {:ok, tips}
    end
  rescue
    error ->
      Logger.error("Failed to retrieve latest tips: #{inspect(error)}")
      {:error, :unavailable}
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("Connected to Jito Tip WebSocket")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: {:local, reason}}, state) do
    Logger.info("Local disconnect from Jito Tip WebSocket: #{inspect(reason)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    Logger.warning(
      "Disconnected from Jito Tip WebSocket: #{inspect(disconnect_map)}. Reconnecting in #{state.reconnect_interval}ms"
    )

    Process.sleep(state.reconnect_interval)
    {:reconnect, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, decoded_msg} ->
        handle_decoded_message(decoded_msg, state)

      {:error, reason} ->
        Logger.error("Failed to decode Jito tip data: #{inspect(reason)}")
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_frame(frame, state) do
    Logger.warning("Received unexpected frame from Jito Tip WebSocket: #{inspect(frame)}")
    {:ok, state}
  end

  defp handle_decoded_message([tip_data | _], state) when is_map(tip_data) do
    new_tips = parse_tip_data(tip_data)
    {:ok, %{state | latest_tips: new_tips}}
  rescue
    error ->
      Logger.error("Error processing Jito tip data: #{Exception.format(:error, error, __STACKTRACE__)}")

      {:ok, state}
  end

  defp handle_decoded_message(decoded_msg, state) do
    Logger.warning("Unexpected message format from Jito Tip WebSocket: #{inspect(decoded_msg, pretty: true)}")

    {:ok, state}
  end

  defp parse_tip_data(tips) do
    parse = fn key, value ->
      case value do
        v when is_number(v) ->
          trunc(v * ExSolana.lamports_per_sol())

        v when is_binary(v) ->
          case Float.parse(v) do
            {float_value, _} ->
              trunc(float_value * ExSolana.lamports_per_sol())

            :error ->
              Logger.warning("Failed to parse #{key} as float: #{v}")
              0
          end

        _ ->
          Logger.warning("Unexpected value type for #{key}: #{inspect(value)}")
          0
      end
    end

    keys =
      ~w(landed_tips_25th_percentile landed_tips_50th_percentile landed_tips_75th_percentile
              landed_tips_95th_percentile landed_tips_99th_percentile ema_landed_tips_50th_percentile)

    value =
      Enum.reduce(keys, %{}, fn key, acc ->
        Map.put(acc, String.to_atom(key), parse.(key, tips[key]))
      end)

    value
  end
end
