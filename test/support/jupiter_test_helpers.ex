defmodule ExSolana.JupiterTestHelpers do
  @moduledoc """
  Helper functions and mock data for testing Jupiter functionality.

  This module provides convenient mock data and helpers to facilitate testing
  of Jupiter swap functionality without making actual API calls.

  ## Examples

  Use in tests:

      use ExUnit.Case
      import ExSolana.JupiterTestHelpers

      test "mock quote response" do
        quote = mock_quote_response()
        assert quote["inputMint"] == test_tokens().sol
      end

  """

  @doc """
  Returns a mock Jupiter quote response for testing.

  ## Options

  * `:input_mint` - Input token mint address. Default: SOL
  * `:output_mint` - Output token mint address. Default: USDC
  * `:in_amount` - Input amount. Default: 1_000_000_000 (1 SOL)
  * `:out_amount` - Output amount. Default: 9_950_000 (USDC)
  * `:slippage_bps` - Slippage in basis points. Default: 50
  * `:price_impact` - Price impact percentage. Default: "0.5"
  * `:swap_mode` - Swap mode. Default: "ExactIn"

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_quote_response()
      %{...}

      iex> ExSolana.JupiterTestHelpers.mock_quote_response(in_amount: 100_000_000)
      %{...}

  """
  @spec mock_quote_response(keyword()) :: map()
  def mock_quote_response(opts \\ []) do
    input_mint = Keyword.get(opts, :input_mint, test_tokens().sol)
    output_mint = Keyword.get(opts, :output_mint, test_tokens().usdc)
    in_amount = Keyword.get(opts, :in_amount, 1_000_000_000)
    out_amount = Keyword.get(opts, :out_amount, 9_950_000)
    slippage_bps = Keyword.get(opts, :slippage_bps, 50)
    price_impact = Keyword.get(opts, :price_impact, "0.5")
    swap_mode = Keyword.get(opts, :swap_mode, "ExactIn")

    %{
      "inputMint" => input_mint,
      "inAmount" => to_string(in_amount),
      "outputMint" => output_mint,
      "outAmount" => to_string(out_amount),
      "otherAmountThreshold" => to_string(trunc(out_amount * 0.995)),
      "swapMode" => swap_mode,
      "slippageBps" => slippage_bps,
      "platformFee" => %{
        "amount" => "0",
        "feeBps" => 0
      },
      "priceImpactPct" => price_impact,
      "routePlan" => [
        %{
          "swapInfo" => %{
            "ammKey" => "HXpGFJGCEEFdV31tDmjDBaJMEB1fKLiAoKoWr3Fnonid",
            "label" => "Orca",
            "inputMint" => input_mint,
            "outputMint" => output_mint,
            "inAmount" => to_string(in_amount),
            "outAmount" => to_string(out_amount),
            "feeAmount" => "10000",
            "feeMint" => input_mint
          },
          "percent" => 100
        }
      ],
      "contextSlot" => 123_456_789,
      "timeTaken" => 0.012
    }
  end

  @doc """
  Returns a mock swap instructions response for testing.

  ## Options

  * `:include_lookup_tables` - Whether to include address lookup tables. Default: false
  * `:include_cleanup` - Whether to include cleanup instruction. Default: true
  * `:include_compute_budget` - Whether to include compute budget instructions. Default: true

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_swap_instructions_response()
      %{...}

      iex> ExSolana.JupiterTestHelpers.mock_swap_instructions_response(include_lookup_tables: true)
      %{...}

  """
  @spec mock_swap_instructions_response(keyword()) :: map()
  def mock_swap_instructions_response(opts \\ []) do
    include_lookup_tables = Keyword.get(opts, :include_lookup_tables, false)
    include_cleanup = Keyword.get(opts, :include_cleanup, true)
    include_compute_budget = Keyword.get(opts, :include_compute_budget, true)

    response = %{
      "swapInstruction" => %{
        "programId" => "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",
        "accounts" => [
          %{
            "pubkey" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
            "isSigner" => false,
            "isWritable" => false
          },
          %{
            "pubkey" => "USER_PUBLIC_KEY",
            "isSigner" => true,
            "isWritable" => false
          },
          %{
            "pubkey" => "INPUT_TOKEN_ACCOUNT",
            "isSigner" => false,
            "isWritable" => true
          },
          %{
            "pubkey" => "OUTPUT_TOKEN_ACCOUNT",
            "isSigner" => false,
            "isWritable" => true
          }
        ],
        "data" => Base.encode64(<<0::size(8)>>)
      }
    }

    response =
      if include_compute_budget do
        Map.put(response, "computeBudgetInstructions", [
          %{
            "programId" => "ComputeBudget111111111111111111111111111111",
            "accounts" => [],
            "data" => Base.encode64(<<2::little-unsigned-integer-size(8), 200_000::little-unsigned-integer-size(32)>>)
          },
          %{
            "programId" => "ComputeBudget111111111111111111111111111111",
            "accounts" => [],
            "data" => Base.encode64(<<3::little-unsigned-integer-size(8), 1_000::little-unsigned-integer-size(64)>>)
          }
        ])
      else
        Map.put(response, "computeBudgetInstructions", [])
      end

    response =
      if include_cleanup do
        Map.put(response, "cleanupInstruction", %{
          "programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",
          "accounts" => [
            %{
              "pubkey" => "USER_PUBLIC_KEY",
              "isSigner" => true,
              "isWritable" => false
            }
          ],
          "data" => Base.encode64(<<0::size(8)>>)
        })
      else
        response
      end

    response =
      if include_lookup_tables do
        Map.put(response, "addressLookupTableAddresses", [
          "AddressLookupTab1eMyKuqeLJQvxUZyiBvsvUEszo9raofMWNdLh",
          "AddressLookupTab1eMyKuqeLJQvxUZyiBvsvUEszo9raofMWNdLh"
        ])
      else
        Map.put(response, "addressLookupTableAddresses", [])
      end

    Map.put(response, "setupInstructions", [])
  end

  @doc """
  Returns common test token mint addresses.

  ## Returns

  Map with atom keys:
  * `:sol` - Native SOL mint
  * `:usdc` - USDC mint
  * `:usdt` - USDT mint
  * `:ray` - RAY token mint
  * `:jup` - JUP token mint

  ## Examples

      iex> tokens = ExSolana.JupiterTestHelpers.test_tokens()
      iex> tokens.sol
      "So11111111111111111111111111111111111111112"

  """
  @spec test_tokens() :: %{
          sol: String.t(),
          usdc: String.t(),
          usdt: String.t(),
          ray: String.t(),
          jup: String.t()
        }
  def test_tokens do
    %{
      sol: "So11111111111111111111111111111111111111112",
      usdc: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
      usdt: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
      ray: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
      jup: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
    }
  end

  @doc """
  Returns a mock price API response.

  ## Parameters

  - `tokens` - List of token addresses to get prices for

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_price_response(["So11111111111111111111111111111111111111112"])
      %{...}

  """
  @spec mock_price_response([String.t()]) :: map()
  def mock_price_response(tokens) when is_list(tokens) do
    data =
      Map.new(tokens, fn token ->
        {token, %{"id" => token, "price" => "100.00"}}
      end)

    %{
      "data" => data
    }
  end

  @doc """
  Returns a mock token list response.

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_token_list_response()
      %{...}

  """
  @spec mock_token_list_response() :: map()
  def mock_token_list_response do
    %{
      "length" => 10,
      "tokens" => [
        %{
          "address" => "So11111111111111111111111111111111111111112",
          "symbol" => "SOL",
          "decimals" => 9,
          "name" => "Wrapped SOL",
          "tags" => ["verified", "native"]
        },
        %{
          "address" => "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
          "symbol" => "USDC",
          "decimals" => 6,
          "name" => "USDC",
          "tags" => ["verified", "stablecoin"]
        }
      ]
    }
  end

  @doc """
  Creates a mock transaction signature for testing.

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_signature()
      "5j7s6NiJS3JAkvgkoc18WVAsiSaci2pxB2A6ueCJP4tprA2u62nm8Z6xYvbdGsiLYZ"

  """
  @spec mock_signature() :: String.t()
  def mock_signature do
    # Generate a fake signature (not a valid Solana signature)
    "5j7s6NiJS3JAkvgkoc18WVAsiSaci2pxB2A6ueCJP4tprA2u62nm8Z6xYvbdGsiLYZ" <>
      "8N9x3z8XH4mP2w7R1b4Q6cE3vT0nL5K9jS2dA6fG1hY8jK3pN4mQ7rT1vW6xZ"
  end

  @doc """
  Returns a mock RPC response for get_multiple_accounts.

  ## Parameters

  - `accounts` - List of account addresses

  ## Examples

      iex> ExSolana.JupiterTestHelpers.mock_get_multiple_accounts_response(["address1", "address2"])
      %{"result" => %{...}}

  """
  @spec mock_get_multiple_accounts_response([String.t()]) :: map()
  def mock_get_multiple_accounts_response(accounts) when is_list(accounts) do
    account_infos =
      Enum.map(accounts, fn address ->
        %{
          "account" => %{
            "data" => ["", "base64"],
            "executable" => false,
            "lamports" => 1_000_000,
            "owner" => "AccountOwner11111111111111111111111111111",
            "rentEpoch" => 0
          },
          "pubkey" => address
        }
      end)

    %{
      "result" => %{
        "context" => %{"slot" => 123_456_789},
        "value" => account_infos
      }
    }
  end
end
