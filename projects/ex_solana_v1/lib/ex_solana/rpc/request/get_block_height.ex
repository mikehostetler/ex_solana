defmodule ExSolana.RPC.Request.GetBlockHeight do
  @moduledoc """
  Functions for creating a getBlockHeight request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_block_height_options commitment_option() ++
                              min_context_slot_option()

  @doc """
  Returns the current block height of the node.

  ## Options

  {NimbleOptions.docs(@get_block_height_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblockheight).
  """
  @spec get_block_height(keyword()) :: Request.t() | {:error, String.t()}
  def get_block_height(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_block_height_options) do
      {"getBlockHeight", [encode_opts(validated_opts)]}
    end
  end
end
