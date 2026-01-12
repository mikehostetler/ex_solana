defmodule ExSolana.RPC.Request.IsBlockhashValid do
  @moduledoc """
  Functions for creating an isBlockhashValid request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @is_blockhash_valid_options commitment_option()

  @doc """
  Creates a request to check if a blockhash is still valid.

  ## Parameters

  - `blockhash` - The blockhash to validate, as a base-58 encoded string.

  ## Options

  {NimbleOptions.docs(@is_blockhash_valid_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#isblockhashvalid).
  """
  @spec is_blockhash_valid(String.t(), keyword()) :: Request.t() | {:error, String.t()}
  def is_blockhash_valid(blockhash, opts \\ []) when is_binary(blockhash) do
    with {:ok, validated_opts} <- validate(opts, @is_blockhash_valid_options) do
      {"isBlockhashValid", [blockhash, encode_opts(validated_opts)]}
    end
  end
end
