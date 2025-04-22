defmodule ExSolana.RPC.Request.GetHealth do
  @moduledoc """
  Functions for creating a getHealth request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns the current health of the node.

  This method does not take any parameters.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gethealth).
  """
  @spec get_health() :: Request.t()
  def get_health do
    {"getHealth", []}
  end
end
