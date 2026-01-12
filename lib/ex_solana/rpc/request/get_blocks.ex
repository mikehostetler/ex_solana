defmodule ExSolana.RPC.Request.GetBlocks do
  @moduledoc """
  Functions for creating a getBlocks request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

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

  {NimbleOptions.docs(@get_blocks_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblocks).
  """
  @spec get_blocks(non_neg_integer(), non_neg_integer(), keyword()) ::
          Request.t() | {:error, String.t()}
  def get_blocks(start_slot, end_slot, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_blocks_options) do
      {"getBlocks", [start_slot, end_slot, encode_opts(validated_opts)]}
    end
  end
end
