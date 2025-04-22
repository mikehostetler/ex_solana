defmodule ExSolana.RPC.Request.GetMinimumBalanceForRentExemption do
  @moduledoc """
  Functions for creating a getMinimumBalanceForRentExemption request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_minimum_balance_for_rent_exemption_options commitment_option()

  @doc """
  Returns minimum balance required to make account rent exempt.

  ## Parameters

  - `data_size`: Size of account data in bytes

  ## Options

  {NimbleOptions.docs(@get_minimum_balance_for_rent_exemption_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getminimumbalanceforrentexemption).
  """
  @spec get_minimum_balance_for_rent_exemption(non_neg_integer(), keyword()) ::
          Request.t() | {:error, String.t()}
  def get_minimum_balance_for_rent_exemption(space, opts \\ []) when is_integer(space) and space >= 0 do
    with {:ok, validated_opts} <-
           validate(opts, @get_minimum_balance_for_rent_exemption_options) do
      {"getMinimumBalanceForRentExemption", [space, encode_opts(validated_opts)]}
    end
  end
end
