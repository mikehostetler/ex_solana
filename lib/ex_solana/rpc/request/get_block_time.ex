defmodule ExSolana.RPC.Request.GetBlockTime do
  @moduledoc """
  Functions for creating a getBlockTime request.

  Returns the estimated production time of a block.

  ## Examples

      iex> ExSolana.RPC.Request.GetBlockTime.get_block_time(12345)

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblocktime).
  """

  @doc """
  Returns the estimated production time of a block.

  ## Parameters

    * `slot` - The slot number to query

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request

  ## Examples

      iex> ExSolana.RPC.Request.GetBlockTime.get_block_time(12345)
      {"getBlockTime", [12345]}

  """
  @spec get_block_time(non_neg_integer()) :: {String.t(), list()}
  def get_block_time(slot) do
    {"getBlockTime", [slot]}
  end
end
