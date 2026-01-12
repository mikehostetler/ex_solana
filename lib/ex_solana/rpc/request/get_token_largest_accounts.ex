defmodule ExSolana.RPC.Request.GetTokenLargestAccounts do
  @moduledoc """
  Functions for creating a getTokenLargestAccounts request.

  Returns the 20 largest accounts of a particular SPL Token type.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokenlargestaccounts).
  """

  import ExSolana.RPC.Request.Helpers

  @get_token_largest_accounts_options commitment_option()

  @doc """
  Returns the 20 largest accounts of a particular SPL Token type.

  ## Parameters

  - `mint`: Pubkey of the token Mint to query, as a base-58 encoded string

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.GetTokenLargestAccounts.get_token_largest_accounts("mint")
      {"getTokenLargestAccounts", ["mint", %{"commitment" => "confirmed"}]}

  """
  @spec get_token_largest_accounts(binary(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_token_largest_accounts(mint, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_token_largest_accounts_options),
         {:ok, encoded_mint} <- encode_key(mint) do
      {"getTokenLargestAccounts", [encoded_mint, encode_opts(validated_opts)]}
    end
  end
end
