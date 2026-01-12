defmodule ExSolana.RPC.Request.GetTokenSupply do
  @moduledoc """
  Functions for creating a getTokenSupply request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_token_supply_options commitment_option()

  @doc """
  Returns the total supply of an SPL Token type.

  ## Parameters

  - `mint`: Pubkey of the token Mint to query, as a base-58 encoded string

  ## Options

  {NimbleOptions.docs(@get_token_supply_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#gettokensupply).
  """
  @spec get_token_supply(ExSolana.key(), keyword()) :: Request.t() | {:error, String.t()}
  def get_token_supply(mint, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_token_supply_options),
         {:ok, encoded_mint} <- encode_key(mint) do
      {"getTokenSupply", [encoded_mint, encode_opts(validated_opts)]}
    end
  end
end
