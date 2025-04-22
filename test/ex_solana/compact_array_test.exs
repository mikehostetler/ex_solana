defmodule ExSolana.CompactArrayTest do
  use ExUnit.Case

  alias ExSolana.CompactArray, as: C

  test "encodes" do
    Enum.each(
      [
        {0, [0]},
        {5, [5]},
        {0x7F, [0x7F]},
        {0x80, [0x80, 0x01]},
        {0xFF, [0xFF, 0x01]},
        {0x100, [0x80, 0x02]},
        {0x7FFF, [0xFF, 0xFF, 0x01]},
        {0x200000, [0x80, 0x80, 0x80, 0x01]}
      ],
      fn {length, expected} -> assert C.encode_length(length) == expected end
    )
  end

  test "decodes" do
    Enum.each([0, 5, 0x7F, 0x80, 0xFF, 0x100, 0x7FFF, 0x200000], fn length ->
      assert C.decode_length(C.encode_length(length)) == length
    end)
  end
end
