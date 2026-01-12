defmodule ExSolana.RPC.Request.GetEpochInfo do
  @moduledoc """
  Functions for creating a getEpochInfo request.

  Returns information about the current epoch.

  ## Examples

      iex> ExSolana.RPC.Request.GetEpochInfo.get_epoch_info(commitment: "confirmed")

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getepochinfo).
  """

  import ExSolana.RPC.Request.Helpers

  @get_epoch_info_options commitment_option()

  @doc """
  Returns information about the current epoch.

  ## Options

    * `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Returns

    * `{String.t(), list()}` - A tuple of method name and params for the request
    * `{:error, String.t()}` - Error if validation fails

  ## Examples

      iex> ExSolana.RPC.Request.GetEpochInfo.get_epoch_info()
      {"getEpochInfo", [%{"commitment" => "confirmed"}]}

      iex> ExSolana.RPC.Request.GetEpochInfo.get_epoch_info(commitment: "finalized")
      {"getEpochInfo", [%{"commitment" => "finalized"}]}

  """
  @spec get_epoch_info(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_epoch_info(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_epoch_info_options) do
      {"getEpochInfo", [encode_opts(validated_opts)]}
    end
  end
end
