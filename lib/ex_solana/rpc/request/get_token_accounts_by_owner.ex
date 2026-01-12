defmodule ExSolana.RPC.Request.GetTokenAccountsByOwner do
  @moduledoc """
  Functions for creating a getTokenAccountsByOwner request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_token_accounts_by_owner_options commitment_option() ++
                                         min_context_slot_option() ++
                                         encoding_option()

  @doc """
  Returns the 20 largest accounts of a particular SPL Token type.

  ## Parameters

  - `mint`: Pubkey of the token Mint to query, as a base-58 encoded string

  ## Options

  {NimbleOptions.docs(@get_token_largest_accounts_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokenaccountsbyowner).
  """
  @spec get_token_accounts_by_owner(ExSolana.key(), keyword()) ::
          Request.t() | {:error, String.t()}
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
