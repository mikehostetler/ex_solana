defmodule ExSolana.Signature do
  @moduledoc """
  Functions and types related to Solana transaction signatures.

  Signatures in Solana are 64-byte arrays that are used to verify the authenticity
  and integrity of transactions. They are always read-only and cannot be modified
  once created.
  """

  @typedoc "A Solana transaction signature"
  @type t :: <<_::512>>

  @doc """
  Checks to see if a `t:ExSolana.Signature.t/0` is valid.

  Returns `{:ok, signature}` if the signature is valid, or an error tuple if it's invalid.

  ## Examples

      iex> valid_sig = <<1::512>>
      iex> ExSolana.Signature.check(valid_sig)
      {:ok, <<1::512>>}

      iex> invalid_sig = <<1::256>>
      iex> ExSolana.Signature.check(invalid_sig)
      {:error, :invalid_signature}

  """
  @spec check(binary()) :: {:ok, t()} | {:error, binary()}
  def check(signature)
  def check(<<signature::binary-size(64)>>), do: {:ok, signature}
  def check(_), do: {:error, :invalid_signature}

  @doc """
  Decodes a base58-encoded signature and validates it.

  Returns `{:ok, signature}` if the signature is valid, or an error tuple if it's invalid
  or cannot be decoded.

  ## Examples

      iex> encoded_sig = "3HJGsoCQacWHNXvJ6WrBBLtFWfekGzjAirgKtDkS2b5d5QzcTH96NKHM65VfLRT8dyUBut56dSbFcAhN832TsVJq"
      iex> {:ok, decoded} = ExSolana.Signature.decode(encoded_sig)
      iex> byte_size(decoded)
      64

      iex> ExSolana.Signature.decode("invalid_base58")
      {:error, :invalid_signature}

  """
  @spec decode(binary()) :: {:ok, t()} | {:error, :invalid_signature}
  def decode(encoded) when is_binary(encoded) do
    case B58.decode58(encoded) do
      {:ok, decoded} -> check(decoded)
      {:error, _} -> {:error, :invalid_signature}
    end
  end

  def decode(_), do: {:error, :invalid_signature}

  @doc """
  Decodes a base58-encoded signature and validates it, raising an error if invalid.

  Returns the decoded signature if valid, or raises an `ArgumentError` if invalid
  or cannot be decoded.

  ## Examples

      iex> encoded_sig = "3HJGsoCQacWHNXvJ6WrBBLtFWfekGzjAirgKtDkS2b5d5QzcTH96NKHM65VfLRT8dyUBut56dSbFcAhN832TsVJq"
      iex> decoded = ExSolana.Signature.decode!(encoded_sig)
      iex> byte_size(decoded)
      64

      iex> ExSolana.Signature.decode!("invalid_base58")
      ** (ArgumentError) invalid signature input: invalid_base58

  """
  @spec decode!(binary()) :: t()
  def decode!(encoded) when is_binary(encoded) do
    case decode(encoded) do
      {:ok, signature} -> signature
      {:error, _} -> raise ArgumentError, "invalid signature input: #{encoded}"
    end
  end

  def decode!(_), do: raise(ArgumentError, "invalid signature input")

  @doc """
  Encodes a Solana signature to its base58 representation.

  Returns `{:ok, encoded_signature}` if the encoding is successful, or an error tuple if the
  input is not a valid signature.

  ## Examples

      iex> signature = <<1, 2, 3, 4>> <> <<0::480>>  # 64-byte binary
      iex> {:ok, encoded} = ExSolana.Signature.encode(signature)
      iex> String.length(encoded) > 0
      true

  """
  @spec encode(binary()) :: {:ok, binary()} | {:error, :invalid_signature}
  def encode(signature) do
    case check(signature) do
      {:ok, valid_signature} -> {:ok, B58.encode58(valid_signature)}
      error -> error
    end
  end

  @doc """
  Encodes a Solana signature to its base58 representation, raising an error if invalid.

  Returns the base58-encoded signature if valid, or raises an `ArgumentError` if the
  input is not a valid signature.

  ## Examples

      iex> signature = <<1, 2, 3, 4>> <> <<0::480>>  # 64-byte binary
      iex> encoded = ExSolana.Signature.encode!(signature)
      iex> String.length(encoded) > 0
      true

      iex> ExSolana.Signature.encode!(<<1, 2, 3>>)
      ** (ArgumentError) invalid signature

  """
  @spec encode!(binary()) :: binary()
  def encode!(signature) do
    case encode(signature) do
      {:ok, encoded} -> encoded
      {:error, _} -> raise ArgumentError, "invalid signature"
    end
  end
end
