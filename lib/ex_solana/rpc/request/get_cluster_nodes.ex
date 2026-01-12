defmodule ExSolana.RPC.Request.GetClusterNodes do
  @moduledoc """
  Functions for creating a getClusterNodes request.
  """

  alias ExSolana.RPC.Request

  @doc """
  Returns information about all the nodes participating in the cluster.

  This method doesn't accept any parameters.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getclusterNodes).
  """
  @spec get_cluster_nodes() :: Request.t()
  def get_cluster_nodes do
    {"getClusterNodes", []}
  end
end
