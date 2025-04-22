# defmodule ExSolana.TxnDecoder.DecodeUiTokenAmountTest do
#   use ExUnit.Case
#   alias ExSolana.Transaction.Core
#   alias ExSolana.TxnDecoder

#   describe "decode_ui_token_amount/1" do
#     test "successfully decodes valid UI token amount" do
#       input = %{
#         ui_amount: 100.5,
#         decimals: 9,
#         amount: "100500000000",
#         ui_amount_string: "100.5"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 100.5
#       assert result.decimals == 9
#       assert result.amount == "100500000000"
#       assert result.ui_amount_string == "100.5"
#     end

#     test "handles zero values correctly" do
#       input = %{
#         ui_amount: 0.0,
#         decimals: 6,
#         amount: "0",
#         ui_amount_string: "0.0"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 0.0
#       assert result.decimals == 6
#       assert result.amount == "0"
#       assert result.ui_amount_string == "0.0"
#     end

#     test "handles large numbers correctly" do
#       input = %{
#         ui_amount: 1_000_000_000.123456789,
#         decimals: 9,
#         amount: "1000000000123456789",
#         ui_amount_string: "1000000000.123456789"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 1_000_000_000.123456789
#       assert result.decimals == 9
#       assert result.amount == "1000000000123456789"
#       assert result.ui_amount_string == "1000000000.123456789"
#     end

#     test "handles small numbers correctly" do
#       input = %{
#         ui_amount: 0.000000001,
#         decimals: 9,
#         amount: "1",
#         ui_amount_string: "0.000000001"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 0.000000001
#       assert result.decimals == 9
#       assert result.amount == "1"
#       assert result.ui_amount_string == "0.000000001"
#     end

#     test "handles different decimal places" do
#       input = %{
#         ui_amount: 123.45,
#         decimals: 3,
#         amount: "123450",
#         ui_amount_string: "123.45"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 123.45
#       assert result.decimals == 3
#       assert result.amount == "123450"
#       assert result.ui_amount_string == "123.45"
#     end

#     test "handles scientific notation in ui_amount" do
#       input = %{
#         ui_amount: 1.23e5,
#         decimals: 2,
#         amount: "12300000",
#         ui_amount_string: "123000.00"
#       }

#       assert {:ok, result} = TxnDecoder.decode_ui_token_amount(input)
#       assert %Core.UiTokenAmount{} = result
#       assert result.ui_amount == 1.23e5
#       assert result.decimals == 2
#       assert result.amount == "12300000"
#       assert result.ui_amount_string == "123000.00"
#     end

#     test "returns error for invalid ui_amount" do
#       invalid_input = %{
#         ui_amount: "not a number",
#         decimals: 9,
#         amount: "100000000",
#         ui_amount_string: "100.0"
#       }

#       assert {:error, :invalid_ui_amount} = TxnDecoder.decode_ui_token_amount(invalid_input)
#     end

#     test "returns error for invalid decimals" do
#       invalid_input = %{
#         ui_amount: 100.0,
#         decimals: "not an integer",
#         amount: "100000000",
#         ui_amount_string: "100.0"
#       }

#       assert {:error, :invalid_decimals} = TxnDecoder.decode_ui_token_amount(invalid_input)
#     end

#     test "returns error for invalid amount" do
#       invalid_input = %{
#         ui_amount: 100.0,
#         decimals: 9,
#         # Should be a string
#         amount: 100_000_000,
#         ui_amount_string: "100.0"
#       }

#       assert {:error, :invalid_amount} = TxnDecoder.decode_ui_token_amount(invalid_input)
#     end

#     test "returns error for invalid ui_amount_string" do
#       invalid_input = %{
#         ui_amount: 100.0,
#         decimals: 9,
#         amount: "100000000",
#         # Should be a string
#         ui_amount_string: 100.0
#       }

#       assert {:error, :invalid_ui_amount_string} =
#                TxnDecoder.decode_ui_token_amount(invalid_input)
#     end

#     test "returns error for missing keys" do
#       incomplete_input = %{
#         ui_amount: 100.0,
#         decimals: 9,
#         amount: "100000000"
#         # Missing ui_amount_string
#       }

#       assert {:error, :missing_key} = TxnDecoder.decode_ui_token_amount(incomplete_input)
#     end
#   end
# end
