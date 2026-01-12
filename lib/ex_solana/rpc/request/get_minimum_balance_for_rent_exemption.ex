defmodule ExSolana.RPC.Request.GetMinimumBalanceForRentExemption do
  @moduledoc """
  Functions for creating a getMinimumBalanceForRentExemption request.

  Returns minimum balance required to make account rent exempt.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getminimumbalanceforrentexemption).
  """

  import ExSolana.RPC.Request.Helpers

  @get_minimum_balance_for_rent_exemption_options commitment_option()

  @doc """
  Returns minimum balance required to make account rent exempt.

  ## Parameters

  - `data_size`: Size of account data in bytes

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.GetMinimumBalanceForRentExemption.get_minimum_balance_for_rent_exemption(100)
      {"getMinimumBalanceForRentExemption", [100, %{"commitment" => "confirmed"}]}

  """
  @spec get_minimum_balance_for_rent_exemption(non_neg_integer(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def get_minimum_balance_for_rent_exemption(space, opts \\ [])
      when is_integer(space) and space >= 0 do
    with {:ok, validated_opts} <-
           validate(opts, @get_minimum_balance_for_rent_exemption_options) do
      {"getMinimumBalanceForRentExemption", [space, encode_opts(validated_opts)]}
    end
  end
end
