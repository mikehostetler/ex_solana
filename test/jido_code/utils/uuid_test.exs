defmodule JidoCode.Utils.UUIDTest do
  use ExUnit.Case, async: true

  alias JidoCode.Utils.UUID

  describe "valid?/1" do
    test "returns true for valid lowercase UUID" do
      assert UUID.valid?("550e8400-e29b-41d4-a716-446655440000")
    end

    test "returns true for valid uppercase UUID" do
      assert UUID.valid?("550E8400-E29B-41D4-A716-446655440000")
    end

    test "returns true for valid mixed case UUID" do
      assert UUID.valid?("550e8400-E29B-41d4-A716-446655440000")
    end

    test "returns false for UUID without dashes" do
      refute UUID.valid?("550e8400e29b41d4a716446655440000")
    end

    test "returns false for short string" do
      refute UUID.valid?("550e8400-e29b-41d4")
    end

    test "returns false for long string" do
      refute UUID.valid?("550e8400-e29b-41d4-a716-446655440000-extra")
    end

    test "returns false for invalid characters" do
      refute UUID.valid?("550e8400-e29b-41d4-a716-44665544000g")
    end

    test "returns false for empty string" do
      refute UUID.valid?("")
    end

    test "returns false for nil" do
      refute UUID.valid?(nil)
    end

    test "returns false for integer" do
      refute UUID.valid?(123)
    end

    test "returns false for atom" do
      refute UUID.valid?(:uuid)
    end

    test "returns false for list" do
      refute UUID.valid?(["550e8400-e29b-41d4-a716-446655440000"])
    end

    test "returns false for path traversal attempt" do
      refute UUID.valid?("../../../etc/passwd")
    end

    test "returns false for PID-like string" do
      refute UUID.valid?("#PID<0.123.0>")
    end
  end

  describe "pattern/0" do
    test "returns a regex" do
      assert %Regex{} = UUID.pattern()
    end

    test "regex matches valid UUID" do
      assert Regex.match?(UUID.pattern(), "550e8400-e29b-41d4-a716-446655440000")
    end

    test "regex rejects invalid string" do
      refute Regex.match?(UUID.pattern(), "not-a-uuid")
    end
  end
end
