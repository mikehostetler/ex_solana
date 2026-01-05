defmodule ExSolana.RPC.Request.GetEpochSchedule do
  @moduledoc """
  Functions for creating a getEpochSchedule request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns epoch schedule information from this cluster's genesis config.

  This method doesn't accept any parameters.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getepochschedule).
  """
  @spec get_epoch_schedule() :: Request.t()
  def get_epoch_schedule do
    {"getEpochSchedule", []}
  end
end
