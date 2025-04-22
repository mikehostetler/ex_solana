# defmodule ExSolana.TxnDecoder.DecodeTokenBalanceTest do
#   use ExUnit.Case
#   alias ExSolana.Transaction.Core
#   alias ExSolana.TxnDecoder
#   import ExSolana.TestHelpers
#   use Private

#   setup do
#     {:ok, samples: load_sample_transactions()}
#   end

#   describe "decode_token_balance/1" do
#     test "successfully decodes valid token balances from samples", %{samples: samples} do
#       for {sample, _index} <- Enum.with_index(samples) do
#         pre_token_balances = get_in_struct(sample, ["transaction", "meta", "preTokenBalances"])
#         post_token_balances = get_in_struct(sample, ["transaction", "meta", "postTokenBalances"])
#         token_balances = (pre_token_balances || []) ++ (post_token_balances || [])

#         for token_balance <- token_balances do
#           assert {:ok, result} = TxnDecoder.decode_token_balance(token_balance)
#           assert %Core.TokenBalance{} = result
#           assert is_integer(result.account_index)
#           assert is_binary(result.mint)
#           assert %Core.UiTokenAmount{} = result.ui_token_amount
#           assert is_binary(result.owner)
#           assert is_binary(result.program_id)
#         end
#       end
#     end

#     test "handles missing fields" do
#       incomplete_input = %{"accountIndex" => 1, "mint" => "SomeMint"}

#       assert {:error, "Invalid token balance format"} =
#                TxnDecoder.decode_token_balance(incomplete_input)
#     end

#     test "handles invalid input type" do
#       assert {:error, "Invalid token balance format"} =
#                TxnDecoder.decode_token_balance("invalid input")
#     end
#   end

#   describe "safe_encode_or_pass_through/2" do
#     # test "successfully encodes valid input" do
#     #   input =
#     #     <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
#     #       25, 26, 27, 28, 29, 30, 31, 32>>

#     #   encoded = TxnDecoder.safe_encode_or_pass_through(&ExSolana.Key.encode!/1, input)
#     #   assert is_binary(encoded)
#     #   assert encoded != input
#     # end

#     test "passes through invalid input" do
#       input = "invalid_input"
#       result = TxnDecoder.safe_encode_or_pass_through(&ExSolana.Key.encode!/1, input)
#       assert result == input
#     end
#   end

#   describe "safe_decode/2" do
#     test "successfully decodes valid ui_token_amount", %{samples: samples} do
#       sample = hd(samples)

#       sample_ui_token_amount =
#         get_in_struct(sample, [
#           "transaction",
#           "meta",
#           "preTokenBalances",
#           Access.at(0),
#           "uiTokenAmount"
#         ])

#       if sample_ui_token_amount do
#         decoded =
#           TxnDecoder.safe_decode(&TxnDecoder.decode_ui_token_amount/1, sample_ui_token_amount)

#         assert %Core.UiTokenAmount{} = decoded
#         assert is_float(decoded.ui_amount) || is_nil(decoded.ui_amount)
#         assert is_integer(decoded.decimals)
#         assert is_binary(decoded.amount)
#         assert is_binary(decoded.ui_amount_string)
#       else
#         :ok
#       end
#     end

#     test "passes through invalid input" do
#       input = "invalid_input"
#       result = TxnDecoder.safe_decode(&TxnDecoder.decode_ui_token_amount/1, input)
#       assert result == input
#     end
#   end
# end
