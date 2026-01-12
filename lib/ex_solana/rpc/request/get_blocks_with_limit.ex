defmodule ExSolana.RPC.Request.GetBlocksWithLimit do
  @moduledoc """
  Functions for creating a getBlocksWithLimit request.

  Returns a list of confirmed blocks starting at the given slot.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblockswithLimit).
  """

  import ExSolana.RPC.Request.Helpers

  @get_blocks_with_limit_options commitment_option() ++
                                   [
                                     start_slot: [
                                       type: :non_neg_integer,
                                       required: true,
                                       doc: "Start slot (inclusive)"
                                     ],
                                     limit: [
                                       type: :pos_integer,
                                       required: true,
                                       doc: "Limit (number of blocks to return)"
                                     ]
                                   ]

  @doc """
  Returns a list of confirmed blocks starting at the given slot.

  ## Parameters

  - `start_slot`: Start slot (inclusive)
  - `limit`: Limit (number of blocks to return)

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.GetBlocksWithLimit.get_blocks_with_limit(100, 10)
      {"getBlocksWithLimit", [100, 10, %{"commitment" => "confirmed"}]}

  """
  @spec get_blocks_with_limit(non_neg_integer(), pos_integer(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_blocks_with_limit(start_slot, limit, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_blocks_with_limit_options) do
      {"getBlocksWithLimit", [start_slot, limit, encode_opts(validated_opts)]}
    end
  end
end
