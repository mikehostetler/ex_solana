defmodule ExSolana.RPC.Request.GetHealth do
  @moduledoc """
  Functions for creating a getHealth request.

  Returns the current health of the node.

  ## Examples

      iex> ExSolana.RPC.Request.GetHealth.get_health()
      {"getHealth", []}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gethealth).
  """

  @doc """
  Returns the current health of the node.

  This method does not take any parameters.

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request

  ## Examples

      iex> ExSolana.RPC.Request.GetHealth.get_health()
      {"getHealth", []}

  """
  @spec get_health() :: {String.t(), list()}
  def get_health do
    {"getHealth", []}
  end
end
