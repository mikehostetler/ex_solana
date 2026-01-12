defmodule ExSolanaTest.BorshTest do
  use ExUnit.Case

  defmodule NumericStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:u8, "u8"},
        {:u16, "u16"},
        {:u32, "u32"},
        {:u64, "u64"},
        {:u128, "u128"},
        {:i8, "i8"},
        {:i16, "i16"},
        {:i32, "i32"},
        {:i64, "i64"},
        {:i128, "i128"},
        {:f32, "f32"},
        {:f64, "f64"}
      ]
  end

  defmodule ArrayStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:int_array, ["u32", 3]},
        {:string_array, ["string", 2]}
      ]
  end

  defmodule NestedStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:inner,
         [
           field1: "u8",
           field2: "string"
         ]}
      ]
  end

  defmodule MaxValueStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:max_u8, "u8"},
        {:max_u16, "u16"},
        {:max_u32, "u32"},
        {:max_u64, "u64"}
      ]
  end

  defmodule EmptyStringStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:empty_string, "string"}
      ]
  end

  defmodule TestStruct do
    @moduledoc false
    use ExSolana.Borsh,
      schema: [
        {:name, "string"},
        {:age, "u8"},
        {:balance, "u64"},
        {:is_active, "bool"},
        {:scores, ["u16", 3]},
        {:pubkey, "pubkey"}
      ]
  end

  describe "encode and decode" do
    test "simple struct" do
      data = %TestStruct{
        name: "John",
        age: 30,
        balance: 1_000_000,
        is_active: true,
        scores: [100, 200, 300],
        pubkey: "11111111111111111111111111111111"
      }

      assert {:ok, encoded} = TestStruct.encode(data)
      assert {:ok, decoded} = TestStruct.decode(encoded)

      assert decoded == data
    end

    test "all numeric types" do
      data = %NumericStruct{
        u8: 255,
        u16: 65_535,
        u32: 4_294_967_295,
        u64: 18_446_744_073_709_551_615,
        u128: 340_282_366_920_938_463_463_374_607_431_768_211_455,
        i8: -128,
        i16: -32_768,
        i32: -2_147_483_648,
        i64: -9_223_372_036_854_775_808,
        i128: -170_141_183_460_469_231_731_687_303_715_884_105_728,
        f32: 3.14159,
        f64: 2.718281828459045
      }

      assert {:ok, encoded} = NumericStruct.encode(data)
      assert {:ok, decoded} = NumericStruct.decode(encoded)

      assert_in_delta decoded.f32, data.f32, 0.000001
      assert decoded.f64 == data.f64
      assert %{decoded | f32: data.f32} == data
    end

    test "arrays" do
      data = %ArrayStruct{
        int_array: [1, 2, 3],
        string_array: ["hello", "world"]
      }

      assert {:ok, encoded} = ArrayStruct.encode(data)
      assert {:ok, decoded} = ArrayStruct.decode(encoded)

      assert decoded == data
    end

    test "nested structs" do
      data = %NestedStruct{
        inner: %{
          field1: 42,
          field2: "nested"
        }
      }

      assert {:ok, encoded} = NestedStruct.encode(data)
      assert {:ok, decoded} = NestedStruct.decode(encoded)

      assert decoded == data
    end
  end

  describe "error handling" do
    test "insufficient data" do
      # Incomplete data
      assert {:error, reason} = TestStruct.decode(<<4, 74, 111, 104, 110>>)
      assert reason =~ "Failed to decode"
    end

    test "invalid pubkey" do
      invalid_data = %TestStruct{
        name: "John",
        age: 30,
        balance: 1_000_000,
        is_active: true,
        scores: [100, 200, 300],
        pubkey: "InvalidPubKey"
      }

      assert {:error, reason} = TestStruct.encode(invalid_data)
      assert reason =~ "Invalid pubkey"
    end
  end

  describe "edge cases" do
    test "empty string" do
      data = %EmptyStringStruct{empty_string: ""}
      assert {:ok, encoded} = EmptyStringStruct.encode(data)
      assert {:ok, decoded} = EmptyStringStruct.decode(encoded)

      assert decoded == data
    end

    test "max values" do
      data = %MaxValueStruct{
        max_u8: 255,
        max_u16: 65_535,
        max_u32: 4_294_967_295,
        max_u64: 18_446_744_073_709_551_615
      }

      assert {:ok, encoded} = MaxValueStruct.encode(data)
      assert {:ok, decoded} = MaxValueStruct.decode(encoded)

      assert decoded == data
    end

    test "out of range values" do
      invalid_data = %NumericStruct{
        u8: 256,
        u16: 65_536,
        u32: 4_294_967_296,
        u64: 18_446_744_073_709_551_616,
        u128: 340_282_366_920_938_463_463_374_607_431_768_211_456,
        i8: 128,
        i16: 32_768,
        i32: 2_147_483_648,
        i64: 9_223_372_036_854_775_808,
        i128: 170_141_183_460_469_231_731_687_303_715_884_105_728,
        f32: 3.14159,
        f64: 2.718281828459045
      }

      assert {:error, reason} = NumericStruct.encode(invalid_data)
      assert reason =~ "Failed to encode field"
    end
  end
end
