defmodule ExSolana.RPC.Request.RequestAirdrop do
  @moduledoc """
  Functions for creating a requestAirdrop request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @request_airdrop_options commitment_option() ++
                             min_context_slot_option()

  @doc """
  Requests an airdrop of lamports to a Pubkey.

  ## Parameters

  - `pubkey`: Base58 encoded Pubkey of account to receive lamports
  - `lamports`: Amount of lamports to airdrop

  ## Options

  {NimbleOptions.docs(@request_airdrop_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#requestairdrop).
  """
  @spec request_airdrop(ExSolana.key(), non_neg_integer(), keyword()) ::
          Request.t() | {:error, String.t()}
  def request_airdrop(pubkey, lamports, opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @request_airdrop_options),
         {:ok, encoded_pubkey} <- encode_key(pubkey) do
      {"requestAirdrop", [encoded_pubkey, lamports, encode_opts(validated_opts)]}
    end
  end
end
