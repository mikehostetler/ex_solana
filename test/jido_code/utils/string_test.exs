defmodule JidoCode.Utils.StringTest do
  use ExUnit.Case, async: true

  alias JidoCode.Utils.String, as: StringUtils

  doctest JidoCode.Utils.String

  describe "truncate/3" do
    test "returns string unchanged when shorter than max" do
      assert StringUtils.truncate("hello", 10) == "hello"
    end

    test "returns string unchanged when equal to max" do
      assert StringUtils.truncate("hello", 5) == "hello"
    end

    test "truncates and adds ellipsis when longer than max" do
      assert StringUtils.truncate("hello world", 8) == "hello..."
    end

    test "uses custom suffix when provided" do
      assert StringUtils.truncate("hello world", 8, suffix: "…") == "hello w…"
    end

    test "handles very short max length" do
      assert StringUtils.truncate("hello", 2) == "he"
    end

    test "handles empty string" do
      assert StringUtils.truncate("", 10) == ""
    end
  end

  describe "truncate_binary/2" do
    test "returns binary unchanged when shorter than max" do
      assert StringUtils.truncate_binary("hello", 10) == "hello"
    end

    test "truncates at exact byte position" do
      assert StringUtils.truncate_binary("hello world", 5) == "hello"
    end

    test "handles large binaries" do
      large = String.duplicate("x", 1000)
      result = StringUtils.truncate_binary(large, 100)
      assert byte_size(result) == 100
    end
  end

  describe "to_display_string/1" do
    test "returns string as-is" do
      assert StringUtils.to_display_string("hello") == "hello"
    end

    test "converts atom to string" do
      assert StringUtils.to_display_string(:hello) == "hello"
    end

    test "inspects maps" do
      result = StringUtils.to_display_string(%{a: 1})
      assert String.contains?(result, "a:")
      assert String.contains?(result, "1")
    end

    test "inspects lists" do
      assert StringUtils.to_display_string([1, 2, 3]) == "[1, 2, 3]"
    end

    test "inspects numbers" do
      assert StringUtils.to_display_string(42) == "42"
    end
  end
end
