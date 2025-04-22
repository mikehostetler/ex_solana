defmodule ExSolana.RPC.Request.SimulateTransaction do
  @moduledoc """
  Functions for creating a simulateTransaction request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

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

  - `transaction`: A fully-signed Transaction, as encoded string or ExSolana.Transaction struct

  ## Options

  {NimbleOptions.docs(@simulate_transaction_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#simulatetransaction).
  """
  @spec simulate_transaction(ExSolana.Transaction.t() | binary(), keyword()) ::
          Request.t() | {:error, String.t()}
  def simulate_transaction(tx, opts \\ [])

  def simulate_transaction(%ExSolana.Transaction{} = tx, opts) do
    with {:ok, tx_bin} <- ExSolana.Transaction.to_binary(tx),
         {:ok, validated_opts} <- validate(opts, @simulate_transaction_options) do
      {"simulateTransaction", [Base.encode64(tx_bin), encode_opts(validated_opts)]}
    end
  end

  def simulate_transaction(tx_string, opts) when is_binary(tx_string) do
    with {:ok, validated_opts} <- validate(opts, @simulate_transaction_options) do
      {"simulateTransaction", [tx_string, encode_opts(validated_opts)]}
    end
  end
end
