defmodule ExSolana.RPC.GetBlockTest do
  use ExUnit.Case, async: true

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

  describe "get_block/2" do
    test "builds correct request with valid slot and default options" do
      slot = 100

      expected_request = {
        "getBlock",
        [
          slot,
          %{"commitment" => "confirmed", "encoding" => "base64"}
        ]
      }

      assert Request.get_block(slot) == expected_request
    end

    test "builds correct request with valid slot and custom options" do
      slot = 100

      opts = [
        commitment: "confirmed",
        encoding: "jsonParsed"
      ]

      expected_request = {
        "getBlock",
        [
          slot,
          %{
            "commitment" => "confirmed",
            "encoding" => "jsonParsed"
          }
        ]
      }

      assert Request.get_block(slot, opts) == expected_request
    end

    test "returns error with invalid slot" do
      invalid_slot = -1

      assert {:error, error_message} = Request.get_block(invalid_slot)
      assert error_message =~ "Invalid slot"
    end

    test "returns error with invalid options" do
      valid_slot = 100
      invalid_opts = [commitment: "invalid_commitment"]

      assert {:error, error} =
               Request.get_block(valid_slot, invalid_opts)

      assert error =~ "invalid value for :commitment option"
    end

    test "solana validator can accept the get_block request", %{
      client: client
    } do
      # Get the latest slot first
      {:ok, latest_slot} = RPC.send(client, Request.get_slot())

      request = Request.get_block(latest_slot, commitment: "confirmed")

      assert {:ok, block} = RPC.send(client, request)
      assert is_map(block)
      assert Map.has_key?(block, "blockhash")
      assert Map.has_key?(block, "parentSlot")
      assert Map.has_key?(block, "transactions")
    end
  end
end
