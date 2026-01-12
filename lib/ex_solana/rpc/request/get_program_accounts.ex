defmodule ExSolana.RPC.Request.GetProgramAccounts do
  @moduledoc """
  Functions for creating a getProgramAccounts request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  require IEx

  # with_context_option() ++
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

  {NimbleOptions.docs(@get_program_accounts_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getprogramaccounts).
  """
  @spec get_program_accounts(ExSolana.key(), keyword()) :: Request.t() | {:error, String.t()}
  def get_program_accounts(pubkey, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_program_accounts_options),
         {:ok, encoded_pubkey} <- encode_key(pubkey) do
      {"getProgramAccounts", [encoded_pubkey, encode_opts(validated_opts)]}
    end
  end
end
