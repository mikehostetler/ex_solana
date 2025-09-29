defmodule ExSolana.RPC.GetTransactionTest do
  use ExUnit.Case, async: true

  alias ExSolana.RPC.Request

  describe "get_transaction/2" do
    test "builds correct request with string signature and default options" do
      signature =
        "5UAs6GCu5wkxbvgmwJaodRVHdi9ueWYEJj3PuGtPxzZm4GpTZaZGPAdc5qxzTpbmfJWtDmPikJrfwzp6MaUx9Pj7"

      expected_request = {
        "getTransaction",
        [
          signature,
          %{"commitment" => "confirmed", "encoding" => "base64"}
        ]
      }

      assert Request.get_transaction(signature) == expected_request
    end

    test "builds correct request with binary signature and default options" do
      # Create a binary signature
      binary_signature =
        <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
          25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46,
          47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64>>

      {:ok, encoded_signature} = ExSolana.Signature.encode(binary_signature)

      # Define the expected request
      expected_request = {
        "getTransaction",
        [
          encoded_signature,
          %{"commitment" => "confirmed", "encoding" => "base64"}
        ]
      }

      # Assert that the request matches the expected output
      assert Request.get_transaction(binary_signature) == expected_request
    end

    test "builds correct request with custom options" do
      signature =
        "5UAs6GCu5wkxbvgmwJaodRVHdi9ueWYEJj3PuGtPxzZm4GpTZaZGPAdc5qxzTpbmfJWtDmPikJrfwzp6MaUx9Pj7"

      opts = [
        commitment: "finalized",
        encoding: "jsonParsed",
        max_supported_transaction_version: 0
      ]

      expected_request = {
        "getTransaction",
        [
          signature,
          %{
            "commitment" => "finalized",
            "encoding" => "jsonParsed",
            "maxSupportedTransactionVersion" => 0
          }
        ]
      }

      assert Request.get_transaction(signature, opts) == expected_request
    end

    test "returns error with invalid options" do
      signature =
        "5UAs6GCu5wkxbvgmwJaodRVHdi9ueWYEJj3PuGtPxzZm4GpTZaZGPAdc5qxzTpbmfJWtDmPikJrfwzp6MaUx9Pj7"

      invalid_opts = [commitment: "invalid_commitment"]

      assert {:error, error_message} = Request.get_transaction(signature, invalid_opts)
      assert error_message =~ "invalid value for :commitment option"
    end

    test "returns error with invalid max_supported_transaction_version" do
      signature =
        "5UAs6GCu5wkxbvgmwJaodRVHdi9ueWYEJj3PuGtPxzZm4GpTZaZGPAdc5qxzTpbmfJWtDmPikJrfwzp6MaUx9Pj7"

      invalid_opts = [max_supported_transaction_version: -1]

      assert {:error, error_message} = Request.get_transaction(signature, invalid_opts)
      assert error_message =~ "invalid value for :max_supported_transaction_version option"
    end
  end
end
