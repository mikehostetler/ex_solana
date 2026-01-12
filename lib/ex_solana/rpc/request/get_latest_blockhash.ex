defmodule ExSolana.RPC.Request.GetLatestBlockhash do
  @moduledoc """
  Functions for creating a getLatestBlockhash request.

  Returns the latest blockhash from the ledger.

  ## Examples

      iex> ExSolana.RPC.Request.GetLatestBlockhash.get_latest_blockhash(commitment: "finalized")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getlatestblockhash).
  """

  import ExSolana.RPC.Request.Helpers

  @get_latest_blockhash_options commitment_option()

  @doc """
  Returns the latest blockhash from the ledger.

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetLatestBlockhash.get_latest_blockhash()
      {"getLatestBlockhash", [%{"commitment" => "confirmed"}]}

      iex> ExSolana.RPC.Request.GetLatestBlockhash.get_latest_blockhash(commitment: "finalized")
      {"getLatestBlockhash", [%{"commitment" => "finalized"}]}

  """
  @spec get_latest_blockhash(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_latest_blockhash(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_latest_blockhash_options) do
      {"getLatestBlockhash", [encode_opts(validated_opts)]}
    end
  end
end
