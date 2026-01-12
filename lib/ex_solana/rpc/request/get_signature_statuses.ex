defmodule ExSolana.RPC.Request.GetSignatureStatuses do
  @moduledoc """
  Functions for creating a getSignatureStatuses request.

  Returns the statuses of a list of signatures.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getsignaturestatuses).
  """

  import ExSolana.RPC.Request.Helpers

  @get_signature_statuses_options [
    search_transaction_history: [
      type: :boolean,
      default: true,
      doc:
        "If true, a Solana node will search its ledger cache for any signatures not found in the recent status cache"
    ]
  ]

  @doc """
  Returns the statuses of a list of signatures.

  ## Parameters

  - `signatures`: An array of transaction signatures to confirm, as base-58 encoded strings (up to a maximum of 256)

  ## Options

  - `:search_transaction_history` - Search ledger cache for signatures (default: true)

  ## Examples

      iex> ExSolana.RPC.Request.GetSignatureStatuses.get_signature_statuses(["signature1", "signature2"])
      {"getSignatureStatuses", [["signature1", "signature2"], %{"searchTransactionHistory" => true}]}

  """
  @spec get_signature_statuses([binary()], keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_signature_statuses(signatures, opts \\ []) when is_list(signatures) do
    with {:ok, validated_opts} <- validate(opts, @get_signature_statuses_options),
         {:ok, encoded_signatures} <- encode_signatures(signatures) do
      {"getSignatureStatuses", [encoded_signatures, encode_opts(validated_opts)]}
    end
  end

  defp encode_signatures(signatures) do
    Enum.reduce_while(signatures, {:ok, []}, fn sig, {:ok, acc} ->
      case encode_signature(sig) do
        {:ok, encoded} -> {:cont, {:ok, [encoded | acc]}}
        {:error, reason} -> {:halt, {:error, "Failed to encode signature: #{reason}"}}
      end
    end)
  end
end
