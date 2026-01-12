defmodule ExSolana.RPC.RequestCache do
  @moduledoc """
  A Tesla middleware for caching RPC responses.

  This module implements caching for Solana RPC requests, storing responses
  either as JSON or Erlang terms. It caches to the local filesystem and is
  intended to be used during development.
  """

  @behaviour Tesla.Middleware

  alias ExSolana.Config

  require Logger

  @cache_dir Application.compile_env(:ex_solana, :cache, [])[:directory] || "priv/rpc_cache"
  @use_json Application.compile_env(:ex_solana, :cache, [])[:use_json] || false

  @success 200..299

  @doc """
  Implements the Tesla middleware callback.

  This function intercepts the request, checks if it can be served from cache,
  and if not, forwards the request and caches the response.

  The cache is disabled by default in production.
  """
  @spec call(Tesla.Env.t(), Tesla.Env.next(), any()) :: {:ok, Tesla.Env.t()} | {:error, any()}
  def call(env, next, _options) do
    request = env.body

    if cache_enabled?(request) do
      case get_cached(request) do
        nil ->
          response = Tesla.run(env, next)
          cache_response(request, response)
          response

        cached ->
          {:ok, %{env | status: 200, body: cached}}
      end
    else
      Tesla.run(env, next)
    end
  end

  defp get_cached(request) do
    if use_cache?(request) do
      path = cache_path(request)

      if File.exists?(path) do
        try do
          if @use_json do
            path
            |> File.read!()
            |> Jason.decode!()
          else
            path
            |> File.read!()
            |> :erlang.binary_to_term()
          end
        rescue
          e ->
            Logger.warning("Failed to read cache file: #{inspect(e)}")
            nil
        end
      end
    end
  end

  defp cache_response(request, {:ok, %{status: status} = response}) when status in @success do
    if use_cache?(request) do
      path = cache_path(request)
      File.mkdir_p!(Path.dirname(path))

      content =
        prepare_content(response.body)

      File.write!(path, content)
      Logger.info("RPC Cache: Successfully cached response for request: #{path}")
    end
  end

  defp cache_response(_, _) do
    :ok
  end

  defp prepare_content(body) do
    if @use_json do
      Jason.encode!(body, pretty: true)
    else
      :erlang.term_to_binary(body)
    end
  end

  defp cache_path(request) do
    Path.join([@cache_dir, derive_cache_key(request)])
  end

  defp derive_cache_key(%{method: "getSignaturesForAddress", params: [address | _]}) do
    "getSignaturesForAddress_#{address}.json"
  end

  # Get account info
  defp derive_cache_key(%{method: "getAccountInfo", params: [address | _]}) do
    "getAccountInfo_#{address}.json"
  end

  # Get balance
  defp derive_cache_key(%{method: "getBalance", params: [address | _]}) do
    "getBalance_#{address}.json"
  end

  # Get transaction
  defp derive_cache_key(%{method: "getTransaction", params: [signature | _]}) do
    "getTransaction_#{signature}.json"
  end

  # Get recent blockhash
  defp derive_cache_key(%{method: "getRecentBlockhash"}) do
    "getRecentBlockhash"
  end

  # Get block
  defp derive_cache_key(%{method: "getBlock", params: [slot | _]}) do
    "getBlock_#{slot}.json"
  end

  # Get token account balance
  defp derive_cache_key(%{method: "getTokenAccountBalance", params: [account | _]}) do
    "getTokenAccountBalance_#{account}.json"
  end

  # Fallback for other methods
  defp derive_cache_key(%{method: method, params: params}) do
    # For other methods, use the entire request as the key
    "#{method}_#{:erlang.phash2(params)}.json"
  end

  defp use_cache?(request) do
    opts =
      case request do
        %{params: params} when is_list(params) ->
          List.last(params)

        _ ->
          %{}
      end

    case opts do
      opts when is_map(opts) -> Map.get(opts, "useCache", true)
      opts when is_list(opts) -> Keyword.get(opts, :use_cache, true)
      _ -> true
    end
  end

  defp cache_enabled?(request) do
    global_cache_enabled? = Config.get({:cache, :enabled}) || false
    global_cache_enabled? and use_cache?(request)
  end
end
