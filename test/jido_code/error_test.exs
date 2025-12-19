defmodule JidoCode.ErrorTest do
  use ExUnit.Case, async: true

  alias JidoCode.Error

  describe "new/3" do
    test "creates error with code and message" do
      error = Error.new(:not_found, "Resource not found")

      assert error.code == :not_found
      assert error.message == "Resource not found"
      assert error.details == nil
    end

    test "creates error with code, message, and details" do
      error = Error.new(:validation_failed, "Invalid input", %{field: :name, value: ""})

      assert error.code == :validation_failed
      assert error.message == "Invalid input"
      assert error.details == %{field: :name, value: ""}
    end
  end

  describe "wrap/3" do
    test "returns error tuple" do
      result = Error.wrap(:not_found, "User not found")

      assert {:error, %Error{code: :not_found, message: "User not found"}} = result
    end

    test "includes details in wrapped error" do
      result = Error.wrap(:config_invalid, "Bad config", %{key: :provider})

      assert {:error, %Error{details: %{key: :provider}}} = result
    end
  end

  describe "from_legacy/1" do
    test "passes through already wrapped errors" do
      original = Error.new(:test, "Test error")
      result = Error.from_legacy({:error, original})

      assert {:error, ^original} = result
    end

    test "converts {atom, string} tuple" do
      result = Error.from_legacy({:error, {:not_found, "Item not found"}})

      assert {:error, %Error{code: :not_found, message: "Item not found"}} = result
    end

    test "converts atom-only error" do
      result = Error.from_legacy({:error, :timeout})

      assert {:error, %Error{code: :timeout, message: "timeout"}} = result
    end

    test "converts string error" do
      result = Error.from_legacy({:error, "Something went wrong"})

      assert {:error, %Error{code: :unknown, message: "Something went wrong"}} = result
    end

    test "converts unknown error types" do
      result = Error.from_legacy({:error, {:complex, :error, :tuple}})

      assert {:error, %Error{code: :unknown}} = result
      assert {:error, %Error{message: message}} = result
      assert String.contains?(message, "complex")
    end
  end

  describe "pattern matching" do
    test "errors can be pattern matched by code" do
      {:error, error} = Error.wrap(:validation_failed, "Bad input")

      case {:error, error} do
        {:error, %Error{code: :validation_failed}} ->
          assert true

        _ ->
          flunk("Pattern matching failed")
      end
    end

    test "errors can be destructured" do
      {:error, error} = Error.wrap(:api_error, "API failed", %{status: 500})

      assert %Error{code: code, message: msg, details: details} = error
      assert code == :api_error
      assert msg == "API failed"
      assert details == %{status: 500}
    end
  end
end
