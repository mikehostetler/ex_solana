defmodule ExSolana.RPC.Request.GetBlocks do
  @moduledoc """
  Functions for creating a getBlocks request.

  Returns a list of confirmed blocks between two slots.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblocks).
  """

  import ExSolana.RPC.Request.Helpers

  @get_blocks_options commitment_option() ++
                        [
                          start_slot: [
                            type: :non_neg_integer,
                            required: true,
                            doc: "Start slot (inclusive)"
                          ],
                          end_slot: [
                            type: :non_neg_integer,
                            required: true,
                            doc: "End slot (inclusive)"
                          ]
                        ]

  @doc """
  Returns a list of confirmed blocks between two slots.

  ## Parameters

  - `start_slot`: Start slot (inclusive)
  - `end_slot`: End slot (inclusive)

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.GetBlocks.get_blocks(100, 200)
      {"getBlocks", [100, 200, %{"commitment" => "confirmed"}]}

  """
  @spec get_blocks(non_neg_integer(), non_neg_integer(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_blocks(start_slot, end_slot, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_blocks_options) do
      {"getBlocks", [start_slot, end_slot, encode_opts(validated_opts)]}
    end
  end
end
