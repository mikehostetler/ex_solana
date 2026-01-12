defmodule ExSolana.RPC.Request.SendTransaction do
  @moduledoc """
  Functions for creating a sendTransaction request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

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

  {NimbleOptions.docs(@send_transaction_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#sendtransaction).
  """
  @spec send_transaction(ExSolana.Transaction.t() | binary(), keyword()) ::
          Request.t() | {:error, String.t()}
  def send_transaction(tx, opts \\ [])

  def send_transaction(%ExSolana.Transaction{} = tx, opts) do
    with {:ok, tx_bin} <- ExSolana.Transaction.to_binary(tx),
         {:ok, validated_opts} <- validate(opts, @send_transaction_options) do
      encoded_opts = validated_opts |> fix_tx_opts() |> encode_opts(%{"encoding" => "base64"})
      {"sendTransaction", [Base.encode64(tx_bin), encoded_opts]}
    end
  end

  def send_transaction(tx_string, opts) when is_binary(tx_string) do
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
