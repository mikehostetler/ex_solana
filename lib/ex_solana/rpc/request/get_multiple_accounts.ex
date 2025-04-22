defmodule ExSolana.RPC.Request.GetMultipleAccounts do
  @moduledoc """
  Functions for creating a getMultipleAccounts request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_multiple_accounts_options commitment_option() ++
                                   encoding_option() ++
                                   data_slice_option()

  @doc """
  Returns the account information for a list of Pubkeys.

  ## Parameters

  - `pubkeys`: An array of Pubkeys to query, as base-58 encoded strings

  ## Options

  {NimbleOptions.docs(@get_multiple_accounts_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getmultipleaccounts).
  """
  @spec get_multiple_accounts([ExSolana.key()], keyword()) :: Request.t() | {:error, String.t()}
  def get_multiple_accounts(pubkeys, opts \\ []) when is_list(pubkeys) do
    with {:ok, validated_opts} <- validate(opts, @get_multiple_accounts_options),
         {:ok, encoded_pubkeys} <- encode_pubkeys(pubkeys) do
      {"getMultipleAccounts", [encoded_pubkeys, encode_opts(validated_opts)]}
    end
  end

  defp encode_pubkeys(pubkeys) do
    encoded = Enum.map(pubkeys, &encode_key/1)

    if Enum.all?(encoded, fn result -> match?({:ok, _}, result) end) do
      {:ok, Enum.map(encoded, fn {:ok, key} -> key end)}
    else
      {:error, "Failed to encode one or more pubkeys"}
    end
  end
end
