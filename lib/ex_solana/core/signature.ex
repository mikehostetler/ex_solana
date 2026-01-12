defmodule ExSolana.Signature do
  @moduledoc """
  Solana transaction signature functions and types.

  ## Overview

  Signatures in Solana are 64-byte ed25519 signatures used to verify the
  authenticity and integrity of transactions. They are read-only and
  cannot be modified once created.

  ## Examples

      # Check if a signature is valid
      {:ok, signature} = ExSolana.Signature.check(binary)

      # Decode a base58-encoded signature
      {:ok, signature} = ExSolana.Signature.decode("3HJGsoCQ...")

      # Encode a signature to base58
      {:ok, encoded} = ExSolana.Signature.encode(signature)

  ## Error Handling

  All functions return `{:ok, result}` or `{:error, reason}` tuples:

      case ExSolana.Signature.decode(encoded) do
        {:ok, signature} -> signature
        {:error, %ExSolana.Error.InvalidKeyError{} = error} ->
          handle_error(error)
      end

  """

  alias ExSolana.{Error, Key}

  @typedoc """
  A Solana transaction signature (64 bytes / 512 bits).
  """
  @type t :: <<_::512>>

  @doc """
  The length of a Solana signature in bytes.
  """
  @spec length() :: 64
  def length, do: 64

  @doc """
  Checks if a binary is a valid Solana signature.

  ## Parameters

  - `signature` - Any binary to validate

  ## Returns

  - `{:ok, signature}` - Valid 64-byte signature
  - `{:error, %InvalidKeyError{}}` - Invalid signature length

  ## Examples

      iex> valid_sig = <<1::512>>
      iex> ExSolana.Signature.check(valid_sig)
      {:ok, <<1::512>>}

      iex> invalid_sig = <<1::256>>
      iex> ExSolana.Signature.check(invalid_sig)
      {:error, %ExSolana.Error.InvalidKeyError{}}

  """
  @spec check(binary()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def check(<<signature::binary-size(64)>>) do
    {:ok, signature}
  end

  def check(_) do
    {:error,
     Error.invalid_key_error("Invalid signature length",
       reason: :length,
       details: %{expected: 64, actual: "not 64 bytes"}
     )}
  end

  @doc """
  Decodes a base58-encoded signature and validates it.

  ## Parameters

  - `encoded` - Base58-encoded signature string

  ## Returns

  - `{:ok, signature}` - Valid decoded signature
  - `{:error, %InvalidKeyError{}}` - Invalid encoding or length

  ## Examples

      iex> encoded_sig = "3HJGsoCQacWHNXvJ6WrBBLtFWfekGzjAirgKtDkS2b5d5QzcTH96NKHM65VfLRT8dyUBut56dSbFcAhN832TsVJq"
      iex> {:ok, decoded} = ExSolana.Signature.decode(encoded_sig)
      iex> byte_size(decoded)
      64

      iex> ExSolana.Signature.decode("invalid_base58")
      {:error, %ExSolana.Error.InvalidKeyError{}}

  """
  @spec decode(binary()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def decode(encoded) when is_binary(encoded) do
    case BaseFiftyEight.decode58(encoded) do
      {:ok, decoded} ->
        check(decoded)

      {:error, _} ->
        {:error, Error.invalid_key_error("Invalid base58 encoding", reason: :decode)}
    end
  end

  @doc """
  Decodes a base58-encoded signature, raising an error if invalid.

  ## Parameters

  - `encoded` - Base58-encoded signature string

  ## Returns

  - Decoded 64-byte signature

  ## Raises

  - `ArgumentError` - If input is invalid

  ## Examples

      iex> encoded_sig = "3HJGsoCQacWHNXvJ6WrBBLtFWfekGzjAirgKtDkS2b5d5QzcTH96NKHM65VfLRT8dyUBut56dSbFcAhN832TsVJq"
      iex> decoded = ExSolana.Signature.decode!(encoded_sig)
      iex> byte_size(decoded)
      64

      iex> ExSolana.Signature.decode!("invalid_base58")
      ** (ArgumentError)

  """
  @spec decode!(binary()) :: t()
  def decode!(encoded) when is_binary(encoded) do
    case decode(encoded) do
      {:ok, signature} ->
        signature

      {:error, %Error.InvalidKeyError{message: message}} ->
        raise ArgumentError, message
    end
  end

  @doc """
  Encodes a Solana signature to base58.

  ## Parameters

  - `signature` - 64-byte signature binary

  ## Returns

  - `{:ok, encoded}` - Base58-encoded signature
  - `{:error, %InvalidKeyError{}}` - Invalid signature

  ## Examples

      iex> signature = <<1, 2, 3, 4>> <> <<0::480>>
      iex> {:ok, encoded} = ExSolana.Signature.encode(signature)
      iex> String.length(encoded) > 0
      true

  """
  @spec encode(t()) :: {:ok, String.t()} | {:error, Error.InvalidKeyError.t()}
  def encode(signature) do
    case check(signature) do
      {:ok, valid_signature} ->
        {:ok, BaseFiftyEight.encode58(valid_signature)}

      error ->
        error
    end
  end

  @doc """
  Encodes a Solana signature to base58, raising an error if invalid.

  ## Parameters

  - `signature` - 64-byte signature binary

  ## Returns

  - Base58-encoded signature string

  ## Raises

  - `ArgumentError` - If input is invalid

  ## Examples

      iex> signature = <<1, 2, 3, 4>> <> <<0::480>>
      iex> encoded = ExSolana.Signature.encode!(signature)
      iex> String.length(encoded) > 0
      true

      iex> ExSolana.Signature.encode!(<<1, 2, 3>>)
      ** (ArgumentError)

  """
  @spec encode!(t()) :: String.t()
  def encode!(signature) do
    case encode(signature) do
      {:ok, encoded} ->
        encoded

      {:error, %Error.InvalidKeyError{message: message}} ->
        raise ArgumentError, message
    end
  end

  @doc """
  Creates a signature from a byte array.

  ## Parameters

  - `bytes` - 64-byte binary

  ## Returns

  - `{:ok, signature}` - Valid signature
  - `{:error, %InvalidKeyError{}}` - Invalid length

  ## Examples

      {:ok, sig} = ExSolana.Signature.from_bytes(<<1::512>>)

  """
  @spec from_bytes(binary()) :: {:ok, t()} | {:error, Error.InvalidKeyError.t()}
  def from_bytes(bytes) when is_binary(bytes), do: check(bytes)

  @doc """
  Converts a signature to a byte array (no-op for binary signatures).

  ## Parameters

  - `signature` - 64-byte signature

  ## Returns

  - The signature binary

  """
  @spec to_bytes(t()) :: t()
  def to_bytes(signature), do: signature
end
