defmodule ExSolana.RPC.Request.GetBalance do
  @moduledoc """
  Functions for creating a getBalance request.

  Returns the balance of the provided pubkey's account.

  ## Examples

      iex> ExSolana.RPC.Request.GetBalance.get_balance("pubkey", commitment: "confirmed")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getbalance).
  """

  import ExSolana.RPC.Request.Helpers

  @get_balance_options commitment_option() ++ min_context_slot_option()

  @doc """
  Returns the balance of the provided pubkey's account.

  ## Parameters

    * `account` - The public key of the account to query

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
    * `:min_context_slot` - Minimum slot to fetch context from

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if encoding or validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetBalance.get_balance("pubkey")
      {"getBalance", ["pubkey", %{"commitment" => "confirmed"}]}

      iex> ExSolana.RPC.Request.GetBalance.get_balance("pubkey", commitment: "finalized")
      {"getBalance", ["pubkey", %{"commitment" => "finalized"}]}

  """
  @spec get_balance(ExSolana.Key.t(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_balance(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_balance_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getBalance", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
