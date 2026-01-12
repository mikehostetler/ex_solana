defmodule ExSolana.RPC.Request.GetLatestBlockhash do
  @moduledoc """
  Functions for creating a getlatestBlockhash request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_latest_blockhash_options commitment_option() ++
                                  min_context_slot_option()

  @doc """
  Returns a latest block hash from the ledger, and a fee schedule that can be used to compute the cost of submitting a transaction using it.

  ## Options

  {NimbleOptions.docs(@get_latest_blockhash_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getlatestblockhash).
  """
  @spec get_latest_blockhash(keyword()) :: Request.t() | {:error, String.t()}
  def get_latest_blockhash(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_latest_blockhash_options) do
      {"getLatestBlockhash", [encode_opts(validated_opts)]}
    end
  end
end
