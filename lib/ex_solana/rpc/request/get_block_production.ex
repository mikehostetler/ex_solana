defmodule ExSolana.RPC.Request.GetBlockProduction do
  @moduledoc """
  Functions for creating a getBlockProduction request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_block_production_options commitment_option() ++
                                  [
                                    identity: [
                                      type: :string,
                                      doc:
                                        "Only return results for this validator identity (base-58 encoded)"
                                    ],
                                    range: [
                                      type: :map,
                                      keys: [:first_slot, :last_slot],
                                      doc:
                                        "Slot range to return block production for. If not provided, defaults to the current epoch."
                                    ]
                                  ]

  @doc """
  Returns recent block production information from the current or previous epoch.

  ## Options


  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblockproduction).
  """
  @spec get_block_production(keyword()) :: Request.t() | {:error, String.t()}
  def get_block_production(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_block_production_options) do
      {"getBlockProduction", [encode_opts(validated_opts)]}
    end
  end
end
