# defmodule ExSolana.TxnDecoderTest do
#   use ExUnit.Case, async: true
#   alias ExSolana.TxnDecoder
#   import ExSolana.TestHelpers

#   setup do
#     {:ok, samples: load_sample_transactions()}
#   end

#   describe "decode" do
#     test "decode/1 with valid input", %{samples: samples} do
#       for {sample, _index} <- Enum.with_index(samples) do
#         assert {:ok, _decoded} = TxnDecoder.decode(sample)
#       end
#     end
#   end

#   describe "safe decode methods" do
#     test "safe_encode_or_pass_through/2 with successful encoding" do
#       encode_fun = fn _ -> {:ok, "encoded"} end
#       assert TxnDecoder.safe_encode_or_pass_through(encode_fun, "value") == "encoded"
#     end

#     test "safe_encode_or_pass_through/2 with failed encoding" do
#       encode_fun = fn _ -> {:error, "failed"} end
#       assert TxnDecoder.safe_encode_or_pass_through(encode_fun, "value") == "value"
#     end

#     test "safe_encode_or_pass_through/2 with raised exception" do
#       encode_fun = fn _ -> raise "Error" end
#       assert TxnDecoder.safe_encode_or_pass_through(encode_fun, "value") == "value"
#     end

#     test "safe_decode_account_indexes/2 with binary accounts" do
#       accounts = <<0, 1, 2>>
#       account_keys = ["key1", "key2", "key3"]

#       result = TxnDecoder.safe_decode_account_indexes(accounts, account_keys)
#       assert result == ["key1", "key2", "key3"]
#     end

#     test "safe_decode_account_indexes/2 with non-binary accounts" do
#       accounts = [0, 1, 2]
#       account_keys = ["key1", "key2", "key3"]

#       assert TxnDecoder.safe_decode_account_indexes(accounts, account_keys) == accounts
#     end

#     test "safe_get_account_by_index/2 with valid index" do
#       account_keys = ["key1", "key2", "key3"]

#       result = TxnDecoder.safe_get_account_by_index(1, account_keys)
#       assert result == "key2"
#     end

#     test "safe_get_account_by_index/2 with invalid index" do
#       account_keys = ["key1", "key2", "key3"]

#       assert TxnDecoder.safe_get_account_by_index(-1, account_keys) == nil
#       assert TxnDecoder.safe_get_account_by_index(3, account_keys) == nil
#     end

#     test "safe_get_account_keys/1 with valid input" do
#       input = %{message: %{account_keys: ["key1", "key2", "key3"]}}
#       assert TxnDecoder.safe_get_account_keys(input) == ["key1", "key2", "key3"]
#     end

#     test "safe_get_account_keys/1 with invalid input" do
#       assert TxnDecoder.safe_get_account_keys(%{}) == []
#       assert TxnDecoder.safe_get_account_keys(%{message: %{}}) == []
#     end

#     test "safe_decode/2 with successful decoding" do
#       decode_fun = fn data -> String.upcase(data) end
#       assert TxnDecoder.safe_decode(decode_fun, "hello") == "HELLO"
#     end

#     test "safe_decode/2 with raised exception" do
#       decode_fun = fn _ -> raise "Error" end
#       assert TxnDecoder.safe_decode(decode_fun, "hello") == "hello"
#     end
#   end
# end
