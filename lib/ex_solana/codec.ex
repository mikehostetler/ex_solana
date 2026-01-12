defprotocol ExSolana.Codec do
  @moduledoc """
  Protocol for encoding and decoding Solana network structures.

  This protocol defines a standard interface for converting between
  Elixir structs and the binary format used by the Solana network.

  ## Implementing the Protocol

  To implement this protocol for your custom types:

      defimpl ExSolana.Codec, for: MyCustomType do
        def encode(data, opts \\ []) do
          # Implementation
        end

        def decode(data, opts \\ []) do
          # Implementation
        end
      end

  ## Examples

      iex> ExSolana.Codec.encode(transaction)
      {:ok, <<binary::bits>>}

      iex> ExSolana.Codec.decode(<<binary::bits>>)
      {:ok, %Transaction{}}

  """

  @doc """
  Decodes the given data into the appropriate struct.

  ## Parameters

    * `data` - Binary data to decode
    * `opts` - Optional decoding parameters

  ## Returns

    * `{:ok, struct()}` - Successfully decoded struct
    * `{:error, String.t()}` - Error reason if decoding fails

  """
  @spec decode(t, keyword()) :: {:ok, struct()} | {:error, String.t()}
  def decode(data, opts \\ [])

  @doc """
  Decodes the given data into the appropriate struct.

  Raises an exception on failure.

  ## Parameters

    * `data` - Binary data to decode
    * `opts` - Optional decoding parameters

  ## Returns

    * `struct()` - Successfully decoded struct

  ## Raises

    * `ArgumentError` - If decoding fails

  """
  @spec decode!(t, keyword()) :: struct()
  def decode!(data, opts \\ [])

  @doc """
  Encodes the given struct into its raw Solana network format.

  ## Parameters

    * `data` - Struct to encode
    * `opts` - Optional encoding parameters

  ## Returns

    * `{:ok, binary()}` - Successfully encoded binary
    * `{:error, String.t()}` - Error reason if encoding fails

  """
  @spec encode(struct(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def encode(data, opts \\ [])

  @doc """
  Encodes the given struct into its raw Solana network format.

  Raises an exception on failure.

  ## Parameters

    * `data` - Struct to encode
    * `opts` - Optional encoding parameters

  ## Returns

    * `binary()` - Successfully encoded binary

  ## Raises

    * `ArgumentError` - If encoding fails

  """
  @spec encode!(struct(), keyword()) :: binary()
  def encode!(data, opts \\ [])
end
