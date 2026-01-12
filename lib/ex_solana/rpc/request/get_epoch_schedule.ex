defmodule ExSolana.RPC.Request.GetEpochSchedule do
  @moduledoc """
  Functions for creating a getEpochSchedule request.

  Returns epoch schedule information from this cluster's genesis config.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getepochschedule).
  """

  @doc """
  Returns epoch schedule information from this cluster's genesis config.

  This method doesn't accept any parameters.

  ## Examples

      iex> ExSolana.RPC.Request.GetEpochSchedule.get_epoch_schedule()
      {"getEpochSchedule", []}

  """
  @spec get_epoch_schedule() :: {String.t(), list()}
  def get_epoch_schedule do
    {"getEpochSchedule", []}
  end
end
