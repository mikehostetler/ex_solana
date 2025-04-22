# defmodule ExSolana.Transaction.BuilderTest do
#   use ExUnit.Case, async: true
#   @moduletag :solana
#   import ExSolana.TestHelpers, only: [create_payer: 3]
#   import ExSolana, only: [pubkey!: 1]

#   alias ExSolana.{RPC, Transaction}
#   alias ExSolana.Transaction.Builder
#   alias ExSolana.Native.SystemProgram

#   setup_all do
#     client = RPC.client(network: "localhost")
#     tracker = ExSolana.tracker(client: client, t: 100)
#     {:ok, payer} = create_payer(tracker, client, commitment: "confirmed", amount: 1000)

#     [tracker: tracker, client: client, payer: payer]
#   end

#   describe "Transaction.Builder" do
#     test "builds a transaction matching a manually created one", %{client: client, payer: payer} do
#       new_account = ExSolana.keypair()
#       lamports = 1_000_000
#       space = 0

#       {:ok, %{"blockhash" => blockhash}} =
#         RPC.send(client, RPC.Request.get_latest_blockhash(commitment: "confirmed"))

#       # Manually created transaction
#       manual_tx = %Transaction{
#         instructions: [
#           SystemProgram.create_account(
#             lamports: lamports,
#             space: space,
#             program_id: SystemProgram.id(),
#             from: pubkey!(payer),
#             new: pubkey!(new_account)
#           ),
#           SystemProgram.transfer(
#             lamports: 500_000,
#             from: pubkey!(payer),
#             to: pubkey!(new_account)
#           )
#         ],
#         signers: [payer, new_account],
#         blockhash: blockhash,
#         payer: pubkey!(payer)
#       }

#       # Transaction created using the Builder
#       built_tx =
#         Builder.new()
#         |> Builder.payer(pubkey!(payer))
#         |> Builder.add_instruction(
#           SystemProgram.create_account(
#             lamports: lamports,
#             space: space,
#             program_id: SystemProgram.id(),
#             from: pubkey!(payer),
#             new: pubkey!(new_account)
#           )
#         )
#         |> Builder.add_instruction(
#           SystemProgram.transfer(
#             lamports: 500_000,
#             from: pubkey!(payer),
#             to: pubkey!(new_account)
#           )
#         )
#         |> Builder.add_signers([payer, new_account])
#         |> Builder.blockhash(client)
#         |> Builder.build()

#       assert {:ok, built_tx} = built_tx
#       assert built_tx.payer == manual_tx.payer
#       assert built_tx.instructions == manual_tx.instructions
#       assert built_tx.signers == manual_tx.signers
#       assert is_binary(built_tx.blockhash)
#     end

#     test "splits transaction when it exceeds limits", %{client: client, payer: payer} do
#       transfers =
#         Enum.map(1..25, fn _ ->
#           SystemProgram.transfer(
#             lamports: 1000,
#             from: pubkey!(payer),
#             to: pubkey!(ExSolana.keypair())
#           )
#         end)

#       result =
#         Builder.new()
#         |> Builder.payer(pubkey!(payer))
#         |> Builder.add_signers([payer])
#         |> add_many_instructions(transfers)
#         |> Builder.blockhash(client)
#         |> Builder.build()

#       assert {:ok, transactions} = result
#       assert is_list(transactions)
#       assert length(transactions) > 1

#       Enum.each(transactions, fn tx ->
#         assert tx.payer == pubkey!(payer)
#         assert tx.signers == [payer]
#         assert is_binary(tx.blockhash)
#         assert length(tx.instructions) <= Transaction.max_instructions()
#       end)

#       total_instructions =
#         Enum.reduce(transactions, 0, fn tx, acc -> acc + length(tx.instructions) end)

#       assert total_instructions == length(transfers)
#     end
#   end

#   test "handles empty transaction", %{client: client, payer: payer} do
#     result =
#       Builder.new()
#       |> Builder.payer(pubkey!(payer))
#       |> Builder.add_signers([payer])
#       |> Builder.blockhash(client)
#       |> Builder.build()

#     assert {:ok, tx} = result
#     assert tx.payer == pubkey!(payer)
#     assert tx.instructions == []
#     assert tx.signers == [payer]
#     assert is_binary(tx.blockhash)
#   end

#   test "handles maximum number of signers", %{client: client, payer: payer} do
#     max_signers = Transaction.max_signers()
#     additional_signers = Enum.map(1..(max_signers - 1), fn _ -> ExSolana.keypair() end)

#     result =
#       Builder.new()
#       |> Builder.payer(pubkey!(payer))
#       |> Builder.add_signers([payer | additional_signers])
#       |> Builder.blockhash(client)
#       |> Builder.build()

#     assert {:ok, tx} = result
#     assert length(tx.signers) == max_signers
#   end

#   defp add_many_instructions(builder, instructions) do
#     Enum.reduce(instructions, builder, fn instruction, acc ->
#       Builder.add_instruction(acc, instruction)
#     end)
#   end
# end
