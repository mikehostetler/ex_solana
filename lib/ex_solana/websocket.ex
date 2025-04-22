defmodule ExSolana.Websocket do
  @moduledoc """
  Handles WebSocket connections and communication for Solana RPC.

  This module provides a simplified interface for establishing and managing
  WebSocket connections to Solana RPC endpoints, handling subscriptions internally,
  and processing incoming messages.
  """

  use WebSockex
  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.Config
  alias ExSolana.Websocket.Request

  @type subscription_id :: String.t()
  @type method :: String.t()

  @type t :: %__MODULE__{
          url: String.t(),
          reconnect_interval: non_neg_integer(),
          manager_pid: pid(),
          max_reconnect_attempts: non_neg_integer(),
          current_reconnect_attempts: non_neg_integer(),
          subscriptions: %{subscription_id() => method()}
        }

  defstruct [
    :url,
    :reconnect_interval,
    :manager_pid,
    max_reconnect_attempts: 10,
    current_reconnect_attempts: 0,
    subscriptions: %{}
  ]

  @callback handle_message(map()) :: any()

  @doc """
  Starts a WebSocket connection to the Solana RPC endpoint.
  """
  @spec start_link(module(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(manager_pid, opts \\ []) do
    url = Keyword.get(opts, :url) || Config.get({:websocket, :url})

    reconnect_interval =
      Keyword.get(opts, :reconnect_interval) || Config.get({:websocket, :reconnect_interval})

    try do
      :ets.new(:subscription_requests, [:named_table, :public])
    rescue
      ArgumentError ->
        debug("ETS table :subscription_requests already exists")

      error ->
        debug("Error creating ETS table: #{inspect(error)}")
        {:error, :ets_table_creation_failed}
    end

    state = %__MODULE__{
      url: url,
      reconnect_interval: reconnect_interval,
      manager_pid: manager_pid
    }

    debug("Starting WebSocket connection to #{url}")
    WebSockex.start_link(url, __MODULE__, state, opts)
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    debug("Connected to Solana WebSocket at #{state.url}")
    {:ok, %{state | current_reconnect_attempts: 0}}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: {:local, reason}}, state) do
    debug("Local close with reason: #{inspect(reason)}")
    {:ok, state}
  end

  def handle_disconnect(disconnect_map, %{current_reconnect_attempts: attempts} = state) do
    if attempts < state.max_reconnect_attempts do
      backoff = calculate_backoff(attempts)
      debug("Disconnected: #{inspect(disconnect_map)}. Reconnecting in #{backoff}ms")
      Process.sleep(backoff)
      {:reconnect, %{state | current_reconnect_attempts: attempts + 1}}
    else
      debug("Max reconnection attempts reached. Terminating.")
      {:stop, :max_attempts_reached, state}
    end
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, decoded} ->
        debug("Received WebSocket frame: #{inspect(decoded)}")
        process_message(decoded, state)

      {:error, _reason} ->
        debug("Error decoding WebSocket message, processing raw message")
        handle_unexpected_frame(msg, state)
    end
  end

  # Fallback for handling raw WebSocket frames when JSON decoding fails
  defp handle_unexpected_frame(msg, state) do
    debug("Handling raw WebSocket frame: #{inspect(msg)}")
    # Optionally process the raw frame in some way
    {:ok, state}
  end

  @doc """
  Subscribes to a Solana WebSocket method.
  """
  @spec subscribe(pid(), method(), Request.params(), Request.opts()) ::
          {:ok, subscription_id()} | {:error, term()}
  def subscribe(pid, method, params, opts \\ []) do
    request = Request.build(method, params, opts)
    debug("Sending subscription request: #{inspect(request)}")
    ref = make_ref()

    # Added configurable timeout, defaults to 10 seconds
    timeout = Keyword.get(opts, :timeout, 10_000)

    try do
      debug("Sending subscription request to process: #{inspect(pid)}")
      send(pid, {:subscribe, self(), ref, request})

      debug("Waiting for subscription response")

      receive do
        {:subscription_success, ^ref, subscription_id} ->
          debug("Subscription successful. ID: #{subscription_id}")
          {:ok, subscription_id}

        {:subscription_error, ^ref, reason} ->
          debug("Subscription error: #{inspect(reason)}")
          {:error, reason}

        other ->
          debug("Unexpected message received: #{inspect(other)}")
          {:error, :unexpected_message}
      after
        timeout ->
          debug("Subscription timed out after #{timeout}ms")
          {:error, :timeout}
      end
    catch
      :exit, reason ->
        debug("Process exited while waiting for subscription response: #{inspect(reason)}")
        {:error, :process_exited}
    end
  end

  @doc """
  Unsubscribes from a Solana WebSocket method.
  """
  @spec unsubscribe(pid(), subscription_id()) :: :ok | {:error, term()}
  def unsubscribe(pid, subscription_id) do
    debug("Unsubscribing from subscription: #{subscription_id}")
    GenServer.call(pid, {:unsubscribe, subscription_id})
  end

  @doc """
  Shuts down the WebSocket connection.
  """
  @spec shutdown(pid()) :: :ok
  def shutdown(pid) do
    debug("Shutting down WebSocket connection")
    GenServer.cast(pid, :shutdown)
  end

  @impl WebSockex
  def handle_info({:subscribe, from, ref, request}, state) do
    debug("Handling subscription request: #{inspect(request)}")
    {:ok, request_id} = Map.fetch(request, :id)
    debug("Inserting subscription request into ETS. Request ID: #{request_id}")
    :ets.insert(:subscription_requests, {request_id, from, ref})
    debug("ETS lookup result: #{inspect(:ets.lookup(:subscription_requests, request_id))}")
    {:reply, {:text, Jason.encode!(request)}, state}
  end

  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    case Map.pop(state.subscriptions, subscription_id) do
      {nil, _} ->
        debug("Attempted to unsubscribe from non-existent subscription: #{subscription_id}")
        {:reply, {:error, :not_found}, state}

      {method, new_subscriptions} ->
        unsubscribe_method = String.replace(method, "Subscribe", "Unsubscribe")
        request = Request.build(unsubscribe_method, [subscription_id])
        debug("Sending unsubscribe request: #{inspect(request)}")

        {:reply, :ok, {:text, Jason.encode!(request)}, %{state | subscriptions: new_subscriptions}}
    end
  end

  @impl WebSockex
  def handle_cast(:shutdown, state) do
    debug("Received shutdown request")

    Enum.each(state.subscriptions, fn {subscription_id, _} ->
      debug("Unsubscribing from subscription: #{subscription_id}")
      unsubscribe(self(), subscription_id)
    end)

    {:close, state}
  end

  # Private functions

  defp process_message(
         %{"method" => _method, "params" => %{"result" => _result, "subscription" => subscription_id}} = msg,
         state
       ) do
    debug("Received subscription message for subscription ID: #{subscription_id}")
    send(state.manager_pid, {:solana_websocket_message, msg})
    {:ok, state}
  end

  defp process_message(%{"result" => subscription_id, "id" => request_id} = msg, state) do
    debug("Received subscription confirmation. ID: #{subscription_id}, Request ID: #{request_id}")

    case :ets.lookup(:subscription_requests, request_id) do
      [{^request_id, from, ref}] ->
        debug("Found matching subscription request. Notifying requester.")
        :ets.delete(:subscription_requests, request_id)
        send(from, {:subscription_success, ref, subscription_id})

      [] ->
        debug("No pending request found for id: #{request_id}")
    end

    {:ok, put_in(state.subscriptions[subscription_id], get_method_from_msg(msg))}
  end

  defp process_message(%{"error" => error, "id" => request_id} = _msg, state) do
    debug("Received error response. Request ID: #{request_id}, Error: #{inspect(error)}")

    case :ets.lookup(:subscription_requests, request_id) do
      [{^request_id, from, ref}] ->
        debug("Found matching subscription request. Notifying requester of error.")
        :ets.delete(:subscription_requests, request_id)
        send(from, {:subscription_error, ref, error})

      [] ->
        debug("No pending request found for id: #{request_id}")
    end

    {:ok, state}
  end

  defp process_message(msg, state) do
    # debug("Received unhandled message: #{inspect(msg)}")
    state.callback_module.handle_message(msg)
    {:ok, state}
  end

  defp get_method_from_msg(%{"method" => method}) when is_binary(method), do: method
  defp get_method_from_msg(_), do: nil

  defp calculate_backoff(attempt) do
    max_interval = 30_000
    interval = min(round(:math.pow(2, attempt) * 1000), max_interval)
    interval + :rand.uniform(1000)
  end

  # Default handle_message implementation
  def handle_message(_msg) do
    # Default no-op
    :ok
  end
end
