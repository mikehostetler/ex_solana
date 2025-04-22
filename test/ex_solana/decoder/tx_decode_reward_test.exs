# defmodule ExSolana.TxnDecoder.DecodeRewardTest do
#   use ExUnit.Case

#   import ExSolana.TestHelpers

#   alias ExSolana.Transaction.Core
#   alias ExSolana.TxnDecoder

#   setup do
#     samples = load_sample_transactions()
#     {:ok, samples: samples}
#   end

#   describe "decode_reward/1" do
#     test "successfully decodes valid reward data", %{samples: samples} do
#       for {sample, index} <- Enum.with_index(samples || []) do
#         rewards = get_in_struct(sample, ["transaction", "meta", "rewards"])

#         for reward <- rewards || [] do
#           result = TxnDecoder.decode_reward(reward)

#           assert {:ok, decoded} = result,
#                  "Sample #{index}: Expected successful decoding"

#           assert %Core.Reward{} = decoded,
#                  "Sample #{index}: Expected Core.Reward struct"

#           assert is_binary(decoded.pubkey), "Sample #{index}: Expected binary pubkey"
#           assert is_integer(decoded.lamports), "Sample #{index}: Expected integer lamports"

#           assert is_integer(decoded.post_balance),
#                  "Sample #{index}: Expected integer post_balance"

#           assert decoded.reward_type in Core.reward_types(),
#                  "Sample #{index}: Invalid reward_type"

#           assert is_binary(decoded.commission) or is_nil(decoded.commission),
#                  "Sample #{index}: Expected binary or nil commission"

#           # Verify that the pubkey is correctly encoded
#           original_pubkey = reward.pubkey
#           encoded_pubkey = B58.encode58(original_pubkey)

#           assert decoded.pubkey == encoded_pubkey,
#                  "Sample #{index}: Pubkey encoding mismatch"
#         end
#       end
#     end

#     test "handles reward with valid 32-byte pubkey" do
#       valid_reward = %{
#         pubkey: :crypto.strong_rand_bytes(32),
#         lamports: 1000,
#         post_balance: 5000,
#         reward_type: :Rent,
#         commission: "10"
#       }

#       assert {:ok, decoded} = TxnDecoder.decode_reward(valid_reward)
#       assert %Core.Reward{} = decoded
#       assert byte_size(B58.decode58!(decoded.pubkey)) == 32
#     end

#     test "returns error for invalid pubkey length" do
#       invalid_reward = %{
#         pubkey: <<1, 2, 3>>,
#         lamports: 1000,
#         post_balance: 5000,
#         reward_type: :Rent,
#         commission: "10"
#       }

#       assert {:error, "Invalid public key"} = TxnDecoder.decode_reward(invalid_reward)
#     end

#     test "handles missing post_balance" do
#       invalid_reward = %{
#         pubkey: :crypto.strong_rand_bytes(32),
#         lamports: 1000,
#         reward_type: :Rent,
#         commission: "10"
#       }

#       assert {:error, "Missing post_balance"} = TxnDecoder.decode_reward(invalid_reward)
#     end

#     test "handles all valid reward types" do
#       base_reward = %{
#         pubkey: :crypto.strong_rand_bytes(32),
#         lamports: 1000,
#         post_balance: 5000,
#         commission: "10"
#       }

#       for reward_type <- Core.reward_types() do
#         reward = Map.put(base_reward, :reward_type, reward_type)
#         assert {:ok, decoded} = TxnDecoder.decode_reward(reward)
#         assert decoded.reward_type == reward_type
#       end
#     end

#     test "handles nil commission" do
#       reward = %{
#         pubkey: :crypto.strong_rand_bytes(32),
#         lamports: 1000,
#         post_balance: 5000,
#         reward_type: :Staking,
#         commission: nil
#       }

#       assert {:ok, decoded} = TxnDecoder.decode_reward(reward)
#       assert is_nil(decoded.commission)
#     end

#     test "handles integer values correctly" do
#       reward = %{
#         pubkey: :crypto.strong_rand_bytes(32),
#         lamports: -500,
#         post_balance: 1_000_000_000,
#         reward_type: :Fee,
#         commission: "0"
#       }

#       assert {:ok, decoded} = TxnDecoder.decode_reward(reward)
#       assert decoded.lamports == -500
#       assert decoded.post_balance == 1_000_000_000
#     end
#   end
# end
