defmodule ExSolana.RPC.Request.SimulateTransaction do
  @moduledoc """
  Functions for creating a simulateTransaction request.

  Creates a simulateTransaction request.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#simulatetransaction).
  """

  import ExSolana.RPC.Request.Helpers

  @simulate_transaction_options commitment_option() ++
                                  [
                                    sigVerify: [
                                      type: :boolean,
                                      doc: "If true, signatures will be verified"
                                    ],
                                    replaceRecentBlockhash: [
                                      type: :boolean,
                                      doc:
                                        "If true, the transaction recent blockhash will be replaced with the most recent blockhash"
                                    ]
                                  ] ++
                                  min_context_slot_option() ++
                                  encoding_option()

  @doc """
  Creates a simulateTransaction request.

  ## Parameters

  - `transaction`: A fully-signed Transaction, as encoded string

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:encoding` - Encoding format ("base64", "base58", "json", "jsonParsed", default: "base64")
  - `:sigVerify` - If true, signatures will be verified
  - `:replaceRecentBlockhash` - If true, replace recent blockhash
  - `:min_context_slot` - Minimum slot to fetch context from

  ## Examples

      iex> ExSolana.RPC.Request.SimulateTransaction.simulate_transaction("base64_encoded_tx")
      {"simulateTransaction", ["base64_encoded_tx", %{"commitment" => "confirmed", "encoding" => "base64"}]}

  """
  @spec simulate_transaction(binary(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def simulate_transaction(tx_string, opts \\ []) when is_binary(tx_string) do
    with {:ok, validated_opts} <- validate(opts, @simulate_transaction_options) do
      {"simulateTransaction", [tx_string, encode_opts(validated_opts)]}
    end
  end
end
