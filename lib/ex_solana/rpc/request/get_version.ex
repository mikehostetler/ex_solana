defmodule ExSolana.RPC.Request.GetVersion do
  @moduledoc """
  Functions for creating a getVersion request.

  Returns the current version of the Solana software running on the node.

  ## Examples

      iex> ExSolana.RPC.Request.GetVersion.get_version()

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getversion).
  """

  @doc """
  Returns the current version of the Solana software running on the node.

  This method does not take any parameters.

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request

  ## Examples

      iex> ExSolana.RPC.Request.GetVersion.get_version()
      {"getVersion", []}

  """
  @spec get_version() :: {String.t(), list()}
  def get_version do
    {"getVersion", []}
  end
end
