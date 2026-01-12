defmodule ExSolana.RPC.Request.GetClusterNodes do
  @moduledoc """
  Functions for creating a getClusterNodes request.

  Returns information about all the nodes participating in the cluster.

  ## Examples

      iex> ExSolana.RPC.Request.GetClusterNodes.get_cluster_nodes()

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getclusternodes).
  """

  @doc """
  Returns information about all the nodes participating in the cluster.

  This method does not take any parameters.

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request

  ## Examples

      iex> ExSolana.RPC.Request.GetClusterNodes.get_cluster_nodes()
      {"getClusterNodes", []}

  """
  @spec get_cluster_nodes() :: {String.t(), list()}
  def get_cluster_nodes do
    {"getClusterNodes", []}
  end
end
