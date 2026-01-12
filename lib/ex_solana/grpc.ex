defmodule ExSolana.GRPCClientBase do
  @moduledoc """
  Base module for GRPC client connections with flexible SSL options.

  This module provides a unified interface for creating GRPC clients that can
  connect to both secure and insecure endpoints. It handles SSL/TLS configuration
  automatically with a fallback strategy.

  ## Features

    * Automatic SSL/TLS detection and fallback
    * Custom header support (including authentication tokens)
    * Configurable compression and interceptors
    * Comprehensive logging for debugging

  ## Example

      # Connect to an insecure endpoint
      {:ok, channel} = ExSolana.GRPCClientBase.new("localhost:10000", [], "MyService")

      # Connect with authentication
      {:ok, channel} = ExSolana.GRPCClientBase.new(
        "https://api.example.com",
        [token: "my-auth-token"],
        "MyService"
      )

  ## Options

    * `:adapter` - GRPC adapter (default: `GRPC.Client.Adapters.Mint`)
    * `:codec` - GRPC codec (default: `GRPC.Codec.Proto`)
    * `:interceptors` - List of interceptors (default: `[]`)
    * `:compressor` - Compression algorithm (default: `nil`)
    * `:accepted_compressors` - List of accepted compressors (default: `[]`)
    * `:headers` - Additional headers (default: `[]`)
    * `:token` - Authentication token (automatically added as `x-token` header)

  """

  require Logger

  @default_options [
    adapter: GRPC.Client.Adapters.Mint,
    codec: GRPC.Codec.Proto,
    interceptors: [],
    compressor: nil,
    accepted_compressors: [],
    headers: []
  ]

  @typedoc "Connection options"
  @type options :: [
          adapter: module(),
          codec: module(),
          interceptors: list(),
          compressor: atom() | nil,
          accepted_compressors: list(atom()),
          headers: list({String.t(), String.t()}),
          token: String.t() | nil
        ]

  @doc """
  Establishes a new connection with the given URL, options, and service name.

  This function attempts to connect without SSL first, and falls back to SSL
  if the initial connection fails. This provides a seamless experience when
  connecting to endpoints that may or may not require SSL.

  ## Parameters

    * `url` - The endpoint URL (e.g., `"localhost:10000"` or `"https://api.example.com"`)
    * `opts` - Connection options (see type documentation)
    * `service_name` - Name of the service (for logging purposes)

  ## Returns

    * `{:ok, channel}` - Connection established successfully
    * `{:error, reason}` - Connection failed (both with and without SSL)

  ## Examples

      # Basic connection
      {:ok, channel} = ExSolana.GRPCClientBase.new("localhost:10000", [], "Geyser")

      # With authentication
      {:ok, channel} = ExSolana.GRPCClientBase.new(
        "https://geyser.example.com",
        [token: "my-token"],
        "Geyser"
      )

  """
  @spec new(String.t(), options(), String.t()) :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def new(url, opts, service_name) do
    options =
      @default_options
      |> Keyword.merge(opts)
      |> add_custom_headers()

    connect_with_strategy(url, options, service_name)
  end

  # Private Functions

  defp add_custom_headers(options) do
    custom_headers = get_custom_headers(options)
    headers = custom_headers ++ Keyword.get(options, :headers, [])
    Keyword.put(options, :headers, headers)
  end

  defp get_custom_headers(options) do
    case Keyword.get(options, :token) do
      nil -> []
      token -> [{"x-token", token}]
    end
  end

  defp connect_with_strategy(url, options, service_name) do
    Logger.debug("Attempting to connect to #{service_name} at #{url}")

    case connect_without_ssl(url, options) do
      {:ok, channel} ->
        Logger.info("Successfully connected to #{service_name} at #{url} without SSL")
        {:ok, channel}

      {:error, reason} ->
        Logger.warning("Failed to connect without SSL: #{inspect(reason)}", reason: reason)
        fallback_to_ssl_connection(url, options, service_name)
    end
  end

  defp connect_without_ssl(url, options) do
    GRPC.Stub.connect(url, options)
  end

  defp fallback_to_ssl_connection(url, options, service_name) do
    Logger.warning("Attempting SSL connection to #{service_name} at #{url}")

    ssl_options = [verify: :verify_none, versions: [:"tlsv1.2", :"tlsv1.3"]]
    options = Keyword.put(options, :cred, GRPC.Credential.new(ssl: ssl_options))

    case GRPC.Stub.connect(url, options) do
      {:ok, channel} ->
        Logger.info("Connected to #{service_name} at #{url} with SSL")
        {:ok, channel}

      {:error, reason} ->
        Logger.error("Failed to connect to #{service_name} at #{url}: #{inspect(reason)}",
          reason: reason
        )

        {:error, reason}
    end
  end
end
