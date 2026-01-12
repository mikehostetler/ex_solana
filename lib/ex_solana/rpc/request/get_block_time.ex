defmodule ExSolana.RPC.Request.GetBlockTime do
  @moduledoc """
  Functions for creating a getBlockTime request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns the estimated production time of a block.

  ## Parameters

  - `slot`: The slot to get the block time for.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblocktime).
  """
  @spec get_block_time(non_neg_integer()) :: Request.t() | {:error, String.t()}
  def get_block_time(slot) when is_integer(slot) and slot >= 0 do
    {"getBlockTime", [slot]}
  end

  def get_block_time(_), do: {:error, "Invalid slot: expected non-negative integer"}
end
