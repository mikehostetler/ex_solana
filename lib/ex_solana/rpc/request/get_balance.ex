defmodule ExSolana.RPC.Request.GetBalance do
  @moduledoc """
  Functions for creating a getBalance request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_balance_options commitment_option() ++
                         min_context_slot_option()

  @doc """
  Returns the balance of the provided pubkey's account.

  ## Options

  {NimbleOptions.docs(@get_balance_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getbalance).
  """
  @spec get_balance(ExSolana.key(), keyword()) :: Request.t() | {:error, String.t()}
  def get_balance(account, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_balance_options),
         {:ok, encoded_account} <- encode_key(account) do
      {"getBalance", [encoded_account, encode_opts(validated_opts)]}
    end
  end
end
