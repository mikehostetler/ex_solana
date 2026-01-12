defmodule ExSolana.RPC do
  @moduledoc """
  Solana JSON-RPC API client using Req.

  ## Features

  - JSON-RPC 2.0 communication with Solana nodes
  - Built-in retry logic for transient failures
  - Support for all Solana RPC methods
  - Configurable timeouts and authentication

  ## Quick Start

      # Create client
      client = ExSolana.RPC.client(network: :mainnet_beta)

      # Get account balance
      {:ok, balance} = ExSolana.RPC.get_balance(client, pubkey)

      # Send transaction
      {:ok, signature} = ExSolana.RPC.send_transaction(client, tx)

  ## Configuration

  Client options:

  - `:network` - Solana cluster (`:mainnet_beta`, `:testnet`, `:devnet`, `:localhost`)
  - `:base_url` - Custom RPC endpoint URL
  - `:api_key` - API key for authentication
  - `:retry` - Retry options (`:safe_transient`, `:never`, or custom)
  - `:receive_timeout` - Request timeout in milliseconds (default: 30000)
  - `:verbose` - Enable debug logging (default: false)

  ## Error Handling

  All RPC errors are returned as structured errors:

      case ExSolana.RPC.get_balance(client, pubkey) do
        {:ok, balance} -> balance
        {:error, %ExSolana.Error.RPCError{} = error} ->
          handle_error(error)
      end

  ## Examples

      # Connect to mainnet-beta
      client = ExSolana.RPC.client(network: :mainnet_beta)

      # Get recent blockhash
      {:ok, blockhash} = ExSolana.RPC.get_latest_blockhash(client)

      # Get account info
      {:ok, account} = ExSolana.RPC.get_account_info(client, pubkey)

      # Send transaction
      {:ok, signature} = ExSolana.RPC.send_transaction(client, signed_tx)

  """

  alias ExSolana.{Error, Key}
  require Logger

  @typedoc """
  RPC client type.
  """
  @type client :: %__MODULE__{}

  @typedoc """
  Supported Solana networks.
  """
  @type network :: :mainnet_beta | :testnet | :devnet | :localhost

  use Zoi

  @schema Zoi.struct(
            __MODULE__,
            %{
              base_url:
                Zoi.string()
                |> Zoi.description("RPC endpoint base URL"),
              req:
                Zoi.any()
                |> Zoi.description("Req client instance")
                |> Zoi.optional(),
              retry:
                Zoi.atom()
                |> Zoi.description("Retry mode: :safe_transient, :never, or custom")
                |> Zoi.default(:safe_transient),
              receive_timeout:
                Zoi.integer()
                |> Zoi.description("Request timeout in milliseconds")
                |> Zoi.default(30_000),
              verbose:
                Zoi.boolean()
                |> Zoi.description("Enable debug logging")
                |> Zoi.default(false)
            },
            coerce: true
          )

  defstruct [:base_url, :req, retry: :safe_transient, receive_timeout: 30_000, verbose: false]

  @doc """
  Creates a new RPC client.

  ## Options

  - `:network` - Solana cluster (`:mainnet_beta`, `:testnet`, `:devnet`, `:localhost`)
  - `:base_url` - Custom RPC endpoint URL (overrides :network)
  - `:api_key` - API key appended to URL
  - `:retry` - Retry mode (`:safe_transient`, `:never`, default: `:safe_transient`)
  - `:receive_timeout` - Timeout in milliseconds (default: 30000)
  - `:verbose` - Enable debug logging (default: false)

  ## Examples

      # Connect to mainnet-beta
      client = ExSolana.RPC.client(network: :mainnet_beta)

      # Connect to custom endpoint
      client = ExSolana.RPC.client(base_url: "https://my-solana-rpc.com")

      # With API key
      client = ExSolana.RPC.client(
        network: :mainnet_beta,
        api_key: "my-api-key"
      )

      # With custom timeout
      client = ExSolana.RPC.client(
        network: :mainnet_beta,
        receive_timeout: 60_000
      )

  """
  @spec client(keyword()) :: client()
  def client(opts \\ []) do
    base_url = get_base_url(opts)
    retry_mode = Keyword.get(opts, :retry, :safe_transient)
    timeout = Keyword.get(opts, :receive_timeout, 30_000)
    verbose = Keyword.get(opts, :verbose, false)

    req =
      Req.new(
        base_url: base_url,
        retry: retry_mode,
        receive_timeout: timeout,
        headers: {"Content-Type", "application/json"}
      )

    if verbose do
      Logger.debug("Created ExSolana.RPC client",
        base_url: base_url,
        retry: retry_mode,
        timeout: timeout
      )
    end

    %__MODULE__{
      base_url: base_url,
      req: req,
      retry: retry_mode,
      receive_timeout: timeout,
      verbose: verbose
    }
  end

  # ============================================================================
  # Network Configuration
  # ============================================================================

  @doc """
  Returns the base URL for a given network.
  """
  @spec network_url(network()) :: String.t()
  def network_url(:mainnet_beta), do: "https://api.mainnet-beta.solana.com"
  def network_url(:testnet), do: "https://api.testnet.solana.com"
  def network_url(:devnet), do: "https://api.devnet.solana.com"
  def network_url(:localhost), do: "http://localhost:8899"

  defp get_base_url(opts) do
    cond do
      url = Keyword.get(opts, :base_url) ->
        append_api_key(url, Keyword.get(opts, :api_key))

      network = Keyword.get(opts, :network) ->
        network_url(network)
        |> append_api_key(Keyword.get(opts, :api_key))

      true ->
        # Default to mainnet-beta
        network_url(:mainnet_beta)
        |> append_api_key(Keyword.get(opts, :api_key))
    end
  end

  defp append_api_key(url, nil), do: url

  defp append_api_key(url, api_key) when is_binary(api_key) do
    url
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(%{"api-key" => api_key}))
    |> URI.to_string()
  end

  # ============================================================================
  # RPC Request/Response
  # ============================================================================

  @doc """
  Sends a JSON-RPC request.

  ## Parameters

  - `client` - RPC client
  - `method` - RPC method name
  - `params` - Method parameters (default: [])

  ## Examples

      {:ok, result} = ExSolana.RPC.request(client, "getBalance", [pubkey])

  """
  @spec request(client(), String.t(), list()) :: {:ok, any()} | {:error, Error.t()}
  def request(%__MODULE__{} = client, method, params \\ []) do
    json_payload = build_json_payload(method, params)

    if client.verbose do
      Logger.debug("Sending RPC request",
        method: method,
        params: inspect(params, limit: 500)
      )
    end

    case Req.post(client.req, json: json_payload) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        handle_json_response(body, method)

      {:ok, %{status: status}} ->
        {:error, Error.rpc_error("RPC request failed", kind: :http_error, code: status)}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, Error.rpc_error("Transport error", kind: :network, details: %{reason: reason})}

      {:error, %Req.TimeoutError{}} ->
        {:error, Error.rpc_error("Request timeout", kind: :timeout)}

      {:error, reason} ->
        {:error,
         Error.rpc_error("Request failed", kind: :network, details: %{reason: inspect(reason)})}
    end
  end

  defp build_json_payload(method, params) do
    %{
      jsonrpc: "2.0",
      id: 1,
      method: method,
      params: params
    }
  end

  defp handle_json_response(body, method) do
    case body do
      %{"result" => result} ->
        {:ok, decode_result(result, method)}

      %{"error" => error} ->
        {:error,
         Error.rpc_error("RPC error returned",
           kind: :response,
           code: get_in(error, ["code"]),
           details: %{message: get_in(error, ["message"])}
         )}

      _ ->
        {:error, Error.rpc_error("Invalid RPC response format", kind: :response)}
    end
  end

  # Decode special response formats
  defp decode_result(result, "getBalance") when is_integer(result), do: result
  defp decode_result(result, "sendTransaction") when is_binary(result), do: result
  defp decode_result(result, "getLatestBlockhash") when is_map(result), do: result
  defp decode_result(result, "getAccountInfo") when is_map(result), do: result
  defp decode_result(result, _), do: result

  # ============================================================================
  # Common RPC Methods
  # ============================================================================

  @doc """
  Gets the balance for an account.

  ## Examples

      {:ok, lamports} = ExSolana.RPC.get_balance(client, pubkey)

  """
  @spec get_balance(client(), Key.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_balance(client, pubkey) do
    case request(client, "getBalance", [pubkey]) do
      {:ok, %{"value" => value}} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Gets account information.

  ## Examples

      {:ok, account} = ExSolana.RPC.get_account_info(client, pubkey)

  """
  @spec get_account_info(client(), Key.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_account_info(client, pubkey, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, "base64")
    params = [pubkey, %{"encoding" => encoding}]

    case request(client, "getAccountInfo", params) do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  @doc """
  Gets the latest blockhash.

  ## Examples

      {:ok, blockhash} = ExSolana.RPC.get_latest_blockhash(client)

  """
  @spec get_latest_blockhash(client()) :: {:ok, map()} | {:error, Error.t()}
  def get_latest_blockhash(client) do
    case request(client, "getLatestBlockhash") do
      {:ok, result} -> {:ok, result}
      error -> error
    end
  end

  @doc """
  Sends a signed transaction.

  ## Examples

      {:ok, signature} = ExSolana.RPC.send_transaction(client, signed_tx)

  Options:
  - `:skip_preflight` - Skip preflight checks (default: false)
  - `:preflight_commitment` - Commitment level for preflight (default: "finalized")

  """
  @spec send_transaction(client(), binary(), keyword()) ::
          {:ok, Key.signature()} | {:error, Error.t()}
  def send_transaction(client, signed_tx, opts \\ []) do
    skip_preflight = Keyword.get(opts, :skip_preflight, false)
    preflight_commitment = Keyword.get(opts, :preflight_commitment, "finalized")

    params = [
      Base.encode64(signed_tx),
      %{
        "skipPreflight" => skip_preflight,
        "preflightCommitment" => preflight_commitment
      }
    ]

    case request(client, "sendTransaction", params) do
      {:ok, signature} -> {:ok, signature}
      error -> error
    end
  end

  @doc """
  Gets the health status of the node.

  ## Examples

      {:ok, "ok"} = ExSolana.RPC.get_health(client)

  """
  @spec get_health(client()) :: {:ok, String.t()} | {:error, Error.t()}
  def get_health(client) do
    request(client, "getHealth")
  end

  @doc """
  Gets the current slot.

  ## Examples

      {:ok, slot} = ExSolana.RPC.get_slot(client)

  """
  @spec get_slot(client()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_slot(client) do
    case request(client, "getSlot") do
      {:ok, slot} when is_integer(slot) -> {:ok, slot}
      error -> error
    end
  end

  @doc """
  Gets the cluster nodes.

  ## Examples

      {:ok, nodes} = ExSolana.RPC.get_cluster_nodes(client)

  """
  @spec get_cluster_nodes(client()) :: {:ok, list(map())} | {:error, Error.t()}
  def get_cluster_nodes(client) do
    request(client, "getClusterNodes")
  end

  @doc """
  Gets the version info.

  ## Examples

      {:ok, version} = ExSolana.RPC.get_version(client)

  """
  @spec get_version(client()) :: {:ok, map()} | {:error, Error.t()}
  def get_version(client) do
    request(client, "getVersion")
  end

  @doc """
  Requests an airdrop for an account.

  ## Examples

      {:ok, signature} = ExSolana.RPC.request_airdrop(client, pubkey, lamports)

  """
  @spec request_airdrop(client(), Key.t(), non_neg_integer()) ::
          {:ok, Key.signature()} | {:error, Error.t()}
  def request_airdrop(client, pubkey, lamports) do
    case request(client, "requestAirdrop", [pubkey, lamports]) do
      {:ok, signature} -> {:ok, signature}
      error -> error
    end
  end

  # ============================================================================
  # Helper Modules
  # ============================================================================

  defmodule Client do
    @moduledoc """
    Client helper module for compatibility with code expecting `ExSolana.RPC.Client`.
    """
    @type t :: ExSolana.RPC.t()
  end

  defmodule Request do
    @moduledoc """
    Request builder helper module for compatibility.
    """

    @doc """
    Builds an airdrop request.
    """
    def request_airdrop(pubkey, lamports) do
      [pubkey, lamports]
    end
  end
end
