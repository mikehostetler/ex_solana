defmodule ExSolana.Decoder.FieldTypes do
  @moduledoc """
  Provides field type decoders for Solana account data.
  """

  @doc "Decodes a 64-bit unsigned integer"
  @spec u64(binary()) :: {non_neg_integer(), binary()}
  def u64(<<value::little-64, rest::binary>>), do: {value, rest}

  @doc "Decodes a 128-bit unsigned integer"
  @spec u128(binary()) :: {non_neg_integer(), binary()}
  def u128(<<value::little-128, rest::binary>>), do: {value, rest}

  @doc "Decodes a public key"
  @spec public_key(binary()) :: {String.t(), binary()}
  def public_key(<<key::binary-size(32), rest::binary>>) do
    {B58.encode58(key), rest}
  end

  @doc "Decodes a binary blob of specified size"
  @spec blob(binary(), non_neg_integer()) :: {binary(), binary()}
  def blob(data, size) do
    <<value::binary-size(size), rest::binary>> = data
    {value, rest}
  end

  @doc "Decodes a sequence of items using the provided decoder function"
  @spec seq(binary(), (binary() -> {any(), binary()}), non_neg_integer()) :: {list(), binary()}
  def seq(data, decode_fn, count) do
    1..count
    |> Enum.reduce_while({[], data}, fn _, {acc, remaining} ->
      case decode_fn.(remaining) do
        {value, new_remaining} -> {:cont, {[value | acc], new_remaining}}
        _ -> {:halt, {acc, remaining}}
      end
    end)
    |> then(fn {values, rest} -> {Enum.reverse(values), rest} end)
  end
end
