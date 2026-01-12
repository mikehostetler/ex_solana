defmodule ExSolana.RPC.Request.GetProgramAccounts do
  @moduledoc """
  Functions for creating a getProgramAccounts request.

  Returns all accounts owned by the provided program Pubkey.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getprogramaccounts).
  """

  import ExSolana.RPC.Request.Helpers

  @get_program_accounts_options commitment_option() ++
                                  min_context_slot_option() ++
                                  encoding_option() ++
                                  with_context_option() ++
                                  data_slice_option() ++
                                  filters_option()

  @doc """
  Returns all accounts owned by the provided program Pubkey.

  ## Parameters

  - `pubkey`: The program Pubkey to query, as a base-58 encoded string

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
  - `:with_context` - Include context in response (default: false)
  - `:data_slice` - Limits the returned account data
  - `:min_context_slot` - Minimum slot to fetch context from
  - `:filters` - Filter results

  ## Examples

      iex> ExSolana.RPC.Request.GetProgramAccounts.get_program_accounts("program_pubkey")
      {"getProgramAccounts", ["program_pubkey", %{"commitment" => "confirmed", "encoding" => "base64"}]}

  """
  @spec get_program_accounts(binary(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_program_accounts(pubkey, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_program_accounts_options),
         {:ok, encoded_pubkey} <- encode_key(pubkey) do
      {"getProgramAccounts", [encoded_pubkey, encode_opts(validated_opts)]}
    end
  end
end
