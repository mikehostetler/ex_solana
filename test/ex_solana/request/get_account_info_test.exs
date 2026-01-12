defmodule ExSolana.RPC.GetAccountInfoTest do
  use ExUnit.Case, async: true

  import ExSolana, only: [pubkey!: 1]
  import ExSolana.TestHelpers, only: [create_payer: 3]

  alias ExSolana.RPC
  alias ExSolana.RPC.Request

  @moduletag :solana
  setup_all do
    client = RPC.client(network: "localhost")
    tracker = ExSolana.tracker(client: client, t: 100)
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "get_account_info/2" do
    test "builds correct request with valid public key and default options" do
      encoded_key = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"
      {:ok, binary_key} = B58.decode58(encoded_key)

      expected_request = {
        "getAccountInfo",
        [
          encoded_key,
          %{"commitment" => "confirmed", "encoding" => "base64"}
        ]
      }

      assert Request.get_account_info(binary_key) == expected_request
      assert Request.get_account_info(encoded_key) == expected_request
    end

    test "builds correct request with valid public key and custom options" do
      encoded_key = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"

      opts = [
        commitment: "confirmed",
        encoding: "jsonParsed",
        data_slice: %{offset: 0, length: 100}
      ]

      expected_request = {
        "getAccountInfo",
        [
          encoded_key,
          %{
            "commitment" => "confirmed",
            "encoding" => "jsonParsed",
            "dataSlice" => %{"offset" => 0, "length" => 100}
          }
        ]
      }

      assert Request.get_account_info(encoded_key, opts) == expected_request
    end

    test "returns error with invalid base58 encoded key" do
      invalid_key = "invalid_base58_key"

      assert {:error, error_message} = Request.get_account_info(invalid_key)
      assert error_message =~ "Invalid key"
    end

    test "returns error with short binary key" do
      # 31 bytes instead of 32
      short_key = <<0::248>>

      assert {:error, error_message} = Request.get_account_info(short_key)
      assert error_message =~ "Invalid key"
    end

    test "returns error with long binary key" do
      # 33 bytes instead of 32
      long_key = <<0::264>>

      assert {:error, error_message} = Request.get_account_info(long_key)
      assert error_message =~ "Invalid key"
    end

    test "returns error with non-binary, non-string key" do
      invalid_key = [:not_a_key]

      assert {:error, error_message} = Request.get_account_info(invalid_key)
      assert error_message =~ "Invalid key"
    end

    test "returns error with invalid options" do
      valid_key = "5Kx58iGycVmfuMeuLc8NUcDL1xdrTK7jg1WPYfVv8jMb"
      invalid_opts = [commitment: "invalid_commitment"]

      assert {:error, error_message} = Request.get_account_info(valid_key, invalid_opts)
      assert error_message =~ "invalid value for :commitment option"
    end

    test "solana validator can accept the get_account_info request", %{
      client: client,
      payer: payer
    } do
      public_key = pubkey!(payer)

      request = Request.get_account_info(public_key, commitment: "confirmed")

      assert {:ok, response} = RPC.send(client, request)
      assert is_map(response)
      assert Map.has_key?(response, "lamports")
      assert Map.has_key?(response, "owner")
      assert Map.has_key?(response, "data")
    end
  end
end
