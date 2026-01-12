defmodule ExSolana.RPC.Request.GetSlotLeader do
  @moduledoc """
  Functions for creating a getSlotLeader request.

  Returns the current slot leader.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getslotleader).
  """

  import ExSolana.RPC.Request.Helpers

  @get_slot_leader_options commitment_option() ++ min_context_slot_option()

  @doc """
  Returns the current slot leader.

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:min_context_slot` - Minimum slot to fetch context from

  ## Examples

      iex> ExSolana.RPC.Request.GetSlotLeader.get_slot_leader()
      {"getSlotLeader", [%{"commitment" => "confirmed"}]}

  """
  @spec get_slot_leader(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_slot_leader(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_slot_leader_options) do
      {"getSlotLeader", [encode_opts(validated_opts)]}
    end
  end
end
