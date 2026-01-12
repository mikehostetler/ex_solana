defmodule ExSolana.CompactArray do
  @moduledoc """
  Compact array encoding/decoding for Solana transactions.

  Solana uses compact-u16 encoding for arrays in transactions.
  See: https://docs.solana.com/developing/programming-model/transactions#compact-array-format
  """

  import Bitwise

  alias ExSolana.Util.Helpers

  @doc """
  Converts an array to compact array iolist format.
  """
  @spec to_iolist(arr :: iolist | nil) :: iolist
  def to_iolist(nil), do: []

  def to_iolist(arr) when is_list(arr) do
    [encode_length(length(arr)) | arr]
  end

  def to_iolist(bin) when is_binary(bin) do
    [encode_length(byte_size(bin)) | [bin]]
  end

  @doc """
  Encodes a length value in compact array format.
  """
  @spec encode_length(length :: non_neg_integer) :: list
  def encode_length(length) when bsr(length, 7) == 0, do: [encode_bits(length)]

  def encode_length(length) do
    [bor(encode_bits(length), 0x80) | encode_length(bsr(length, 7))]
  end

  defp encode_bits(bits), do: band(bits, 0x7F)

  @doc """
  Decodes a compact array from a binary and splits it.
  Returns {rest_of_binary, length} or :error.
  """
  @spec decode_and_split(encoded :: binary) :: {binary, non_neg_integer} | :error
  def decode_and_split(""), do: :error

  def decode_and_split(encoded) do
    count = decode_length(encoded)
    count_size = compact_length_bytes(count)

    case encoded do
      <<length::count_size*8, rest::binary>> -> {rest, length}
      _ -> :error
    end
  end

  @doc """
  Decodes a compact array with fixed-size items.
  Returns {[items], rest_of_binary, count} or :error.
  """
  @spec decode_and_split(encoded :: binary, item_size :: non_neg_integer) ::
          {[binary], binary, non_neg_integer} | :error
  def decode_and_split("", _), do: :error

  def decode_and_split(encoded, item_size) do
    count = decode_length(encoded)
    count_size = compact_length_bytes(count)
    data_size = count * item_size

    case encoded do
      <<length::count_size*8, data::binary-size(data_size), rest::binary>> ->
        {Helpers.chunk(data, item_size), rest, length}

      _ ->
        :error
    end
  end

  @doc """
  Decodes the length from a compact array encoded value.
  """
  def decode_length(bytes), do: decode_length(bytes, 0)

  def decode_length(<<elem, _::binary>>, size) when band(elem, 0x80) == 0 do
    decode_bits(elem, size)
  end

  def decode_length([elem | _], size) when band(elem, 0x80) == 0 do
    decode_bits(elem, size)
  end

  def decode_length(<<elem, rest::binary>>, size) do
    bor(decode_bits(elem, size), decode_length(rest, size + 1))
  end

  def decode_length([elem | rest], size) do
    bor(decode_bits(elem, size), decode_length(rest, size + 1))
  end

  defp decode_bits(bits, size), do: bits |> band(0x7F) |> bsl(7 * size)

  defp compact_length_bytes(length) when length < 0x7F, do: 1
  defp compact_length_bytes(length) when length < 0x3FFF, do: 2
  defp compact_length_bytes(_), do: 3
end
