defmodule ExSolana.RPC.Request.GetSlot do
  @moduledoc """
  Functions for creating a getSlot request.

  Returns the slot that has reached the given or default commitment level.

  ## Examples

      iex> ExSolana.RPC.Request.GetSlot.get_slot(commitment: "confirmed")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getslot).
  """

  import ExSolana.RPC.Request.Helpers

  @get_slot_options commitment_option() ++ min_context_slot_option()

  @doc """
  Returns the slot that has reached the given or default commitment level.

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
    * `:min_context_slot` - Minimum slot to fetch context from

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetSlot.get_slot()
      {"getSlot", [%{"commitment" => "confirmed"}]}

      iex> ExSolana.RPC.Request.GetSlot.get_slot(commitment: "finalized")
      {"getSlot", [%{"commitment" => "finalized"}]}

  """
  @spec get_slot(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_slot(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_slot_options) do
      {"getSlot", [encode_opts(validated_opts)]}
    end
  end
end
