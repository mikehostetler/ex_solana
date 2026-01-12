defmodule ExSolana.RPC.Request.RequestAirdrop do
  @moduledoc """
  Functions for creating a requestAirdrop request.

  Requests an airdrop of lamports to a Pubkey.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#requestairdrop).
  """

  import ExSolana.RPC.Request.Helpers

  @request_airdrop_options commitment_option() ++ min_context_slot_option()

  @doc """
  Requests an airdrop of lamports to a Pubkey.

  ## Parameters

  - `pubkey`: Base58 encoded Pubkey of account to receive lamports
  - `lamports`: Amount of lamports to airdrop

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")
  - `:min_context_slot` - Minimum slot to fetch context from

  ## Examples

      iex> ExSolana.RPC.Request.RequestAirdrop.request_airdrop("pubkey", 1000)
      {"requestAirdrop", ["pubkey", 1000, %{"commitment" => "confirmed"}]}

  """
  @spec request_airdrop(binary(), non_neg_integer(), keyword()) ::
          {String.t(), list()} | {:error, String.t()}
  def request_airdrop(pubkey, lamports, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @request_airdrop_options),
         {:ok, encoded_pubkey} <- encode_key(pubkey) do
      {"requestAirdrop", [encoded_pubkey, lamports, encode_opts(validated_opts)]}
    end
  end
end
