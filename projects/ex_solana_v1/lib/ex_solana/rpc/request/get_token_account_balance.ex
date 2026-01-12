defmodule ExSolana.RPC.Request.GetTokenAccountBalance do
  @moduledoc """
  Functions for creating a getTokenAccountBalance request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_token_account_balance_options commitment_option()

  @doc """
  Returns the token balance of an SPL Token account.

  ## Parameters

  - `account`: Pubkey of Token account to query, as a base-58 encoded string

  ## Options

  {NimbleOptions.docs(@get_token_account_balance_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokenaccountbalance).
  """
  @spec get_token_account_balance(ExSolana.key(), keyword()) :: Request.t() | {:error, String.t()}
  def get_token_account_balance(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_token_account_balance_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getTokenAccountBalance", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
