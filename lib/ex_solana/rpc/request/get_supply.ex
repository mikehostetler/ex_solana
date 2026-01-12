defmodule ExSolana.RPC.Request.GetSupply do
  @moduledoc """
  Functions for creating a getSupply request.

  Returns information about the current supply.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getsupply).
  """

  import ExSolana.RPC.Request.Helpers

  @get_supply_options commitment_option() ++
                        min_context_slot_option() ++
                        [
                          exclude_non_circulating_accounts_list: [
                            type: :boolean,
                            doc: "Exclude non circulating accounts list from response",
                            default: true
                          ]
                        ]

  @doc """
  Returns information about the current supply.

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:min_context_slot` - Minimum slot to fetch context from
  - `:exclude_non_circulating_accounts_list` - Exclude non circulating accounts list (default: true)

  ## Examples

      iex> ExSolana.RPC.Request.GetSupply.get_supply()
      {"getSupply", [%{"commitment" => "confirmed"}]}

  """
  @spec get_supply(keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_supply(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_supply_options) do
      {"getSupply", [encode_opts(validated_opts)]}
    end
  end
end
