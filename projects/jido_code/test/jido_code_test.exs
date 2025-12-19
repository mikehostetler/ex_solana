defmodule JidoCodeTest do
  use ExUnit.Case
  doctest JidoCode

  describe "version/0" do
    test "returns version string" do
      assert is_binary(JidoCode.version())
    end
  end
end
