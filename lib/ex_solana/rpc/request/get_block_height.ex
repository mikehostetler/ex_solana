defmodule ExSolana.RPC.Request.GetBlockHeight do
  @moduledoc """
  Functions for creating a getBlockHeight request.

  Returns the current block height.

  ## Examples

      iex> ExSolana.RPC.Request.GetBlockHeight.get_block_height(commitment: "confirmed")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblockheight).
  """

  import ExSolana.RPC.Request.Helpers

  @get_block_height_options commitment_option()

  @doc """
  Returns the current block height.

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetBlockHeight.get_block_height()
      {"getBlockHeight", [%{"commitment" => "confirmed"}]}

      iex> ExSolana.RPC.Request.GetBlockHeight.get_block_height(commitment: "finalized")
      {"getBlockHeight", [%{"commitment" => "finalized"}]}

  """
  @spec get_block_height(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_block_height(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_block_height_options) do
      {"getBlockHeight", [encode_opts(validated_opts)]}
    end
  end
end
