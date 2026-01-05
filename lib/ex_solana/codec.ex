defprotocol ExSolana.Codec do
  @moduledoc """
  Protocol for encoding and decoding Solana network structures.
  """

  @doc """
  Decodes the given data into the appropriate struct.
  Returns {:ok, result} on success, {:error, reason} on failure.
  """
  @spec decode(t, keyword()) :: {:ok, struct()} | {:error, String.t()}
  def decode(data, opts \\ [])

  @doc """
  Decodes the given data into the appropriate struct.
  Raises an exception on failure.
  """
  @spec decode!(t, keyword()) :: struct()
  def decode!(data, opts \\ [])

  @doc """
  Encodes the given struct into its raw Solana network format.
  Returns {:ok, result} on success, {:error, reason} on failure.
  """
  @spec encode(struct(), keyword()) :: {:ok, t} | {:error, String.t()}
  def encode(data, opts \\ [])

  @doc """
  Encodes the given struct into its raw Solana network format.
  Raises an exception on failure.
  """
  @spec encode!(struct(), keyword()) :: t
  def encode!(data, opts \\ [])
end
