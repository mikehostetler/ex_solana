defmodule ExSolana.Ix.JupiterSwap do
  @moduledoc """
  Functions for creating Jupiter swap instructions.

  Jupiter is a DEX aggregator that finds the best routes for token swaps
  across multiple DEXes on Solana.

  ## Options

  #{NimbleOptions.docs(@jupiter_swap_options)}

  ## Examples

      iex> alias ExSolana.Transaction.Builder
      iex> alias ExSolana.Ix.JupiterSwap
      iex>
      iex> builder = Builder.new()
      iex> builder = Builder.payer(builder, your_public_key)
      iex> builder = JupiterSwap.jupiter_swap(
      ...>   builder,
      ...>   "So11111111111111111111111111111111111111112",  # SOL
      ...>   "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
      ...>   1_000_000_000,  # 1 SOL in lamports
      ...>   50,  # 0.5% slippage
      ...>   swap_mode: :ExactIn
      ...> )

  """

  alias ExSolana.Account
  alias ExSolana.Instruction
  alias ExSolana.Jup
  alias ExSolana.RPC
  alias ExSolana.RPC.Request
  alias ExSolana.Transaction.Builder

  require Logger

  @jupiter_swap_options [
    swap_mode: [
      type: {:in, [:ExactIn, :ExactOut]},
      default: :ExactIn,
      doc: "Swap mode - ExactIn for fixed input, ExactOut for fixed output"
    ],
    dexes: [
      type: :string,
      doc: "Comma-separated list of DEXes to use (e.g., \"Orca,Raydium\")"
    ],
    exclude_dexes: [
      type: :string,
      doc: "Comma-separated list of DEXes to exclude"
    ],
    restrict_intermediate_tokens: [
      type: :boolean,
      default: true,
      doc: "Restrict intermediate tokens in route to stable ones"
    ],
    only_direct_routes: [
      type: :boolean,
      default: false,
      doc: "Only use direct routes (may result in worse routes)"
    ],
    as_legacy_transaction: [
      type: :boolean,
      default: false,
      doc: "Use legacy transaction instead of versioned transaction"
    ],
    platform_fee_bps: [
      type: :non_neg_integer,
      default: 0,
      doc: "Platform fee in basis points"
    ],
    max_accounts: [
      type: :non_neg_integer,
      default: 64,
      doc: "Maximum accounts for the quote"
    ],
    instruction_version: [
      type: {:in, [:V1, :V2]},
      default: :V1,
      doc: "Instruction version to use"
    ]
  ]

  @doc """
  Integrates a Jupiter swap transaction into the builder.

  This function:
  1. Gets a quote from Jupiter API
  2. Gets swap instructions from Jupiter API
  3. Fetches address lookup tables
  4. Parses and adds all instructions to the builder

  ## Parameters

  - `builder`: The current transaction builder
  - `from_mint`: Input token mint address
  - `to_mint`: Output token mint address
  - `amount`: Amount to swap (in smallest unit, considering decimals)
  - `slippage_bps`: Slippage tolerance in basis points (50 = 0.5%)
  - `opts`: Additional options (see NimbleOptions docs above)

  ## Returns

  - Updated transaction builder with Jupiter swap instructions
  - `{:error, reason}` if any step fails

  ## Examples

      iex> alias ExSolana.Transaction.Builder
      iex> alias ExSolana.Ix.JupiterSwap
      iex>
      iex> Builder.new()
      iex> |> Builder.payer(your_public_key)
      iex> |> JupiterSwap.jupiter_swap(
      ...>   "So11111111111111111111111111111111111111112",
      ...>   "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
      ...>   1_000_000_000,
      ...>   50,
      ...>   swap_mode: :ExactIn
      ...> )

  """
  @spec jupiter_swap(Builder.t(), String.t(), String.t(), pos_integer(), non_neg_integer(),
          keyword()) :: Builder.t() | {:error, term()}
  def jupiter_swap(builder \\ Builder.new(), from_mint, to_mint, amount, slippage_bps, opts) do
    with {:ok, validated_opts} <- validate_options(opts),
         {:ok, quote_response} <- get_quote(from_mint, to_mint, amount, slippage_bps, validated_opts),
         {:ok, swap_response} <- get_swap_instructions(quote_response, builder, validated_opts),
         {:ok, lookup_tables} <- fetch_lookup_tables(swap_response),
         {:ok, instructions} <- parse_swap_instructions(swap_response) do
      builder
      |> Builder.add_instructions(instructions)
      |> Builder.add_address_lookup_tables(lookup_tables)
    else
      {:error, %ExSolana.Jupiter.Errors{} = error} ->
        Logger.error("Jupiter swap failed: #{error.message}")
        {:error, error}

      {:error, reason} ->
        Logger.error("Jupiter swap failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Parse an instruction from Jupiter's response format.

  ## Parameters

  - `instruction`: Map with keys "programId", "accounts", "data"

  ## Returns

  An `ExSolana.Instruction` struct

  """
  @spec parse_instruction(map()) :: Instruction.t()
  def parse_instruction(instruction) when is_map(instruction) do
    accounts =
      Enum.map(instruction["accounts"] || [], fn account ->
        %Account{
          key: account["pubkey"],
          signer?: account["isSigner"] || false,
          writable?: account["isWritable"] || false
        }
      end)

    %Instruction{
      program: instruction["programId"],
      accounts: accounts,
      data: instruction["data"]
    }
  end

  # Private functions

  defp validate_options(opts) do
    NimbleOptions.validate(opts, @jupiter_swap_options)
  end

  defp get_quote(from_mint, to_mint, amount, slippage_bps, opts) do
    client = Jup.client()

    # Convert atom options to keyword list for quote_v1
    quote_opts =
      []
      |> maybe_add_option(opts, :swap_mode)
      |> maybe_add_option(opts, :dexes)
      |> maybe_add_option(opts, :exclude_dexes)
      |> maybe_add_option(opts, :restrict_intermediate_tokens)
      |> maybe_add_option(opts, :only_direct_routes)
      |> maybe_add_option(opts, :as_legacy_transaction)
      |> maybe_add_option(opts, :platform_fee_bps)
      |> maybe_add_option(opts, :max_accounts)
      |> maybe_add_option(opts, :instruction_version)

    case Jup.quote_v1(client, from_mint, to_mint, amount, slippage_bps, quote_opts) do
      {:ok, quote_response} ->
        {:ok, quote_response}

      {:error, %ExSolana.Jupiter.Errors{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_swap_instructions(quote_response, builder, opts) do
    client = Jup.client()
    user_public_key = B58.encode58(builder.payer)

    # Build request body with quote response and user public key
    body = %{
      quoteResponse: quote_response,
      userPublicKey: user_public_key
    }

    # Add optional parameters
    body =
      body
      |> maybe_add_body_field(opts, :dexes)
      |> maybe_add_body_field(opts, :exclude_dexes)
      |> maybe_add_body_field(opts, :restrict_intermediate_tokens)
      |> maybe_add_body_field(opts, :only_direct_routes)
      |> maybe_add_body_field(opts, :as_legacy_transaction)
      |> maybe_add_body_field(opts, :platform_fee_bps)
      |> maybe_add_body_field(opts, :max_accounts)
      |> maybe_add_body_field(opts, :instruction_version)

    case Tesla.post(client, "/swap-instructions", body) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        {:ok, response_body}

      {:ok, %{status: status, body: response_body}} ->
        error = ExSolana.Jupiter.Errors.from_http_status(status)
        {:error, error}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp fetch_lookup_tables(swap_response) do
    address_lookups = Map.get(swap_response, "addressLookupTableAddresses", [])

    if Enum.empty?(address_lookups) do
      {:ok, []}
    else
      client = ExSolana.rpc_client()

      case RPC.send(client, Request.get_multiple_accounts(address_lookups)) do
        {:ok, _accounts} -> {:ok, address_lookups}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp parse_swap_instructions(swap_response) do
    try do
      compute_budget_instructions =
        swap_response
        |> Map.get("computeBudgetInstructions", [])
        |> Enum.map(&parse_instruction/1)

      setup_instructions =
        swap_response
        |> Map.get("setupInstructions", [])
        |> Enum.map(&parse_instruction/1)

      swap_instruction =
        swap_response
        |> Map.get("swapInstruction")
        |> parse_instruction()

      cleanup_instruction =
        case Map.get(swap_response, "cleanupInstruction") do
          nil -> []
          cleanup -> [parse_instruction(cleanup)]
        end

      all_instructions =
        compute_budget_instructions ++ setup_instructions ++ [swap_instruction] ++
          cleanup_instruction

      {:ok, all_instructions}
    rescue
      error -> {:error, error}
    end
  end

  # Helper functions for building option lists
  defp maybe_add_option(list, opts, key) do
    case Keyword.get(opts, key) do
      nil -> list
      value -> [{key, value} | list]
    end
  end

  defp maybe_add_body_field(body, opts, key) do
    case Keyword.get(opts, key) do
      nil -> body
      value -> Map.put(body, key, value)
    end
  end
end
