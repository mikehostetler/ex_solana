defmodule ExSolana.GRPCClientBase do
  @moduledoc """
  Base module for GRPC client connections with flexible SSL options.
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

  @doc """
  Establishes a new connection with the given URL, options, and service name.
  """
  def new(url, opts, service_name) do
    options =
      @default_options
      |> Keyword.merge(opts)
      |> add_custom_headers()

    connect_with_strategy(url, options, service_name)
  end

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
