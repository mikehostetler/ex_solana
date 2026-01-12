defmodule ExSolana.RPC.Request.GetVersion do
  @moduledoc """
  Functions for creating a getVersion request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns the current Solana version running on the node.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getversion).
  """
  @spec get_version() :: Request.t()
  def get_version do
    {"getVersion", []}
  end
end
