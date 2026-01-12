# # First, create a new file: lib/ex_solana/system_adapter.ex

# defmodule ExSolana.SystemAdapter do
#   @moduledoc """
#   Adapter for System functions to allow easier mocking in tests.
#   """

#   @callback get_server_state(pid()) :: map()

#   def get_server_state(pid) do
#     :sys.get_state(pid)
#   end
# end

# # Now, update the TipServer module to use this adapter:
# # In lib/ex_solana/jito/tip_server.ex

# defmodule ExSolana.Jito.TipServer do
#   # ... (keep existing code)

#   @websockex Application.compile_env(:ex_solana, :websockex, WebSockex)
#   @system_adapter Application.compile_env(:ex_solana, :system_adapter, ExSolana.SystemAdapter)

#   # ... (keep existing code)

#   def get_latest_tips do
#     try do
#       case @system_adapter.get_server_state(__MODULE__) do
#         %{latest_tips: nil} -> {:error, :no_data_yet}
#         %{latest_tips: tips} -> {:ok, tips}
#       end
#     rescue
#       error ->
#         Logger.error("Failed to retrieve latest tips: #{inspect(error)}")
#         {:error, :unavailable}
#     end
#   end

#   # ... (keep existing code)
# end

# # Now, update the test file: test/ex_solana/jito/tip_server_test.exs

# defmodule ExSolana.Jito.TipServerTest do
#   use ExUnit.Case, async: true
#   import Mox
#   alias ExSolana.Jito.TipServer

#   # Define mock modules
#   defmock(WebSockexMock, for: WebSockex)
#   defmock(SystemAdapterMock, for: ExSolana.SystemAdapter)

#   setup :verify_on_exit!

#   setup do
#     # Replace the real WebSockex and SystemAdapter with our mocks
#     Application.put_env(:ex_solana, :websockex, WebSockexMock)
#     Application.put_env(:ex_solana, :system_adapter, SystemAdapterMock)

#     :ok
#   end

#   test "start_link establishes WebSocket connection" do
#     expect(WebSockexMock, :start_link, fn _url, _module, _state, _opts ->
#       {:ok, self()}
#     end)

#     assert {:ok, _pid} = TipServer.start_link()
#   end

#   test "get_latest_tips returns error when no data available" do
#     start_supervised!(TipServer)

#     expect(SystemAdapterMock, :get_server_state, fn _pid ->
#       %{latest_tips: nil}
#     end)

#     assert {:error, :no_data_yet} = TipServer.get_latest_tips()
#   end

#   test "get_latest_tips returns latest tips when available" do
#     start_supervised!(TipServer)

#     tips = %{
#       landed_tips_25th_percentile: 0.000001,
#       landed_tips_50th_percentile: 0.000002,
#       landed_tips_75th_percentile: 0.000003,
#       landed_tips_95th_percentile: 0.000004,
#       landed_tips_99th_percentile: 0.000005,
#       ema_landed_tips_50th_percentile: 0.000006
#     }

#     expect(SystemAdapterMock, :get_server_state, fn _pid ->
#       %{latest_tips: tips}
#     end)

#     assert {:ok, ^tips} = TipServer.get_latest_tips()
#   end

#   test "handle_frame processes valid JSON message" do
#     json_msg =
#       Jason.encode!([
#         %{
#           "landed_tips_25th_percentile" => "1e-6",
#           "landed_tips_50th_percentile" => "2e-6",
#           "landed_tips_75th_percentile" => "3e-6",
#           "landed_tips_95th_percentile" => "4e-6",
#           "landed_tips_99th_percentile" => "5e-6",
#           "ema_landed_tips_50th_percentile" => "6e-6"
#         }
#       ])

#     state = %{latest_tips: nil}

#     {:ok, new_state} = TipServer.handle_frame({:text, json_msg}, state)

#     assert new_state.latest_tips == %{
#              landed_tips_25th_percentile: 0.000001,
#              landed_tips_50th_percentile: 0.000002,
#              landed_tips_75th_percentile: 0.000003,
#              landed_tips_95th_percentile: 0.000004,
#              landed_tips_99th_percentile: 0.000005,
#              ema_landed_tips_50th_percentile: 0.000006
#            }
#   end

#   test "handle_frame ignores invalid JSON message" do
#     invalid_msg = "invalid json"
#     state = %{latest_tips: nil}

#     {:ok, new_state} = TipServer.handle_frame({:text, invalid_msg}, state)

#     assert new_state == state
#   end

#   test "handle_disconnect schedules reconnection" do
#     state = %{reconnect_interval: 100}
#     disconnect_map = %{reason: :normal}

#     {:reconnect, ^state} = TipServer.handle_disconnect(disconnect_map, state)
#   end

#   test "convert_to_sol handles different value types" do
#     tips = %{
#       "landed_tips_25th_percentile" => "1e-6",
#       "landed_tips_50th_percentile" => 2.0e-6,
#       "landed_tips_75th_percentile" => "3e-6",
#       "landed_tips_95th_percentile" => 4.0e-6,
#       "landed_tips_99th_percentile" => "5e-6",
#       "ema_landed_tips_50th_percentile" => 6.0e-6
#     }

#     converted = TipServer.convert_to_sol(tips)

#     assert_in_delta converted.landed_tips_25th_percentile, 0.000001, 0.0000001
#     assert_in_delta converted.landed_tips_50th_percentile, 0.000002, 0.0000001
#     assert_in_delta converted.landed_tips_75th_percentile, 0.000003, 0.0000001
#     assert_in_delta converted.landed_tips_95th_percentile, 0.000004, 0.0000001
#     assert_in_delta converted.landed_tips_99th_percentile, 0.000005, 0.0000001
#     assert_in_delta converted.ema_landed_tips_50th_percentile, 0.000006, 0.0000001
#   end
# end
