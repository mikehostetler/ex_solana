defmodule ExSolana.BinaryDecoder do
  @moduledoc """
  A general-purpose module for decoding binary data into a map based on a provided pattern.
  """

  use ExSolana.Util.DebugTools, debug_enabled: false

  @type decoder_result :: {term(), binary()}
  @type decoder_fn :: (binary() -> decoder_result())
  @type pattern :: %{required(atom()) => String.t() | [String.t()] | map()}

  @doc """
  Decodes binary data based on the given pattern.

  ## Parameters
    - data: The binary data to decode
    - pattern: A map describing the structure of the data

  ## Returns
    `{decoded_map, rest}` where:
    - `decoded_map` is a map of decoded values
    - `rest` is the remaining binary data

  ## Example
    pattern = %{
      field1: "u8",
      field2: "u16",
      nested: %{
        field3: "u32",
        field4: "bool"
      },
      array_field: ["u8", 3]
    }

    ExSolana.BinaryDecoder.decode(<<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>, pattern)
  """
  @spec decode(binary(), pattern()) :: {map(), binary()}
  def decode(data, pattern) when is_binary(data) and is_map(pattern) do
    debug("Starting decode", data: data, pattern: pattern)

    result =
      Enum.reduce(pattern, {%{}, data}, fn {key, type}, {acc, rest} ->
        debug("Decoding field", key: key, type: type)
        {value, new_rest} = decode_field(rest, type)
        debug("Decoded field", key: key, value: value)
        {Map.put(acc, key, value), new_rest}
      end)

    debug("Finished decode", result: result)
    result
  end

  def decode(data, pattern) when is_binary(data) and is_list(pattern) do
    debug("Starting decode with ordered pattern", data: data, pattern: pattern)

    result =
      Enum.reduce(pattern, {%{}, data}, fn {key, type}, {acc, rest} ->
        debug("Decoding field", key: key, type: type)
        {value, new_rest} = decode_field(rest, type)
        debug("Decoded field", key: key, value: value)
        {Map.put(acc, key, value), new_rest}
      end)

    debug("Finished decode", result: result)
    result
  end

  @doc """
  Decodes a single field based on its type.

  ## Parameters
    - data: The binary data to decode
    - type: The type of the field (e.g., "u8", "bool", ["u8", 3])

  ## Returns
    `{value, rest}` where:
    - `value` is the decoded value
    - `rest` is the remaining binary data
  """
  @spec decode_field(binary(), String.t() | [String.t()] | map()) :: decoder_result()
  def decode_field(data, type) do
    debug("Decoding field", data: data, type: type)
    result = do_decode_field(data, type)
    debug("Decoded field", result: result)
    result
  end

  defp do_decode_field(data, "u8") when byte_size(data) < 1,
    do: {{:insufficient_data, "u8"}, data}

  defp do_decode_field(<<value::little-unsigned-integer-size(8), rest::binary>>, "u8"),
    do: {value, rest}

  defp do_decode_field(data, "u16") when byte_size(data) < 2,
    do: {{:insufficient_data, "u16"}, data}

  defp do_decode_field(<<value::little-unsigned-integer-size(16), rest::binary>>, "u16"),
    do: {value, rest}

  defp do_decode_field(data, "u32") when byte_size(data) < 4,
    do: {{:insufficient_data, "u32"}, data}

  defp do_decode_field(<<value::little-unsigned-integer-size(32), rest::binary>>, "u32"),
    do: {value, rest}

  defp do_decode_field(data, "u64") when byte_size(data) < 8,
    do: {{:insufficient_data, "u64"}, data}

  defp do_decode_field(<<value::little-unsigned-integer-size(64), rest::binary>>, "u64"),
    do: {value, rest}

  defp do_decode_field(data, "u128") when byte_size(data) < 16,
    do: {{:insufficient_data, "u128"}, data}

  defp do_decode_field(<<value::little-unsigned-integer-size(128), rest::binary>>, "u128"),
    do: {value, rest}

  defp do_decode_field(data, "i8") when byte_size(data) < 1,
    do: {{:insufficient_data, "i8"}, data}

  defp do_decode_field(<<value::little-signed-integer-size(8), rest::binary>>, "i8"),
    do: {value, rest}

  defp do_decode_field(data, "i16") when byte_size(data) < 2,
    do: {{:insufficient_data, "i16"}, data}

  defp do_decode_field(<<value::little-signed-integer-size(16), rest::binary>>, "i16"),
    do: {value, rest}

  defp do_decode_field(data, "i32") when byte_size(data) < 4,
    do: {{:insufficient_data, "i32"}, data}

  defp do_decode_field(<<value::little-signed-integer-size(32), rest::binary>>, "i32"),
    do: {value, rest}

  defp do_decode_field(data, "i64") when byte_size(data) < 8,
    do: {{:insufficient_data, "i64"}, data}

  defp do_decode_field(<<value::little-signed-integer-size(64), rest::binary>>, "i64"),
    do: {value, rest}

  defp do_decode_field(data, "f32") when byte_size(data) < 4,
    do: {{:insufficient_data, "f32"}, data}

  defp do_decode_field(<<value::little-float-size(32), rest::binary>>, "f32"), do: {value, rest}

  defp do_decode_field(data, "f64") when byte_size(data) < 8,
    do: {{:insufficient_data, "f64"}, data}

  defp do_decode_field(<<value::little-float-size(64), rest::binary>>, "f64"), do: {value, rest}

  defp do_decode_field(data, "bool") when byte_size(data) < 1,
    do: {{:insufficient_data, "bool"}, data}

  defp do_decode_field(<<value::unsigned-integer-size(8), rest::binary>>, "bool"),
    do: {value != 0, rest}

  defp do_decode_field(data, "publicKey") when byte_size(data) < 32,
    do: {{:insufficient_data, "publicKey"}, data}

  defp do_decode_field(<<value::binary-size(32), rest::binary>>, "publicKey"),
    do: {B58.encode58(value), rest}

  defp do_decode_field(data, [type, count]) when is_list(type) do
    debug("Decoding array", type: type, count: count)
    result = decode_array(data, type, count, [])
    debug("Decoded array", result: result)
    result
  end

  defp do_decode_field(data, type) when is_map(type) do
    debug("Decoding nested structure", type: type)
    result = decode(data, type)
    debug("Decoded nested structure", result: result)
    result
  end

  defp do_decode_field(data, type) do
    debug("Unknown type encountered", type: type)
    {{:unknown, type}, data}
  end

  @spec decode_array(binary(), String.t() | [String.t()] | map(), non_neg_integer(), list()) ::
          decoder_result()
  defp decode_array(data, _type, 0, acc), do: {Enum.reverse(acc), data}

  defp decode_array(data, type, count, acc) do
    debug("Decoding array element", type: type, remaining_count: count)
    {value, rest} = decode_field(data, type)
    debug("Decoded array element", value: value)
    decode_array(rest, type, count - 1, [value | acc])
  end

  @doc """
  Generates a decoder function for a given type.

  ## Parameters
    - type: The type to generate a decoder for

  ## Returns
    A function that takes binary data and returns `{value, rest}`
  """
  @spec generate_decoder(String.t() | [String.t()] | map()) :: decoder_fn()
  def generate_decoder(type) do
    debug("Generating decoder", type: type)

    decoder = fn data ->
      debug("Executing generated decoder", data: data, type: type)
      result = decode_field(data, type)
      debug("Generated decoder result", result: result)
      result
    end

    debug("Generated decoder", decoder: decoder)
    decoder
  end
end
