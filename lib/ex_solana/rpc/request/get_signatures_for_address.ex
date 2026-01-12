defmodule ExSolana.RPC.Request.GetSignaturesForAddress do
  @moduledoc """
  Functions for creating a getSignaturesForAddress request.

  Returns confirmed signatures for transactions involving an address.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getsignaturesforaddress).
  """

  import ExSolana.RPC.Request.Helpers

  @get_signatures_for_address_options commitment_option() ++
                                        [
                                          before: [
                                            type: :string,
                                            doc:
                                              "Start searching backwards from this transaction signature."
                                          ],
                                          until: [
                                            type: :string,
                                            doc:
                                              "Search until this transaction signature, if found before limit reached."
                                          ],
                                          limit: [
                                            type: :integer,
                                            doc:
                                              "Maximum transaction signatures to return (between 1 and 1000, default: 1000)."
                                          ]
                                        ]

  @type address :: String.t()

  @doc """
  Returns confirmed signatures for transactions involving an address.

  ## Parameters

  - `address`: Base58 encoded string of the account address to query.

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:before` - Start searching backwards from this transaction signature
  - `:until` - Search until this transaction signature
  - `:limit` - Maximum transaction signatures to return (1-1000, default: 1000)

  ## Examples

      iex> ExSolana.RPC.Request.GetSignaturesForAddress.get_signatures_for_address("address")
      {"getSignaturesForAddress", ["address", %{"commitment" => "confirmed"}]}

  """
  @spec get_signatures_for_address(address(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def get_signatures_for_address(address, opts \\ []) when is_binary(address) do
    with {:ok, validated_opts} <- validate(opts, @get_signatures_for_address_options) do
      {"getSignaturesForAddress", [address, encode_opts(validated_opts)]}
    end
  end
end
