defmodule ExSolana.RPC.GetSlotTest do
  use ExUnit.Case, async: true

  alias ExSolana.RPC
  alias ExSolana.RPC.Request

  @moduletag :solana
  setup_all do
    client = RPC.client(network: "localhost")
    tracker = ExSolana.tracker(client: client, t: 100)

    [tracker: tracker, client: client]
  end

  describe "get_slot/1" do
    test "builds correct request with default options" do
      expected_request = {
        "getSlot",
        [%{"commitment" => "confirmed"}]
      }

      assert Request.get_slot() == expected_request
    end

    test "builds correct request with custom options" do
      opts = [
        commitment: "finalized",
        min_context_slot: 123
      ]

      expected_request = {
        "getSlot",
        [
          %{
            "commitment" => "finalized",
            "minContextSlot" => 123
          }
        ]
      }

      assert Request.get_slot(opts) == expected_request
    end

    test "returns error with invalid options" do
      invalid_opts = [commitment: "invalid_commitment"]

      assert {:error, error_message} = Request.get_slot(invalid_opts)
      assert error_message =~ "invalid value for :commitment option"
    end

    test "returns error with invalid min_context_slot" do
      invalid_opts = [min_context_slot: -1]

      assert {:error, error_message} = Request.get_slot(invalid_opts)
      assert error_message =~ "invalid value for :min_context_slot option"
    end

    test "solana validator can accept the get_slot request", %{client: client} do
      request = Request.get_slot(commitment: "confirmed")

      assert {:ok, slot} = RPC.send(client, request)
      assert is_integer(slot)
      # assert slot > 0
    end
  end
end
