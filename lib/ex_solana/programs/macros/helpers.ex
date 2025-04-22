defmodule ExSolana.Program.IDLMacros.Helpers do
  @moduledoc false
  def generate_field_pattern(args) do
    Map.new(args, fn arg ->
      {String.to_atom(arg.name), convert_type(arg.type)}
    end)
  end

  # Helper function to convert IDL types to BinaryDecoder types
  def convert_type("u8"), do: "u8"
  def convert_type("u16"), do: "u16"
  def convert_type("u32"), do: "u32"
  def convert_type("u64"), do: "u64"
  def convert_type("i8"), do: "i8"
  def convert_type("i16"), do: "i16"
  def convert_type("i32"), do: "i32"
  def convert_type("i64"), do: "i64"
  def convert_type("f32"), do: "f32"
  def convert_type("f64"), do: "f64"
  def convert_type("bool"), do: "bool"
  def convert_type("publicKey"), do: "publicKey"
  def convert_type(%{"array" => [type, size]}), do: [convert_type(type), size]
  def convert_type(%{"option" => type}), do: {:option, convert_type(type)}
  def convert_type(%{"defined" => type}), do: {:defined, type}
  def convert_type(type) when is_binary(type), do: {:custom, type}
  def convert_type(type), do: {:unknown, type}
end
