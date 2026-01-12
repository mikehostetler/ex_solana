defmodule ExSolana.SignatureTest do
  use ExUnit.Case, async: true

  alias ExSolana.Signature

  doctest ExSolana.Signature

  @valid_encoded_signature "3HJGsoCQacWHNXvJ6WrBBLtFWfekGzjAirgKtDkS2b5d5QzcTH96NKHM65VfLRT8dyUBut56dSbFcAhN832TsVJq"
  @invalid_signature <<1, 2, 3>>
  @invalid_encoded_signature "invalid_base58"

  describe "check/1" do
    test "returns ok tuple for valid signature" do
      {:ok, valid_signature} = Signature.decode(@valid_encoded_signature)
      assert {:ok, ^valid_signature} = Signature.check(valid_signature)
    end

    test "returns error tuple for invalid signature" do
      assert {:error, :invalid_signature} == Signature.check(@invalid_signature)
    end

    test "returns error tuple for non-binary input" do
      assert {:error, :invalid_signature} == Signature.check(123)
    end
  end

  describe "decode/1" do
    test "successfully decodes valid base58 encoded signature" do
      assert {:ok, decoded} = Signature.decode(@valid_encoded_signature)
      assert byte_size(decoded) == 64
    end

    test "returns error for invalid base58 encoded signature" do
      assert {:error, :invalid_signature} == Signature.decode(@invalid_encoded_signature)
    end

    test "returns error for non-binary input" do
      assert {:error, :invalid_signature} == Signature.decode(123)
    end
  end

  describe "decode!/1" do
    test "successfully decodes valid base58 encoded signature" do
      decoded = Signature.decode!(@valid_encoded_signature)
      assert byte_size(decoded) == 64
    end

    test "raises ArgumentError for invalid base58 encoded signature" do
      assert_raise ArgumentError, "invalid signature input: #{@invalid_encoded_signature}", fn ->
        Signature.decode!(@invalid_encoded_signature)
      end
    end

    test "raises ArgumentError for non-binary input" do
      assert_raise ArgumentError, "invalid signature input", fn ->
        Signature.decode!(123)
      end
    end
  end

  describe "encode/1" do
    test "successfully encodes valid signature to base58" do
      {:ok, valid_signature} = Signature.decode(@valid_encoded_signature)
      assert {:ok, encoded} = Signature.encode(valid_signature)
      assert is_binary(encoded)
      assert String.length(encoded) > 0
    end

    test "returns error for invalid signature" do
      assert {:error, :invalid_signature} == Signature.encode(@invalid_signature)
    end

    test "returns error for non-binary input" do
      assert {:error, :invalid_signature} == Signature.encode(123)
    end
  end

  describe "encode!/1" do
    test "successfully encodes valid signature to base58" do
      {:ok, valid_signature} = Signature.decode(@valid_encoded_signature)
      encoded = Signature.encode!(valid_signature)
      assert is_binary(encoded)
      assert String.length(encoded) > 0
    end

    test "raises ArgumentError for invalid signature" do
      assert_raise ArgumentError, "invalid signature", fn ->
        Signature.encode!(@invalid_signature)
      end
    end

    test "raises ArgumentError for non-binary input" do
      assert_raise ArgumentError, "invalid signature", fn ->
        Signature.encode!(123)
      end
    end
  end

  describe "roundtrip encoding and decoding" do
    test "encoding and then decoding returns original signature" do
      {:ok, original} = Signature.decode(@valid_encoded_signature)
      {:ok, encoded} = Signature.encode(original)
      assert {:ok, ^original} = Signature.decode(encoded)
    end

    test "decoding and then encoding returns original encoded signature" do
      {:ok, decoded} = Signature.decode(@valid_encoded_signature)
      {:ok, encoded} = Signature.encode(decoded)
      assert byte_size(decoded) == 64
      assert String.length(encoded) > 0
    end
  end
end
