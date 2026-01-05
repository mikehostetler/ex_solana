defmodule ExSolana.RPC.Request.GetBlockCommitment do
  @moduledoc """
  Functions for creating a getBlockCommitment request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns commitment for particular block.

  ## Parameters

  - `slot`: The slot to get the block commitment for.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblockcommitment).
  """
  @spec get_block_commitment(non_neg_integer()) :: Request.t() | {:error, String.t()}
  def get_block_commitment(slot) when is_integer(slot) and slot >= 0 do
    {"getBlockCommitment", [slot]}
  end

  def get_block_commitment(_), do: {:error, "Invalid slot: expected non-negative integer"}
end
