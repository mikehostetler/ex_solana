defmodule ExSolana.RPC.Request.GetTransaction do
  @moduledoc """
  Functions for creating a getTransaction request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_transaction_options commitment_option() ++
                             encoding_option() ++
                             [
                               max_supported_transaction_version: [
                                 type: :non_neg_integer,
                                 doc: "Set the max transaction version to return in responses"
                               ]
                             ]

  @doc """
  Returns transaction details for a confirmed transaction.

  ## Parameters

  - `signature`: Transaction signature as base-58 encoded string

  ## Options

  {NimbleOptions.docs(@get_transaction_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettransaction).
  """
  @spec get_transaction(String.t(), keyword()) :: Request.t() | {:error, String.t()}
  def get_transaction(signature, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_transaction_options),
         {:ok, encoded_signature} <- encode_signature(signature) do
      {"getTransaction", [encoded_signature, encode_opts(validated_opts)]}
    end
  end
end
