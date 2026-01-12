defmodule ExSolana.RPC.Request.GetRecentBlockhash do
  @moduledoc """
  Functions for creating a getRecentBlockhash request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_recent_blockhash_options commitment_option() ++
                                  min_context_slot_option()

  @doc """
  Returns a recent block hash from the ledger, and a fee schedule that can be used to compute the cost of submitting a transaction using it.

  ## Options

  {NimbleOptions.docs(@get_recent_blockhash_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getrecentblockhash).
  """
  @spec get_recent_blockhash(keyword()) :: Request.t() | {:error, String.t()}
  def get_recent_blockhash(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_recent_blockhash_options) do
      # TODO: Deprecate this function in favor of get_latest_blockhash
      {"getRecentBlockhash", [encode_opts(validated_opts)]}
    end
  end
end
