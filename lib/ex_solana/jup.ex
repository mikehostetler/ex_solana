defmodule ExSolana.Jup do
  @moduledoc """
  An Elixir client for the Jupiter Swap V6 API.
  """
  alias ExSolana.Config
  alias Tesla.Middleware.BaseUrl
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
    Tesla.client([
      {BaseUrl, base_url()},
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
    price_v2_client =
      Tesla.client([
        {BaseUrl, "https://api.jup.ag"},
        {JSON, engine: Jason}
      ])

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
    token_client =
      Tesla.client([
        {BaseUrl, @token_api_base_url},
        {JSON, engine: Jason}
      ])

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
      token_client =
        Tesla.client([
          {BaseUrl, @token_api_base_url},
          {JSON, engine: Jason}
        ])

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

  @spec base_url() :: String.t()
  defp base_url do
    Config.get({:jup, :base_url}) || "https://quote-api.jup.ag/v6"
  end
end
