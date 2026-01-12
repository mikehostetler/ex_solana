defmodule ExSolana.RPC.Request.GetAccountInfo do
  @moduledoc """
  Functions for creating a getAccountInfo request.

  Returns all information associated with the account of the provided Pubkey.

  ## Examples

      iex> ExSolana.RPC.Request.GetAccountInfo.get_account_info("pubkey", encoding: "base64")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getaccountinfo).
  """

  import ExSolana.RPC.Request.Helpers

  @get_account_info_options commitment_option() ++
                               encoding_option() ++
                               data_slice_option() ++
                               min_context_slot_option()

  @doc """
  Returns all information associated with the account of the provided Pubkey.

  ## Parameters

    * `account` - The public key of the account to query

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
    * `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
    * `:data_slice` - Limits the returned account data (map with :length and :offset keys)
    * `:min_context_slot` - Minimum slot to fetch context from

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if encoding or validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetAccountInfo.get_account_info("pubkey")
      {"getAccountInfo", ["pubkey", %{"commitment" => "confirmed", "encoding" => "base64"}]}

      iex> ExSolana.RPC.Request.GetAccountInfo.get_account_info("pubkey", encoding: "jsonParsed")
      {"getAccountInfo", ["pubkey", %{"commitment" => "confirmed", "encoding" => "jsonParsed"}]}

  """
  @spec get_account_info(ExSolana.Key.t(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_account_info(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_account_info_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getAccountInfo", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
