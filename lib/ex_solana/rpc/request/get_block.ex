defmodule ExSolana.RPC.Request.GetBlock do
  @moduledoc """
  Functions for creating a getBlock request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_block_options commitment_option() ++
                       encoding_option() ++
                       [
                         transaction_details: [
                           type: {:in, ["full", "accounts", "signatures", "none"]},
                           doc: "Level of transaction detail to return."
                         ],
                         max_supported_transaction_version: [
                           type: :non_neg_integer,
                           doc: "The max transaction version to return in responses."
                         ],
                         rewards: [
                           type: :boolean,
                           doc: "Whether to populate the rewards array."
                         ]
                       ]

  @doc """
  Returns identity and transaction information about a confirmed block in the ledger.

  ## Options

  #{NimbleOptions.docs(@get_block_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getblock).
  """
  @spec get_block(non_neg_integer(), keyword()) ::
          Request.t() | {:error, String.t()} | {:error, NimbleOptions.ValidationError.t()}
  def get_block(slot, opts \\ [])

  def get_block(slot, opts) when is_integer(slot) and slot >= 0 do
    case validate(opts, @get_block_options) do
      {:ok, validated_opts} ->
        {"getBlock", [slot, encode_opts(validated_opts)]}

      {:error, error} ->
        {:error, error}
    end
  end

  def get_block(slot, _opts) when not is_integer(slot) or slot < 0 do
    {:error, "Invalid slot: must be a non-negative integer"}
  end
end
