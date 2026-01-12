defmodule ExSolana.RPC.Request.GetTransaction do
  @moduledoc """
  Functions for creating a getTransaction request.

  Returns transaction details for a confirmed transaction.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettransaction).
  """

  import ExSolana.RPC.Request.Helpers

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

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
  - `:max_supported_transaction_version` - Max transaction version to return

  ## Examples

      iex> ExSolana.RPC.Request.GetTransaction.get_transaction("signature")
      {"getTransaction", ["signature", %{"commitment" => "confirmed", "encoding" => "base64"}]}

  """
  @spec get_transaction(String.t(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_transaction(signature, opts \\ []) do
    defaults = [commitment: "confirmed", encoding: "base64"]

    with {:ok, validated_opts} <- validate(opts, @get_transaction_options),
         {:ok, encoded_signature} <- encode_signature(signature) do
      {"getTransaction", [encoded_signature, encode_opts(validated_opts, defaults)]}
    end
  end
end
