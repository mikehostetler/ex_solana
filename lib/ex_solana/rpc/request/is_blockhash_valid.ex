defmodule ExSolana.RPC.Request.IsBlockhashValid do
  @moduledoc """
  Functions for creating an isBlockhashValid request.

  Creates a request to check if a blockhash is still valid.

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#isblockhashvalid).
  """

  import ExSolana.RPC.Request.Helpers

  @is_blockhash_valid_options commitment_option()

  @doc """
  Creates a request to check if a blockhash is still valid.

  ## Parameters

  - `blockhash` - The blockhash to validate, as a base-58 encoded string.

  ## Options

  - `:commitment` - Commitment level ("processed", "confirmed", "finalized", default: "confirmed")

  ## Examples

      iex> ExSolana.RPC.Request.IsBlockhashValid.is_blockhash_valid("blockhash")
      {"isBlockhashValid", ["blockhash", %{"commitment" => "confirmed"}]}

  """
  @spec is_blockhash_valid(String.t(), keyword()) :: {String.t(), list()} | {:error, String.t()}
  def is_blockhash_valid(blockhash, opts \\ []) when is_binary(blockhash) do
    with {:ok, validated_opts} <- validate(opts, @is_blockhash_valid_options) do
      {"isBlockhashValid", [blockhash, encode_opts(validated_opts)]}
    end
  end
end
