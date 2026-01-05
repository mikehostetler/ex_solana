defmodule ExSolana.RPC.Request.GetEpochInfo do
  @moduledoc """
  Functions for creating a getEpochInfo request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_epoch_info_options commitment_option()

  @doc """
  Returns information about the current epoch.

  ## Options

  {NimbleOptions.docs(@get_epoch_info_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getepochinfo).
  """
  @spec get_epoch_info(keyword()) :: Request.t() | {:error, String.t()}
  def get_epoch_info(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_epoch_info_options) do
      {"getEpochInfo", [encode_opts(validated_opts)]}
    end
  end
end
