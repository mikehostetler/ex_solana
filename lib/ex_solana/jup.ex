defmodule ExSolana.Jup do
  @moduledoc """
  An Elixir client for the Jupiter Swap API.

  This module provides functions to interact with Jupiter's DEX aggregator API,
  including getting quotes, building swap transactions, and fetching token prices.

  ## Configuration

  You can configure the Jupiter API key in your application config:

      config :ex_solana,
        jupiter: [
          api_key: System.get_env("JUPITER_API_KEY")
        ]

  Get your API key from https://portal.jup.ag

  """
  alias ExSolana.Config
  alias ExSolana.Jupiter.Errors
  alias Tesla.Middleware.BaseUrl
  alias Tesla.Middleware.Headers
  alias Tesla.Middleware.JSON

  require Logger

  # https://station.jup.ag/docs/token-list/token-list-api
  @token_api_base_url "https://tokens.jup.ag"
  @valid_token_tags [
    :verified,
    :unkonwn,
    :community,
    :strict,
    :lst,
    :"birdeye-trending",
    :clone,
    :pump
  ]
  @type error :: {:error, String.t() | {integer(), map()}}

  def client(_opts \\ []) do
    api_key = Config.get({:jupiter, :api_key})

    middleware = [
      {BaseUrl, swap_base_url()},
      {JSON, engine: Jason}
    ]

    # Add API key header if provided
    middleware =
      if api_key do
        [{Headers, [{"x-api-key", api_key}]} | middleware]
      else
        Logger.warning("Jupiter API key not configured. Some endpoints may fail.")
        middleware
      end

    Tesla.client(middleware)
  end

  @doc """
  Creates a client for the Jupiter Price API.
  """
  def price_client(_opts \\ []) do
    api_key = Config.get({:jupiter, :api_key})

    middleware = [
      {BaseUrl, price_base_url()},
      {JSON, engine: Jason}
    ]

    middleware =
      if api_key do
        [{Headers, [{"x-api-key", api_key}]} | middleware]
      else
        middleware
      end

    Tesla.client(middleware)
  end

  @doc """
  Creates a client for the Jupiter Token List API.
  """
  def token_list_client(_opts \\ []) do
    Tesla.client([
      {BaseUrl, Config.get({:jupiter, :token_list_base_url})},
      {JSON, engine: Jason}
    ])
  end

  @doc """
  Get a quote for swapping tokens.

  ## Parameters

  - `input_mint`: Input token mint address (string)
  - `output_mint`: Output token mint address (string)
  - `amount`: Amount to swap (positive integer, considering token decimals)
  - `slippage_bps`: Slippage in basis points (optional, non-negative integer, default: 50)
  - `options`: Additional options (optional map)

  ## Examples

      iex> ExJup.quote("So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1_000_000_000, 50)
      {:ok, %{...}}

  """
  @spec quote(Tesla.Client.t(), String.t(), String.t(), pos_integer(), non_neg_integer(), map()) ::
          {:ok, map()} | error()
  def quote(client, input_mint, output_mint, amount, slippage_bps \\ 50, options \\ %{})

  def quote(client, input_mint, output_mint, amount, slippage_bps, options)
      when is_binary(input_mint) and is_binary(output_mint) and is_integer(amount) and amount > 0 and
             is_integer(slippage_bps) and slippage_bps >= 0 and is_map(options) do
    query_params =
      Map.merge(options, %{
        inputMint: input_mint,
        outputMint: output_mint,
        amount: amount,
        slippageBps: slippage_bps
      })

    case Tesla.get(client, "/quote", query: query_params) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def quote(_, _, _, _, _, _), do: {:error, "Invalid parameters for quote"}

  @doc """
  Get a quote for swapping tokens using Jupiter v1 API.

  This function uses the latest Jupiter v1 API with support for all advanced features.

  ## Parameters

  - `client`: Tesla client
  - `input_mint`: Input token mint address (string)
  - `output_mint`: Output token mint address (string)
  - `amount`: Amount to swap (positive integer, considering token decimals)
  - `slippage_bps`: Slippage in basis points (optional, non-negative integer, default: 50)
  - `options`: Additional options (optional keyword list)

  ## Options

  - `:swap_mode` - Swap mode: `:ExactIn` (fixed input) or `:ExactOut` (fixed output). Default: `:ExactIn`
  - `:dexes` - Comma-separated list of DEXes to use (e.g., "Orca,Raydium")
  - `:exclude_dexes` - Comma-separated list of DEXes to exclude
  - `:restrict_intermediate_tokens` - Restrict intermediate tokens to stable ones. Default: `true`
  - `:only_direct_routes` - Only use direct routes (may result in worse routes). Default: `false`
  - `:as_legacy_transaction` - Use legacy transaction instead of versioned. Default: `false`
  - `:platform_fee_bps` - Platform fee in basis points. Default: `0`
  - `:max_accounts` - Maximum accounts for the quote. Default: `64`
  - `:instruction_version` - Instruction version: `:V1` or `:V2`. Default: `:V1`

  ## Examples

      iex> ExSolana.Jup.quote_v1(client, "So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1_000_000_000, 50)
      {:ok, %{...}}

      iex> ExSolana.Jup.quote_v1(client, "So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1_000_000, 50, swap_mode: :ExactOut)

      iex> ExSolana.Jup.quote_v1(client, "So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1_000_000_000, 50, dexes: "Orca,Raydium")

  """
  @spec quote_v1(Tesla.Client.t(), String.t(), String.t(), pos_integer(), non_neg_integer(),
          keyword()) :: {:ok, map()} | error()
  def quote_v1(client, input_mint, output_mint, amount, slippage_bps \\ 50, opts \\ [])

  def quote_v1(client, input_mint, output_mint, amount, slippage_bps, opts)
      when is_binary(input_mint) and is_binary(output_mint) and is_integer(amount) and
             amount > 0 and is_integer(slippage_bps) and slippage_bps >= 0 and
           is_list(opts) do
    query_params =
      %{
        inputMint: input_mint,
        outputMint: output_mint,
        amount: amount,
        slippageBps: slippage_bps
      }
      |> add_swap_mode(opts)
      |> add_dexes(opts)
      |> add_exclude_dexes(opts)
      |> add_restrict_intermediate_tokens(opts)
      |> add_only_direct_routes(opts)
      |> add_as_legacy_transaction(opts)
      |> add_platform_fee_bps(opts)
      |> add_max_accounts(opts)
      |> add_instruction_version(opts)

    case Tesla.get(client, "/quote", query: query_params) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        error = Errors.from_http_status(status)
        {:error, error}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def quote_v1(_, _, _, _, _, _), do: {:error, "Invalid parameters for quote_v1"}

  # Helper functions for quote_v1 options
  defp add_swap_mode(params, opts) do
    case Keyword.get(opts, :swap_mode, :ExactIn) do
      :ExactIn -> Map.put(params, :swapMode, "ExactIn")
      :ExactOut -> Map.put(params, :swapMode, "ExactOut")
      _ -> params
    end
  end

  defp add_dexes(params, opts) do
    case Keyword.get(opts, :dexes) do
      nil -> params
      dexes when is_binary(dexes) -> Map.put(params, :dexes, dexes)
      _ -> params
    end
  end

  defp add_exclude_dexes(params, opts) do
    case Keyword.get(opts, :exclude_dexes) do
      nil -> params
      dexes when is_binary(dexes) -> Map.put(params, :excludeDexes, dexes)
      _ -> params
    end
  end

  defp add_restrict_intermediate_tokens(params, opts) do
    value = Keyword.get(opts, :restrict_intermediate_tokens, true)
    Map.put(params, :restrictIntermediateTokens, value)
  end

  defp add_only_direct_routes(params, opts) do
    value = Keyword.get(opts, :only_direct_routes, false)
    Map.put(params, :onlyDirectRoutes, value)
  end

  defp add_as_legacy_transaction(params, opts) do
    value = Keyword.get(opts, :as_legacy_transaction, false)
    Map.put(params, :asLegacyTransaction, value)
  end

  defp add_platform_fee_bps(params, opts) do
    case Keyword.get(opts, :platform_fee_bps) do
      nil -> params
      fee when is_integer(fee) and fee >= 0 -> Map.put(params, :platformFeeBps, fee)
      _ -> params
    end
  end

  defp add_max_accounts(params, opts) do
    case Keyword.get(opts, :max_accounts) do
      nil -> params
      max when is_integer(max) and max > 0 -> Map.put(params, :maxAccounts, max)
      _ -> params
    end
  end

  defp add_instruction_version(params, opts) do
    case Keyword.get(opts, :instruction_version, :V1) do
      :V1 -> Map.put(params, :instructionVersion, "V1")
      :V2 -> Map.put(params, :instructionVersion, "V2")
      _ -> params
    end
  end

  @doc """
  Get swap instructions for a given quote.

  ## Parameters

  - `client`: Tesla client
  - `quote_response`: The response from the quote API (map)
  - `user_public_key`: User's public key (string)
  - `options`: Additional options (optional map)

  ## Examples

      iex> ExJup.swap_instructions(client, %{...}, "user_public_key")
      {:ok, %{...}}

  """
  @spec swap_instructions(Tesla.Client.t(), map(), String.t(), map()) :: {:ok, map()} | error()
  def swap_instructions(client, quote_response, user_public_key, options \\ %{})

  def swap_instructions(client, quote_response, user_public_key, options)
      when is_map(quote_response) and is_binary(user_public_key) and is_map(options) do
    body =
      Map.merge(options, %{quoteResponse: quote_response, userPublicKey: user_public_key})

    case Tesla.post(client, "/swap-instructions", body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def swap_instructions(_, _, _, _), do: {:error, "Invalid parameters for swap_instructions"}

  @doc """
  Get serialized transactions for a swap.

  ## Parameters

  - `quote_response`: The response from the quote API (map)
  - `user_public_key`: User's public key (string)
  - `options`: Additional options (optional map)

  ## Examples

      iex> ExJup.swap(%{...}, "user_public_key")
      {:ok, %{...}}

  """
  @spec swap(Tesla.Client.t(), map(), String.t(), map()) :: {:ok, map()} | error()
  def swap(client, quote_response, user_public_key, options \\ %{})

  def swap(client, quote_response, user_public_key, options)
      when is_map(quote_response) and is_binary(user_public_key) and is_map(options) do
    body =
      Map.merge(options, %{quoteResponse: quote_response, userPublicKey: user_public_key})

    case Tesla.post(client, "/swap", body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def swap(_, _, _, _), do: {:error, "Invalid parameters for swap"}

  @doc """
  Get token prices from Jupiter Price API.

  ## Parameters

  - `ids`: Token IDs (string or list of strings). Can be symbol or address.
  - `vs_token`: Optional. Token to price against. Defaults to USDC. (string)

  ## Examples

      iex> ExSolana.Jup.price("SOL")
      {:ok, %{...}}

      iex> ExSolana.Jup.price(["SOL", "BTC"], "mSOL")
      {:ok, %{...}}

  """
  @spec price(String.t() | [String.t()], String.t() | nil) :: {:ok, map()} | error()
  def price(ids, vs_token \\ nil)

  def price(ids, vs_token) when is_binary(ids) or is_list(ids) do
    price_client =
      Tesla.client([
        {BaseUrl, "https://price.jup.ag"},
        {JSON, engine: Jason}
      ])

    query = [ids: ids |> List.wrap() |> Enum.join(",")]
    query = if vs_token, do: [{:vsToken, vs_token} | query], else: query

    case Tesla.get(price_client, "/v6/price", query: query) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def price(_, _), do: {:error, "Invalid parameters for price"}

  @doc """
  Get token prices using Jupiter Price API V2.

  ## Parameters

  - `ids`: Token IDs (string or list of strings). Can be symbol or address. Maximum of 100 unique IDs allowed.
  - `options`: Additional options (optional map)
    - `:show_extra_info` - Boolean to include additional information in the response (default: false)

  ## Examples

      iex> ExSolana.Jup.price_v2("So11111111111111111111111111111111111111112")
      {:ok, %{...}}

      iex> ExSolana.Jup.price_v2(["So11111111111111111111111111111111111111112","JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"])
      {:ok, %{...}}

  """
  @spec price_v2(String.t() | [String.t()], map()) :: {:ok, map()} | error()
  def price_v2(ids, options \\ %{}) do
    price_v2_client = price_client()

    query = [ids: ids |> List.wrap() |> Enum.join(",")]
    query = if options[:show_extra_info], do: [{:showExtraInfo, "true"} | query], else: query

    case Tesla.get(price_v2_client, "/price/v2", query: query) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        Logger.warning("Price V2 API request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Get token information by mint address.

  ## Parameters

  - `mint_address`: Mint address of the token (string)

  ## Examples

      iex> ExSolana.Jup.get_token_by_mint("So11111111111111111111111111111111111111112")
      {:ok, %{...}}

  """
  @spec get_token_by_mint(String.t()) :: {:ok, map()} | error()
  def get_token_by_mint(mint_address) when is_binary(mint_address) do
    token_client = token_list_client()

    case Tesla.get(token_client, "/token/#{mint_address}") do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def get_token_by_mint(_), do: {:error, "Invalid parameters for get_token_by_mint"}

  @doc """
  Get tokens by tags.

  ## Parameters

  - `tags`: List of tags (list of atoms)

  ## Examples

      iex> ExSolana.Jup.get_tokens_by_tag([:community, :lst])
      {:ok, %{...}}

  """
  @spec get_tokens_by_tag([atom()]) :: {:ok, map()} | error()
  def get_tokens_by_tag(tags) when is_list(tags) do
    if Enum.all?(tags, &(&1 in @valid_token_tags)) do
      token_client = token_list_client()

      tags_param = Enum.join(Enum.map(tags, &Atom.to_string/1), ",")

      case Tesla.get(token_client, "/tokens", query: [tags: tags_param]) do
        {:ok, %{status: status, body: response_body}} when status in 200..299 ->
          {:ok, response_body}

        {:ok, %{status: status, body: response_body}} ->
          {:error, {status, response_body}}

        {:error, reason} ->
          {:error, "Request failed: #{inspect(reason)}"}
      end
    else
      {:error, "Invalid tags provided"}
    end
  end

  def get_tokens_by_tag(_), do: {:error, "Invalid parameters for get_tokens_by_tag"}

  @doc """
  Set the base URL at runtime.

  ## Parameters

  - `url`: New base URL (string)

  ## Examples

      iex> ExJup.set_base_url("https://new-api-url.com")
      :ok

  """
  @spec set_base_url(String.t()) :: :ok | {:error, String.t()}
  def set_base_url(url) when is_binary(url) do
    if String.starts_with?(url, "http") do
      Application.put_env(:ex_solana, :jup, base_url: url)
      :ok
    else
      {:error, "Invalid URL format"}
    end
  end

  def set_base_url(_), do: {:error, "Invalid URL"}

  @spec swap_base_url() :: String.t()
  defp swap_base_url do
    Config.get({:jupiter, :swap_base_url})
  end

  @spec price_base_url() :: String.t()
  defp price_base_url do
    Config.get({:jupiter, :price_base_url})
  end

  @spec base_url() :: String.t()
  defp base_url do
    # Deprecated: use swap_base_url/0 instead
    swap_base_url()
  end

  @doc """
  Calculate price impact from a quote response.

  Returns the price impact as a percentage (0.0 to 1.0).

  ## Examples

      iex> quote_response = %{"priceImpactPct" => "0.5"}
      iex> ExSolana.Jup.calculate_price_impact(quote_response)
      0.005

  """
  @spec calculate_price_impact(map()) :: float()
  def calculate_price_impact(%{"priceImpactPct" => impact_pct}) when is_binary(impact_pct) do
    case Float.parse(impact_pct) do
      {impact, _} -> impact / 100
      :error -> 0.0
    end
  end

  def calculate_price_impact(_), do: 0.0

  @doc """
  Calculate total fees from a quote response.

  Returns a map with total fees and breakdown.

  ## Examples

      iex> quote_response = %{"routePlan" => [%{"swapInfo" => %{"feeAmount" => "1000"}}]}
      iex> ExSolana.Jup.calculate_fees(quote_response)
      %{total: 1000, breakdown: [%{fee_amount: 1000, fee_mint: nil, label: nil}]}

  """
  @spec calculate_fees(map()) :: %{total: non_neg_integer(), breakdown: list()}
  def calculate_fees(%{"routePlan" => route_plan}) when is_list(route_plan) do
    breakdown =
      Enum.map(route_plan, fn route_step ->
        swap_info = Map.get(route_step, "swapInfo", %{})

        %{
          label: Map.get(swap_info, "label"),
          fee_amount: parse_fee_amount(Map.get(swap_info, "feeAmount", "0")),
          fee_mint: Map.get(swap_info, "feeMint")
        }
      end)

    total = Enum.reduce(breakdown, 0, fn %{fee_amount: amount}, acc -> acc + amount end)

    %{total: total, breakdown: breakdown}
  end

  def calculate_fees(_), do: %{total: 0, breakdown: []}

  # Parse fee amount from string to integer
  defp parse_fee_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {parsed, _} -> parsed
      :error -> 0
    end
  end

  defp parse_fee_amount(amount) when is_integer(amount), do: amount
  defp parse_fee_amount(_), do: 0
end
