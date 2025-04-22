defmodule ExSolana.Borsh do
  @moduledoc """
  A module for encoding and decoding data according to the Borsh specification,
  with integrated TypedStruct support.
  """

  use ExSolana.Util.DebugTools, debug_enabled: false

  @type decoder_result :: {:ok, {term(), binary()}} | {:error, String.t()}
  @type decoder_fn :: (binary() -> decoder_result())
  @type pattern :: [{atom(), String.t() | [String.t()] | Keyword.t()}]

  @doc """
  Decodes binary data based on the given pattern.
  """
  @spec decode(binary(), pattern()) :: {:ok, {map(), binary()}} | {:error, String.t()}
  def decode(data, pattern) when is_binary(data) and is_list(pattern) do
    debug("Starting decode", data: data, pattern: pattern)

    Enum.reduce_while(pattern, {:ok, {%{}, data}}, fn {key, type}, {:ok, {acc, rest}} ->
      debug("Decoding field", key: key, type: type)

      case decode_field(rest, type) do
        {:ok, {value, new_rest}} ->
          debug("Decoded field", key: key, value: value)
          {:cont, {:ok, {Map.put(acc, key, value), new_rest}}}

        {:error, reason} ->
          {:halt, {:error, "Failed to decode field #{key}: #{reason}"}}
      end
    end)
  end

  @doc """
  Decodes a single field based on its type.
  """
  @spec decode_field(binary(), String.t() | [String.t()] | Keyword.t()) :: decoder_result()
  def decode_field(data, type) do
    debug("Decoding field", data: data, type: type)
    result = do_decode_field(data, type)
    debug("Decoded field", result: result)
    result
  end

  # Implement all Borsh types
  defp do_decode_field(<<value::little-unsigned-integer-size(8), rest::binary>>, "u8"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-unsigned-integer-size(16), rest::binary>>, "u16"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-unsigned-integer-size(32), rest::binary>>, "u32"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-unsigned-integer-size(64), rest::binary>>, "u64"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-unsigned-integer-size(128), rest::binary>>, "u128"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-signed-integer-size(8), rest::binary>>, "i8"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-signed-integer-size(16), rest::binary>>, "i16"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-signed-integer-size(32), rest::binary>>, "i32"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-signed-integer-size(64), rest::binary>>, "i64"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-signed-integer-size(128), rest::binary>>, "i128"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-float-size(32), rest::binary>>, "f32"), do: {:ok, {value, rest}}

  defp do_decode_field(<<value::little-float-size(64), rest::binary>>, "f64"), do: {:ok, {value, rest}}

  defp do_decode_field(<<0, rest::binary>>, "bool"), do: {:ok, {false, rest}}
  defp do_decode_field(<<1, rest::binary>>, "bool"), do: {:ok, {true, rest}}

  defp do_decode_field(<<len::little-unsigned-integer-size(32), value::binary-size(len), rest::binary>>, "string") do
    {:ok, {value, rest}}
  end

  defp do_decode_field(<<value::binary-size(32), rest::binary>>, "pubkey") do
    {:ok, {B58.encode58(value), rest}}
  end

  defp do_decode_field(data, [type, count]) when is_binary(data) and is_integer(count) do
    decode_array(data, type, count, [])
  end

  defp do_decode_field(data, type) when is_list(type) do
    case decode(data, type) do
      {:ok, {decoded, rest}} -> {:ok, {decoded, rest}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_decode_field(data, {:enum, module}) do
    case data do
      <<variant::little-unsigned-integer-size(8), rest::binary>> ->
        case apply(module, :decode_variant, [variant]) do
          {:ok, decoded} -> {:ok, {decoded, rest}}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, "Insufficient data for enum decoding"}
    end
  end

  defp do_decode_field(_data, type) do
    {:error, "Unknown type: #{inspect(type)}"}
  end

  defp decode_array(data, _type, 0, acc), do: {:ok, {Enum.reverse(acc), data}}

  defp decode_array(data, type, count, acc) do
    case do_decode_field(data, type) do
      {:ok, {value, rest}} -> decode_array(rest, type, count - 1, [value | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Encodes data based on the given pattern.
  """
  @spec encode(map(), pattern()) :: {:ok, binary()} | {:error, String.t()}
  def encode(data, pattern) when is_map(data) and is_list(pattern) do
    debug("Starting encode", data: data, pattern: pattern)

    Enum.reduce_while(pattern, {:ok, <<>>}, fn {key, type}, {:ok, acc} ->
      value = Map.get(data, key)
      debug("Encoding field", key: key, type: type, value: value)

      case encode_field(value, type) do
        {:ok, encoded} ->
          debug("Encoded field", key: key, encoded: encoded)
          {:cont, {:ok, acc <> encoded}}

        {:error, reason} ->
          {:halt, {:error, "Failed to encode field #{key}: #{reason}"}}
      end
    end)
  end

  @doc """
  Encodes a single field based on its type.
  """
  @spec encode_field(term(), String.t() | [String.t()] | Keyword.t()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_field(value, type) do
    debug("Encoding field", value: value, type: type)
    result = do_encode_field(value, type)
    debug("Encoded field", result: result)
    result
  end

  # Implement encoding for all Borsh types
  defp do_encode_field(value, "u8") when is_integer(value) and value >= 0 and value <= 255,
    do: {:ok, <<value::little-unsigned-integer-size(8)>>}

  defp do_encode_field(value, "u16") when is_integer(value) and value >= 0 and value <= 65_535,
    do: {:ok, <<value::little-unsigned-integer-size(16)>>}

  defp do_encode_field(value, "u32") when is_integer(value) and value >= 0 and value <= 4_294_967_295,
    do: {:ok, <<value::little-unsigned-integer-size(32)>>}

  defp do_encode_field(value, "u64") when is_integer(value) and value >= 0 and value <= 18_446_744_073_709_551_615,
    do: {:ok, <<value::little-unsigned-integer-size(64)>>}

  defp do_encode_field(value, "u128")
       when is_integer(value) and value >= 0 and value <= 340_282_366_920_938_463_463_374_607_431_768_211_455,
       do: {:ok, <<value::little-unsigned-integer-size(128)>>}

  defp do_encode_field(value, "i8") when is_integer(value) and value >= -128 and value <= 127,
    do: {:ok, <<value::little-signed-integer-size(8)>>}

  defp do_encode_field(value, "i16") when is_integer(value) and value >= -32_768 and value <= 32_767,
    do: {:ok, <<value::little-signed-integer-size(16)>>}

  defp do_encode_field(value, "i32") when is_integer(value) and value >= -2_147_483_648 and value <= 2_147_483_647,
    do: {:ok, <<value::little-signed-integer-size(32)>>}

  defp do_encode_field(value, "i64")
       when is_integer(value) and value >= -9_223_372_036_854_775_808 and value <= 9_223_372_036_854_775_807,
       do: {:ok, <<value::little-signed-integer-size(64)>>}

  defp do_encode_field(value, "i128")
       when is_integer(value) and value >= -170_141_183_460_469_231_731_687_303_715_884_105_728 and
              value <= 170_141_183_460_469_231_731_687_303_715_884_105_727,
       do: {:ok, <<value::little-signed-integer-size(128)>>}

  defp do_encode_field(value, "f32") when is_float(value), do: {:ok, <<value::little-float-size(32)>>}

  defp do_encode_field(value, "f64") when is_float(value), do: {:ok, <<value::little-float-size(64)>>}

  defp do_encode_field(false, "bool"), do: {:ok, <<0>>}
  defp do_encode_field(true, "bool"), do: {:ok, <<1>>}

  defp do_encode_field(value, "string") when is_binary(value) do
    len = byte_size(value)
    {:ok, <<len::little-unsigned-integer-size(32), value::binary>>}
  end

  defp do_encode_field(value, "pubkey") do
    case B58.decode58(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "Invalid pubkey: #{reason}"}
    end
  end

  defp do_encode_field(values, [type, _count]) when is_list(values) do
    Enum.reduce_while(values, {:ok, <<>>}, fn value, {:ok, acc} ->
      case encode_field(value, type) do
        {:ok, encoded} -> {:cont, {:ok, acc <> encoded}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp do_encode_field(value, type) when is_list(type) do
    encode(value, type)
  end

  defp do_encode_field(value, {:enum, module}) do
    case apply(module, :encode_variant, [value]) do
      {:ok, variant} -> {:ok, <<variant::little-unsigned-integer-size(8)>>}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_encode_field(value, type) do
    {:error, "Unknown type: #{inspect(type)} for value: #{inspect(value)}"}
  end

  defmacro __using__(opts) do
    quote do
      use TypedStruct

      import ExSolana.Borsh

      @borsh_schema unquote(opts[:schema])

      typedstruct do
        unquote(generate_typedstruct_fields(opts[:schema]))
      end

      def decode(data) do
        case ExSolana.Borsh.decode(data, @borsh_schema) do
          {:ok, {decoded, _rest}} -> {:ok, struct(__MODULE__, decoded)}
          {:error, reason} -> {:error, reason}
        end
      end

      def encode(%__MODULE__{} = data) do
        map_data = Map.from_struct(data)
        ExSolana.Borsh.encode(map_data, @borsh_schema)
      end
    end
  end

  defp generate_typedstruct_fields(schema) do
    Enum.map(schema, fn {name, type} ->
      quote do
        field(unquote(name), unquote(borsh_type_to_elixir_type(type)), enforce: true)
      end
    end)
  end

  defp borsh_type_to_elixir_type(type) do
    case type do
      "u8" -> quote do: non_neg_integer()
      "u16" -> quote do: non_neg_integer()
      "u32" -> quote do: non_neg_integer()
      "u64" -> quote do: non_neg_integer()
      "u128" -> quote do: non_neg_integer()
      "i8" -> quote do: integer()
      "i16" -> quote do: integer()
      "i32" -> quote do: integer()
      "i64" -> quote do: integer()
      "i128" -> quote do: integer()
      "f32" -> quote do: float()
      "f64" -> quote do: float()
      "bool" -> quote do: boolean()
      "string" -> quote do: String.t()
      "pubkey" -> quote do: String.t()
      [inner_type, _size] -> quote do: list(unquote(borsh_type_to_elixir_type(inner_type)))
      {:enum, module} -> quote do: unquote(module).t()
      _ when is_list(type) -> quote do: map()
      _ -> quote do: any()
    end
  end
end
