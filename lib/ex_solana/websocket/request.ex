defmodule ExSolana.Websocket.Request do
  @moduledoc """
  Builds WebSocket requests for Solana RPC methods.
  """

  alias ExSolana.Config

  @type subscription_method :: String.t()
  @type params :: list()
  @type opts :: keyword()

  @doc """
  Builds a WebSocket request for a Solana RPC method.
  """
  @spec build(subscription_method(), params(), opts()) :: map()
  def build(method, params, opts \\ []) do
    request_id = :rand.uniform(1_000_000)

    %{
      jsonrpc: "2.0",
      id: request_id,
      method: method,
      params: build_params(method, params, opts)
    }
  end

  @spec build_params(subscription_method(), params(), opts()) :: list()
  defp build_params("blockSubscribe", params, opts) do
    filter = List.first(params) || "all"
    config = build_block_subscribe_config(opts)
    [filter, config]
  end

  defp build_params("programSubscribe", program_id, opts) do
    config = build_program_subscribe_config(opts)
    [program_id, config]
  end

  defp build_params("logsSubscribe", [filter], opts) when is_map(filter) do
    config = build_logs_subscribe_config(opts)
    [filter, config]
  end

  defp build_params("logsSubscribe", filter, opts) when filter in ["all", "allWithVotes"] do
    config = build_logs_subscribe_config(opts)
    [filter, config]
  end

  defp build_params(_method, params, opts) do
    commitment = opts[:commitment] || Config.get({:default, :commitment})
    params ++ [%{encoding: "jsonParsed", commitment: commitment}]
  end

  @spec build_block_subscribe_config(opts()) :: map()
  defp build_block_subscribe_config(opts) do
    %{}
    |> maybe_add_option(:commitment, opts[:commitment] || Config.get({:default, :commitment}))
    |> maybe_add_option(:encoding, opts[:encoding] || Config.get({:default, :encoding}))
    |> maybe_add_option(
      :transactionDetails,
      opts[:transaction_details] || Config.get({:default, :transaction_details})
    )
    |> maybe_add_option(
      :maxSupportedTransactionVersion,
      opts[:max_supported_transaction_version] ||
        Config.get({:default, :max_supported_transaction_version})
    )
    |> maybe_add_option(
      :showRewards,
      opts[:show_rewards] || Config.get({:default, :show_rewards})
    )
  end

  @spec maybe_add_option(map(), atom(), any()) :: map()
  defp maybe_add_option(config, _key, nil), do: config
  defp maybe_add_option(config, key, value), do: Map.put(config, key, value)

  @spec build_program_subscribe_config(opts()) :: map()
  defp build_program_subscribe_config(opts) do
    %{}
    |> maybe_add_option(:commitment, opts[:commitment] || Config.get({:default, :commitment}))
    |> maybe_add_option(:encoding, opts[:encoding] || "jsonParsed")
    |> maybe_add_option(:filters, build_filters(opts[:filters] || []))
  end

  defp build_logs_subscribe_config(opts) do
    %{}
    |> maybe_add_option(:commitment, opts[:commitment] || Config.get({:default, :commitment}))
    |> maybe_add_option(:encoding, "jsonParsed")
  end

  @spec build_filters(list()) :: list()
  defp build_filters(filters) do
    filters
    |> Enum.map(fn filter ->
      case filter do
        %{dataSize: size} when is_integer(size) ->
          %{dataSize: size}

        %{memcmp: %{offset: offset, bytes: bytes}} when is_integer(offset) and is_binary(bytes) ->
          %{memcmp: %{offset: offset, bytes: bytes}}

        %{memcmp: %{offset: offset, bytes: bytes}} when is_integer(offset) and is_list(bytes) ->
          %{memcmp: %{offset: offset, bytes: IO.iodata_to_binary(bytes)}}

        _ ->
          require Logger

          Logger.warning("Invalid filter format: #{inspect(filter)}", filter: filter)
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
