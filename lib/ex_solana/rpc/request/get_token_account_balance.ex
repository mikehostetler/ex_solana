defmodule ExSolana.RPC.Request.GetTokenAccountBalance do
  @moduledoc """
  Functions for creating a getTokenAccountBalance request.

  Returns the token balance of an SPL Token account.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokenaccountbalance).
  """

  import ExSolana.RPC.Request.Helpers

  @get_token_account_balance_options commitment_option()

  @doc """
  Returns the token balance of an SPL Token account.

  ## Parameters

  - `account`: Pubkey of Token account to query, as a base-58 encoded string

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.GetTokenAccountBalance.get_token_account_balance("account")
      {"getTokenAccountBalance", ["account", %{"commitment" => "confirmed"}]}

  """
  @spec get_token_account_balance(binary(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_token_account_balance(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_token_account_balance_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getTokenAccountBalance", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
