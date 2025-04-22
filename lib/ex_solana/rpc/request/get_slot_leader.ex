defmodule ExSolana.RPC.Request.GetSlotLeader do
  @moduledoc """
  Functions for creating a getSlotLeader request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_slot_leader_options commitment_option() ++
                             min_context_slot_option()

  @doc """
  Returns the slot that has reached the given or default commitment level.

  ## Options

  {NimbleOptions.docs(@get_slot_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getslot).
  """
  @spec get_slot_leader(keyword()) :: Request.t() | {:error, String.t()}
  def get_slot_leader(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_slot_leader_options) do
      {"getSlotLeader", [encode_opts(validated_opts)]}
    end
  end
end
