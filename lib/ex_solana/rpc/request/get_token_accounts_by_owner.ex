defmodule ExSolana.RPC.Request.GetTokenAccountsByOwner do
  @moduledoc """
  Functions for creating a getTokenAccountsByOwner request.

  Returns all SPL Token accounts by token owner.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokenaccountsbyowner).
  """

  import ExSolana.RPC.Request.Helpers

  @get_token_accounts_by_owner_options commitment_option() ++
                                         min_context_slot_option() ++
                                         encoding_option()

  @doc """
  Returns all SPL Token accounts by token owner.

  ## Parameters

  - `owner`: Owner Pubkey to query, as a base-58 encoded string

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
  - `:min_context_slot` - Minimum slot to fetch context from

  ## Examples

      iex> ExSolana.RPC.Request.GetTokenAccountsByOwner.get_token_accounts_by_owner("owner")
      {"getTokenAccountsByOwner", ["owner", %{"programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"}, %{"commitment" => "confirmed", "encoding" => "base64"}]}

  """
  @spec get_token_accounts_by_owner(binary(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_token_accounts_by_owner(owner, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_token_accounts_by_owner_options),
         {:ok, encoded_owner} <- encode_key(owner) do
      {"getTokenAccountsByOwner",
       [
         encoded_owner,
         %{"programId" => "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"},
         encode_opts(validated_opts)
       ]}
    end
  end
end
