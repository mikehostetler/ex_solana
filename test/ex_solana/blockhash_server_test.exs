defmodule ExSolana.RPC.BlockhashServerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias ExSolana.RPC
  alias ExSolana.RPC.BlockhashServer

  @moduletag :solana
  setup :verify_on_exit!
  @spec ensure_blockhash_server(RPC.Client.t(), keyword()) :: {:ok, pid()}
  defp ensure_blockhash_server(client, opts \\ []) do
    case Process.whereis(BlockhashServer) do
      nil -> BlockhashServer.start_link([client: client] ++ opts)
      pid when is_pid(pid) -> {:ok, pid}
    end
  end

  setup do
    client = RPC.client(network: "localhost")
    [client: client]
  end

  describe "start_link/1" do
    test "starts the server successfully", %{client: client} do
      {:ok, pid} = ensure_blockhash_server(client)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "get_latest_blockhash/0" do
    setup %{client: client} do
      {:ok, _pid} = ensure_blockhash_server(client)
      :ok
    end

    test "returns a valid blockhash" do
      assert {:ok, blockhash} = BlockhashServer.get_latest_blockhash()
      assert is_binary(blockhash)
      assert byte_size(blockhash) == 32
    end

    test "returns the same blockhash for multiple calls within the fetch interval" do
      {:ok, blockhash1} = BlockhashServer.get_latest_blockhash()
      {:ok, blockhash2} = BlockhashServer.get_latest_blockhash()
      assert blockhash1 == blockhash2
    end
  end

  # test "performs periodic fetches" do
  #   fetch_interval = 500
  #   test_pid = self()

  #   # Mock the RPC call to return different blockhashes
  #   expect(ExSolana.RPC, :send, 2, fn _, _ ->
  #     send(test_pid, {:fetch_called, System.monotonic_time(:millisecond)})
  #     {:ok, %{"blockhash" => "hash_#{System.unique_integer()}"}}
  #   end)

  #   {:ok, _pid} =
  #     ensure_blockhash_server(RPC.client(network: "localhost"), fetch_interval: fetch_interval)

  #   assert_receive {:fetch_called, first_time}, 150
  #   assert_receive {:fetch_called, second_time}, 250
  #   assert second_time > first_time
  # end

  # describe "error handling" do
  #   test "handles RPC errors gracefully" do
  #     stub(RPC, :send, fn _, _ -> {:error, "RPC Error"} end)

  #     client = RPC.client(network: "localhost")
  #     {:ok, _pid} = ensure_blockhash_server(client)

  #     # Give the server time to process the initial fetch
  #     Process.sleep(50)

  #     assert {:error, "RPC Error"} = BlockhashServer.get_latest_blockhash()
  #   end
  # end
end
