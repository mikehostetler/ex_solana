defmodule ExSolana.RPC.Request.SendTransaction do
  @moduledoc """
  Functions for creating a sendTransaction request.

  Creates a sendTransaction request.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#sendtransaction).
  """

  import ExSolana.RPC.Request.Helpers

  @send_transaction_options commitment_option() ++
                              [
                                max_retries: [
                                  type: :non_neg_integer,
                                  doc:
                                    "Maximum number of times for the RPC node to retry sending the transaction to the leader."
                                ],
                                skip_preflight: [
                                  type: :boolean,
                                  default: false,
                                  doc: "If true, skip the preflight transaction checks."
                                ]
                              ]

  @doc """
  Creates a sendTransaction request.

  ## Parameters

  - `encoded_transaction`: A fully-signed Transaction, as encoded string

  ## Options

  - `:commitment` - Commitment level (mapped to preflightCommitment)
  - `:max_retries` - Maximum number of times for the RPC node to retry sending
  - `:skip_preflight` - If true, skip the preflight transaction checks (default: false)

  ## Examples

      iex> ExSolana.RPC.Request.SendTransaction.send_transaction("base64_encoded_tx")
      {"sendTransaction", ["base64_encoded_tx", %{"encoding" => "base64", "preflightCommitment" => "confirmed"}]}

  """
  @spec send_transaction(binary(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def send_transaction(tx_string, opts \\ []) when is_binary(tx_string) do
    with {:ok, validated_opts} <- validate(opts, @send_transaction_options) do
      encoded_opts = validated_opts |> fix_tx_opts() |> encode_opts(%{"encoding" => "base64"})
      {"sendTransaction", [tx_string, encoded_opts]}
    end
  end

  defp fix_tx_opts(opts) do
    Enum.map(opts, fn
      {:commitment, commitment} -> {:preflight_commitment, commitment}
      other -> other
    end)
  end
end
