defmodule ExSolana.RPC.GetSignaturesForAddressTest do
  use ExUnit.Case, async: true

  alias ExSolana.RPC.Request

  describe "get_signatures_for_address/2" do
    test "builds correct request with valid address and default options" do
      address = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"

      expected_request = {
        "getSignaturesForAddress",
        [
          address,
          %{"commitment" => "confirmed"}
        ]
      }

      assert Request.get_signatures_for_address(address) == expected_request
    end

    test "builds correct request with valid address and custom options" do
      address = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"

      opts = [
        commitment: "finalized",
        encoding: "jsonParsed",
        before: "signature1",
        until: "signature2",
        limit: 500
      ]

      expected_request = {
        "getSignaturesForAddress",
        [
          address,
          %{
            "commitment" => "finalized",
            "encoding" => "jsonParsed",
            "before" => "signature1",
            "until" => "signature2",
            "limit" => 500
          }
        ]
      }

      assert Request.get_signatures_for_address(address, opts) == expected_request
    end

    test "returns error with invalid options" do
      address = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"
      invalid_opts = [commitment: "invalid_commitment"]

      assert {:error, error_message} = Request.get_signatures_for_address(address, invalid_opts)
      assert error_message =~ "invalid value for :commitment option"
    end

    test "returns error with invalid limit" do
      address = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"
      invalid_opts = [limit: 1001]

      assert {:error, error_message} = Request.get_signatures_for_address(address, invalid_opts)
      assert error_message =~ "invalid value for :limit option"
    end

    test "returns error with non-binary address" do
      invalid_address = 123

      assert_raise FunctionClauseError, fn ->
        Request.get_signatures_for_address(invalid_address)
      end
    end
  end
end
