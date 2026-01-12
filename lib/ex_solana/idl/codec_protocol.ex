# defprotocol ExSolana.IDL.Codec do
#   @moduledoc """
#   Protocol for encoding and decoding Solana on-chain data structures.

#   This protocol defines methods for serializing Elixir structs to binary format
#   for on-chain storage and deserializing binary data back into Elixir structs.
#   """

#   @doc """
#   Encodes a struct into binary format for Solana on-chain storage.

#   ## Parameters

#     * `value` - The struct to be encoded.

#   ## Returns

#     * `binary` - The encoded binary data.
#   """
#   @spec encode(t) :: binary
#   def encode(value)

#   @doc """
#   Decodes binary data from Solana on-chain storage into an Elixir struct.

#   ## Parameters

#     * `data` - The binary data to be decoded.

#   ## Returns

#     * `{:ok, t}` - A tuple containing `:ok` and the decoded struct on success.
#     * `{:error, term}` - A tuple containing `:error` and an error description on failure.
#   """
#   @spec decode(binary) :: {:ok, t} | {:error, term}
#   def decode(data)
# end
