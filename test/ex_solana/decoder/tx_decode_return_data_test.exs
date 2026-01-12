# defmodule ExSolana.TxnDecoder.DecodeReturnDataTest do
#   use ExUnit.Case

#   import ExSolana.TestHelpers

#   alias ExSolana.Transaction.Core
#   alias ExSolana.TxnDecoder

#   setup do
#     {:ok, samples: load_sample_transactions()}
#   end

#   describe "decode_return_data/1" do
#     test "successfully decodes valid return data", %{samples: samples} do
#       for {sample, index} <- Enum.with_index(samples) do
#         return_data = get_in_struct(sample, ["transaction", "meta", "returnData"])
#         result = TxnDecoder.decode_return_data(return_data)

#         case result do
#           {:ok, nil} ->
#             assert is_nil(return_data), "Sample #{index}: Expected nil return data"

#           {:ok, decoded} ->
#             assert %Core.ReturnData{} = decoded,
#                    "Sample #{index}: Expected Core.ReturnData struct"

#             assert is_binary(decoded.program_id), "Sample #{index}: Expected binary program_id"
#             assert is_binary(decoded.data), "Sample #{index}: Expected binary data"

#             # Verify that the program_id is correctly encoded
#             original_program_id = return_data.program_id
#             encoded_program_id = ExSolana.Key.encode!(original_program_id)

#             assert decoded.program_id == encoded_program_id,
#                    "Sample #{index}: Program ID encoding mismatch"

#           {:error, _} ->
#             flunk("Sample #{index}: Unexpected error in decoding return data")
#         end
#       end
#     end

#     test "handles nil return data" do
#       assert {:ok, nil} = TxnDecoder.decode_return_data(nil)
#     end

#     test "handles invalid return data structure" do
#       invalid_data = %{"invalid_key" => "invalid_value"}

#       assert {:error, "Invalid return data structure"} =
#                TxnDecoder.decode_return_data(invalid_data)
#     end

#     test "handles return data with missing fields" do
#       incomplete_data = %{program_id: <<1, 2, 3, 4>>}

#       assert {:error, "Invalid return data structure"} =
#                TxnDecoder.decode_return_data(incomplete_data)
#     end

#     test "handles return data with invalid field types" do
#       invalid_types = %{program_id: "not_binary", data: 123}

#       assert {:error, "Invalid return data structure"} =
#                TxnDecoder.decode_return_data(invalid_types)
#     end
#   end
# end
