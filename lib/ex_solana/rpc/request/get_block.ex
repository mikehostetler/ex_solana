defmodule ExSolana.RPC.Request.GetBlock do
  @moduledoc """
  Functions for creating a getBlock request.

  Returns identity and transaction information about a confirmed block in the ledger.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblock).
  """

  import ExSolana.RPC.Request.Helpers

  @get_block_options commitment_option() ++
                       encoding_option() ++
                       [
                         transaction_details: [
                           type: {:in, ["full", "accounts", "signatures", "none"]},
                           doc: "Level of transaction detail to return."
                         ],
                         max_supported_transaction_version: [
                           type: :non_neg_integer,
                           doc: "The max transaction version to return in responses."
                         ],
                         rewards: [
                           type: :boolean,
                           doc: "Whether to populate the rewards array."
                         ]
                       ]

  @doc """
  Returns identity and transaction information about a confirmed block in the ledger.

  ## Parameters

  - `slot`: The slot to get the block for.

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
  - `:transaction_details` - Level of transaction detail ("full", "accounts", "signatures", "none")
  - `:max_supported_transaction_version` - Max transaction version to return
  - `:rewards` - Whether to populate rewards array

  ## Examples

      iex> ExSolana.RPC.Request.GetBlock.get_block(123)
      {"getBlock", [123, %{"commitment" => "confirmed", "encoding" => "base64"}]}

  """
  @spec get_block(non_neg_integer(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_block(slot, opts \\ [])

  def get_block(slot, opts) when is_integer(slot) and slot >= 0 do
    with {:ok, validated_opts} <- validate(opts, @get_block_options) do
      {"getBlock", [slot, encode_opts(validated_opts)]}
    end
  end

  def get_block(slot, _opts) when not is_integer(slot) or slot < 0 do
    {:error, "Invalid slot: must be a non-negative integer"}
  end
end
