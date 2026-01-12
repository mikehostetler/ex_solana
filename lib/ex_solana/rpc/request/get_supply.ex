defmodule ExSolana.RPC.Request.GetSupply do
  @moduledoc """
  Functions for creating a getSupply request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

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

  #{NimbleOptions.docs(@get_supply_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getsupply).
  """
  @spec get_supply(keyword()) :: Request.t() | {:error, String.t()}
  def get_supply(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_supply_options) do
      {"getSupply", [encode_opts(validated_opts)]}
    end
  end
end
