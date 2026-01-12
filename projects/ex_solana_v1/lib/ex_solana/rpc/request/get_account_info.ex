defmodule ExSolana.RPC.Request.GetAccountInfo do
  @moduledoc """
  Functions for creating a getAccountInfo request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_account_info_options commitment_option() ++
                              encoding_option() ++
                              data_slice_option() ++
                              min_context_slot_option()

  @doc """
  Returns all information associated with the account of the provided Pubkey.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getaccountinfo).
  ## Options


  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getaccountinfo).
  """
  @spec get_account_info(ExSolana.key(), keyword()) :: Request.t() | {:error, String.t()}
  def get_account_info(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_account_info_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getAccountInfo", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
