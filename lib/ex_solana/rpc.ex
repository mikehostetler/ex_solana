defmodule ExSolana.RPC do
  @moduledoc """
  Functions for dealing with Solana's [JSON-RPC
  API](https://docs.solana.com/developing/clients/jsonrpc-api).
  """
  use ExSolana.Util.DebugTools, debug_enabled: false

  import ExSolana.Helpers

  alias ExSolana.Config
  alias ExSolana.RPC

  require Logger

  @typedoc "Solana JSON-RPC API client."
  @type client :: Tesla.Client.t()

  @client_schema [
    adapter: [
      type: :any,
      default: Tesla.Adapter.Mint,
      doc: "Which `Tesla` adapter to use."
    ],
    network: [
      type: {:custom, __MODULE__, :cluster_url, []},
      required: false,
      doc: "Which [ExSolana cluster](https://docs.solana.com/clusters) to connect to."
    ],
    base_url: [
      type: :string,
      required: false,
      doc: "Custom base URL for the RPC endpoint."
    ],
    api_key: [
      type: :string,
      required: false,
      doc: "API key for authentication with the RPC endpoint."
    ],
    retry_options: [
      type: :keyword_list,
      default: [],
      doc: "Options to pass to `Tesla.Middleware.Retry`."
    ],
    verbose: [
      type: :boolean,
      default: false,
      doc: "Enable debug logging of all requests."
    ]
  ]

  @doc """
  Creates an API client used to interact with Solana's [JSON-RPC
  API](https://docs.solana.com/developing/clients/jsonrpc-api).

  ## Example

      iex> key = ExSolana.keypair() |> ExSolana.pubkey!()
      iex> client = ExSolana.RPC.client(network: "localhost")
      iex> {:ok, signature} = ExSolana.RPC.send(client, ExSolana.RPC.Request.request_airdrop(key, 1))
      iex> is_binary(signature)
      true

  ## Options

  #{NimbleOptions.docs(@client_schema)}
  """
  @spec client(keyword) :: client
  def client(opts) do
    debug("Creating client with opts: #{inspect(opts)}")

    case validate(opts, @client_schema) do
      {:ok, config} ->
        base_url = get_base_url(config)
        middleware = build_middleware(config, base_url)
        client = Tesla.client(middleware, config.adapter)
        debug("Client created: #{inspect(client)}")
        client

      error ->
        debug("Error creating client: #{inspect(error)}")
        error
    end
  end

  # Helper function to get the base URL
  defp get_base_url(%{base_url: base_url}) when is_binary(base_url), do: base_url
  defp get_base_url(%{network: network}), do: network
  defp get_base_url(_), do: Config.get({:rpc, :base_url})

  # Build middleware stack
  defp build_middleware(config, base_url) do
    debug("Building middleware with base_url: #{inspect(base_url)}")

    [
      {Tesla.Middleware.BaseUrl, base_url},
      RPC.Middleware
    ]
    |> add_cache_middleware()
    |> Kernel.++([
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry, retry_opts(config)}
    ])
    |> maybe_add_auth_middleware(config)
  end

  defp add_cache_middleware(middleware) do
    # Use Application.get_env instead of Mix.env() for production compatibility
    env = Application.get_env(:ex_solana, :env, :prod)

    if env in [:dev, :test] and Config.get({:cache, :enabled}) do
      debug("Adding cache middleware")
      middleware ++ [RPC.RequestCache]
    else
      middleware
    end
  end

  defp maybe_add_auth_middleware(middleware, config) do
    network = config[:network] || Config.get({:rpc, :network})
    api_key = config[:api_key] || Config.get({:rpc, :api_key})

    if auth_required?(network) && is_binary(api_key) && api_key != "" do
      debug("Adding auth middleware")
      [{Tesla.Middleware.Headers, [{"Authorization", "Bearer #{api_key}"}]} | middleware]
    else
      middleware
    end
  end

  defp auth_required?(network) when network in ["devnet", "mainnet-beta", "testnet"], do: false
  defp auth_required?(_), do: true

  @doc """
  Sends the provided requests to the configured Solana RPC endpoint.
  """
  def send(client, requests) do
    debug("Sending requests: #{inspect(requests)}")

    if Config.get(:verbose) do
      Logger.debug("RPC Send: #{inspect(requests)}")
    end

    result = Tesla.post(client, "/", ExSolana.RPC.Request.encode(requests))
    debug("Send result: #{inspect(result)}")
    result
  end

  @doc """
  Sends the provided transactions to the configured RPC endpoint, then confirms them.

  Returns a tuple containing all the transactions in the order they were confirmed, OR
  an error tuple containing the list of all the transactions that were confirmed
  before the error occurred.
  """
  @spec send_and_confirm(
          client,
          pid,
          [ExSolana.Transaction.t()] | ExSolana.Transaction.t(),
          keyword
        ) ::
          {:ok, [binary]} | {:error, :timeout, [binary]}
  def send_and_confirm(client, tracker, txs, opts \\ []) do
    debug("Sending and confirming transactions: #{inspect(txs)}")
    timeout = Keyword.get(opts, :timeout, 5_000)
    request_opts = Keyword.take(opts, [:commitment])
    requests = Enum.map(List.wrap(txs), &RPC.Request.send_transaction(&1, request_opts))

    if Config.get(:verbose) do
      Logger.debug("RPC SendConfirm: #{inspect(requests)}")
    end

    task =
      Task.async(fn ->
        client
        |> RPC.send(requests)
        |> Enum.flat_map(fn
          {:ok, signature} ->
            debug("Transaction sent successfully: #{inspect(signature)}")
            [signature]

          {:error, error} ->
            Logger.warning("Error sending transaction: #{inspect(error)}")
            debug("Error sending transaction: #{inspect(error)}")
            []
        end)
        |> case do
          [] ->
            debug("No transactions sent successfully")
            :error

          signatures ->
            debug("Starting tracking for signatures: #{inspect(signatures)}")
            :ok = RPC.Tracker.start_tracking(tracker, signatures, request_opts)
            await_confirmations(tracker, signatures, [])
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        debug("Task completed with result: #{inspect(result)}")
        result

      nil ->
        debug("Task timed out")
        RPC.Tracker.stop_tracking(tracker, List.wrap(txs))
        {:error, :timeout, []}
    end
  end

  defp await_confirmations(tracker, [], confirmed) do
    debug("All confirmations received: #{inspect(confirmed)}")
    RPC.Tracker.stop_tracking(tracker, confirmed)
    {:ok, confirmed}
  end

  defp await_confirmations(tracker, signatures, done) do
    debug("Awaiting confirmations for signatures: #{inspect(signatures)}")

    receive do
      {:ok, confirmed} ->
        debug("Received confirmations: #{inspect(confirmed)}")
        remaining = MapSet.difference(MapSet.new(signatures), MapSet.new(confirmed))
        await_confirmations(tracker, MapSet.to_list(remaining), List.flatten([done, confirmed]))
    end
  end

  @doc false
  def cluster_url(network) when network in ["devnet", "mainnet-beta", "testnet"] do
    {:ok, "https://api.#{network}.solana.com"}
  end

  def cluster_url("localhost"), do: {:ok, "http://127.0.0.1:8899"}

  def cluster_url(other) when is_binary(other) do
    case URI.parse(other) do
      %{scheme: nil, host: nil} -> {:error, "invalid cluster"}
      _ -> {:ok, other}
    end
  end

  def cluster_url(_), do: {:error, "invalid cluster"}

  defp retry_opts(%{retry_options: retry_options}) do
    Keyword.merge(retry_defaults(), retry_options)
  end

  defp retry_defaults do
    [
      max_retries: Config.get({:rpc, :max_retries}) || 10,
      max_delay: Config.get({:rpc, :max_delay}) || 4_000,
      should_retry: &should_retry?/1
    ]
  end

  defp should_retry?({:ok, %{status: status}}) when status in 500..599, do: true
  defp should_retry?({:ok, _}), do: false
  defp should_retry?({:error, _}), do: true
end
