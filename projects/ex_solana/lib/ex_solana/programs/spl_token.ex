# defmodule ExSolana.Program.SPL.Token do
#   @moduledoc false
#   use ExSolana.ProgramBehaviour,
#     idl_path: "priv/idl/spl_token.json",
#     program_id: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

#   # alias ExSolana.Transaction.Core
#   alias ExSolana.Actions

#   # def analyze_invocation(
#   #       %Core.Invocation{instruction: instruction_type} = invocation,
#   #       confirmed_transaction
#   #     ) do
#   #   case instruction_type do
#   #     :initializeMint ->
#   #       analyze_initialize_mint(invocation, confirmed_transaction)

#   #     :initializeAccount ->
#   #       analyze_initialize_account(invocation, confirmed_transaction)

#   #     :initializeMultisig ->
#   #       analyze_initialize_multisig(invocation, confirmed_transaction)

#   #     :transfer ->
#   #       analyze_transfer(invocation, confirmed_transaction)

#   #     :approve ->
#   #       analyze_approve(invocation, confirmed_transaction)

#   #     :revoke ->
#   #       analyze_revoke(invocation, confirmed_transaction)

#   #     :setAuthority ->
#   #       analyze_set_authority(invocation, confirmed_transaction)

#   #     :mintTo ->
#   #       analyze_mint_to(invocation, confirmed_transaction)

#   #     :burn ->
#   #       analyze_burn(invocation, confirmed_transaction)

#   #     :closeAccount ->
#   #       analyze_close_account(invocation, confirmed_transaction)

#   #     :freezeAccount ->
#   #       analyze_freeze_account(invocation, confirmed_transaction)

#   #     :thawAccount ->
#   #       analyze_thaw_account(invocation, confirmed_transaction)

#   #     _ ->
#   #       [
#   #         %Actions.Unknown{
#   #           description: "Unknown SPL Token action: #{instruction_type}",
#   #           details: %{instruction_type: instruction_type}
#   #         }
#   #       ]
#   #   end
#   # end

#   # defp analyze_initialize_mint(invocation, _confirmed_transaction) do
#   #   %Actions.InitializeMint{
#   #     mint: Enum.at(invocation.accounts, 0).key,
#   #     decimals: Map.get(invocation.params, :decimals),
#   #     mint_authority: Map.get(invocation.params, :mintAuthority),
#   #     freeze_authority: Map.get(invocation.params, :freezeAuthority)
#   #   }
#   # end

#   # defp analyze_initialize_account(invocation, _confirmed_transaction) do
#   #   %Actions.InitializeAccount{
#   #     account: Enum.at(invocation.accounts, 0).key,
#   #     mint: Enum.at(invocation.accounts, 1).key,
#   #     owner: Enum.at(invocation.accounts, 2).key
#   #   }
#   # end

#   # defp analyze_initialize_multisig(invocation, _confirmed_transaction) do
#   #   %Actions.InitializeMultisig{
#   #     multisig: Enum.at(invocation.accounts, 0).key,
#   #     m: Map.get(invocation.params, :m)
#   #   }
#   # end

#   def analyze_transfer(invocation, _confirmed_transaction) do
#     %Actions.TokenTransfer{
#       amount: Map.get(invocation.params, :amount),
#       source: Enum.at(invocation.accounts, 0).key,
#       destination: Enum.at(invocation.accounts, 1).key,
#       authority: Enum.at(invocation.accounts, 2).key
#     }
#   end

#   def analyze_get_account_data_size(invocation, _confirmed_transaction) do
#     %Actions.GetAccountDataSize{
#       account: Enum.at(invocation.accounts, 0).key
#     }
#   end

#   # defp analyze_approve(invocation, _confirmed_transaction) do
#   #   %Actions.ApproveTokenDelegate{
#   #     amount: Map.get(invocation.params, :amount),
#   #     token: Enum.at(invocation.accounts, 0).key,
#   #     delegate: Enum.at(invocation.accounts, 1).key,
#   #     owner: Enum.at(invocation.accounts, 2).key
#   #   }
#   # end

#   # defp analyze_revoke(invocation, _confirmed_transaction) do
#   #   %Actions.RevokeTokenDelegate{
#   #     token: Enum.at(invocation.accounts, 0).key,
#   #     owner: Enum.at(invocation.accounts, 1).key
#   #   }
#   # end

#   # defp analyze_set_authority(invocation, _confirmed_transaction) do
#   #   %Actions.SetTokenAuthority{
#   #     token: Enum.at(invocation.accounts, 0).key,
#   #     authority_type: Map.get(invocation.params, :authorityType),
#   #     new_authority: Map.get(invocation.params, :newAuthority)
#   #   }
#   # end

#   # defp analyze_mint_to(invocation, _confirmed_transaction) do
#   #   %Actions.MintTokens{
#   #     amount: Map.get(invocation.params, :amount),
#   #     token: Enum.at(invocation.accounts, 0).key,
#   #     recipient: Enum.at(invocation.accounts, 1).key
#   #   }
#   # end

#   # defp analyze_burn(invocation, _confirmed_transaction) do
#   #   %Actions.BurnTokens{
#   #     amount: Map.get(invocation.params, :amount),
#   #     token: Enum.at(invocation.accounts, 1).key,
#   #     account: Enum.at(invocation.accounts, 0).key
#   #   }
#   # end

#   # defp analyze_close_account(invocation, _confirmed_transaction) do
#   #   %Actions.CloseTokenAccount{
#   #     account: Enum.at(invocation.accounts, 0).key,
#   #     token: Enum.at(invocation.accounts, 1).key
#   #   }
#   # end

#   # defp analyze_freeze_account(invocation, _confirmed_transaction) do
#   #   %Actions.FreezeTokenAccount{
#   #     account: Enum.at(invocation.accounts, 0).key,
#   #     token: Enum.at(invocation.accounts, 1).key
#   #   }
#   # end

#   # defp analyze_thaw_account(invocation, _confirmed_transaction) do
#   #   %Actions.ThawTokenAccount{
#   #     account: Enum.at(invocation.accounts, 0).key,
#   #     token: Enum.at(invocation.accounts, 1).key
#   #   }
#   # end
# end
