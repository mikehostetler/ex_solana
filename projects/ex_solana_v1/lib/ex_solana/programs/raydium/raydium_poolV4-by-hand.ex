# defmodule ExSolana.Program.Raydium.PoolV4 do
#   @moduledoc """
#   Raydium V4 Pool
#   """
#   @behaviour ExSolana.ProgramBehaviour

#   alias ExSolana.Actions
#   alias ExSolana.Transaction.Core

#   require IEx
#   require Logger

#   # Define instruction types and their discriminants
#   @instructions %{
#     0 => :initialize,
#     1 => :initialize2,
#     2 => :monitor_step,
#     3 => :deposit,
#     4 => :withdraw,
#     5 => :migrate_to_open_book,
#     6 => :set_params,
#     7 => :withdraw_pnl,
#     8 => :withdraw_srm,
#     9 => :swap_base_in,
#     10 => :pre_initialize,
#     11 => :swap_base_out,
#     12 => :simulate_info,
#     13 => :admin_cancel_orders,
#     14 => :create_config_account,
#     15 => :update_config_account
#   }

#   # Error codes and other constants remain unchanged...
#   # @errors %{
#   #   0 => {:already_in_use, "AlreadyInUse"},
#   #   1 => {:invalid_program_address, "InvalidProgramAddress"},
#   #   2 => {:expected_mint, "ExpectedMint"},
#   #   3 => {:expected_account, "ExpectedAccount"},
#   #   4 => {:invalid_coin_vault, "InvalidCoinVault"},
#   #   5 => {:invalid_pc_vault, "InvalidPCVault"},
#   #   6 => {:invalid_token_lp, "InvalidTokenLP"},
#   #   7 => {:invalid_dest_token_coin, "InvalidDestTokenCoin"},
#   #   8 => {:invalid_dest_token_pc, "InvalidDestTokenPC"},
#   #   9 => {:invalid_pool_mint, "InvalidPoolMint"},
#   #   10 => {:invalid_open_orders, "InvalidOpenOrders"},
#   #   11 => {:invalid_serum_market, "InvalidSerumMarket"},
#   #   12 => {:invalid_serum_program, "InvalidSerumProgram"},
#   #   13 => {:invalid_target_orders, "InvalidTargetOrders"},
#   #   14 => {:invalid_withdraw_queue, "InvalidWithdrawQueue"},
#   #   15 => {:invalid_temp_lp, "InvalidTempLp"},
#   #   16 => {:invalid_coin_mint, "InvalidCoinMint"},
#   #   17 => {:invalid_pc_mint, "InvalidPCMint"},
#   #   18 => {:invalid_owner, "InvalidOwner"},
#   #   19 => {:invalid_supply, "InvalidSupply"},
#   #   20 => {:invalid_delegate, "InvalidDelegate"},
#   #   21 => {:invalid_sign_account, "Invalid Sign Account"},
#   #   22 => {:invalid_status, "InvalidStatus"},
#   #   23 => {:invalid_instruction, "Invalid instruction"},
#   #   24 => {:wrong_accounts_number, "Wrong accounts number"},
#   #   25 => {:withdraw_transfer_busy, "Withdraw_transfer is busy"},
#   #   26 => {:withdraw_queue_full, "WithdrawQueue is full"},
#   #   27 => {:withdraw_queue_empty, "WithdrawQueue is empty"},
#   #   28 => {:invalid_params_set, "Params Set is invalid"},
#   #   29 => {:invalid_input, "InvalidInput"},
#   #   30 => {:exceeded_slippage, "instruction exceeds desired slippage limit"},
#   #   31 => {:calculation_ex_rate_failure, "CalculationExRateFailure"},
#   #   32 => {:checked_sub_overflow, "Checked_Sub Overflow"},
#   #   33 => {:checked_add_overflow, "Checked_Add Overflow"},
#   #   34 => {:checked_mul_overflow, "Checked_Mul Overflow"},
#   #   35 => {:checked_div_overflow, "Checked_Div Overflow"},
#   #   36 => {:checked_empty_funds, "Empty Funds"},
#   #   37 => {:calc_pnl_error, "Calc pnl error"},
#   #   38 => {:invalid_spl_token_program, "InvalidSplTokenProgram"},
#   #   39 => {:take_pnl_error, "Take Pnl error"},
#   #   40 => {:insufficient_funds, "Insufficient funds"},
#   #   41 => {:conversion_failure, "Conversion to u64 failed with an overflow or underflow"},
#   #   42 => {:invalid_user_token, "user token input does not match amm"},
#   #   43 => {:invalid_srm_mint, "InvalidSrmMint"},
#   #   44 => {:invalid_srm_token, "InvalidSrmToken"},
#   #   45 => {:too_many_open_orders, "TooManyOpenOrders"},
#   #   46 => {:order_at_slot_is_placed, "OrderAtSlotIsPlaced"},
#   #   47 => {:invalid_sys_program_address, "InvalidSysProgramAddress"},
#   #   48 => {:invalid_fee, "The provided fee does not match the program owner's constraints"},
#   #   49 => {:repeat_create_amm, "Repeat create amm about market"},
#   #   50 => {:not_allow_zero_lp, "Not allow Zero LP"},
#   #   51 => {:invalid_close_authority, "Token account has a close authority"},
#   #   52 => {:invalid_freeze_authority, "Pool token mint has a freeze authority"},
#   #   53 => {:invalid_refer_pc_mint, "InvalidReferPCMint"},
#   #   54 => {:invalid_config_account, "InvalidConfigAccount"},
#   #   55 => {:repeat_create_config_account, "Repeat create staking config account"},
#   #   56 => {:unknown_amm_error, "Unknown Amm Error"}
#   # }

#   @log_events %{
#     0 => :init,
#     1 => :deposit,
#     2 => :withdraw,
#     3 => :swap_base_in,
#     4 => :swap_base_out
#   }

#   @impl ExSolana.ProgramBehaviour
#   def id, do: "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8"

#   @impl ExSolana.ProgramBehaviour
#   def decode_instruction(data) do
#     ExSolana.Program.Raydium.PoolV4.DecodeInstruction.decode_instruction(data, @instructions)
#   end

#   @impl ExSolana.ProgramBehaviour
#   def decode_events(logs) do
#     ExSolana.Program.Raydium.PoolV4.DecodeEvents.decode_events(logs, @log_events)
#   end

#   def analyze_invocation(%Core.Invocation{instruction: :swap_base_in} = invocation, confirmed_transaction) do
#     with {:ok, amount_out} <- get_amount(invocation.inner_invocations, 0),
#          {:ok, amount_in} <- get_amount(invocation.inner_invocations, 1),
#          {:ok, owner} <- get_account_key(invocation.accounts, 17),
#          {:ok, pool_address} <- get_account_key(invocation.accounts, 1),
#          {:ok, token_balance_changes} <- get_token_balance_changes(confirmed_transaction),
#          {:ok, to_token, to_token_decimals} <- find_to_token(amount_out, token_balance_changes) do
#       action = %Actions.TokenSwap{
#         slot: confirmed_transaction.slot,
#         owner: owner,
#         to_token: B58.encode58(ExSolana.sol()),
#         to_token_decimals: 9,
#         from_token: to_token,
#         from_token_decimals: to_token_decimals,
#         pool_address: pool_address,
#         amount_out: amount_out,
#         amount_in: amount_in,
#         price: calculate_price(amount_in, amount_out),
#         fee: confirmed_transaction.additional.fee
#       }

#       {:ok, action}
#     end
#   end

#   @impl true
#   def analyze_invocation(%Core.Invocation{instruction: :swap_base_out} = invocation, confirmed_transaction) do
#     with {:ok, amount_out} <- get_amount(invocation.inner_invocations, 0),
#          {:ok, amount_in} <- get_amount(invocation.inner_invocations, 1),
#          {:ok, owner} <- get_account_key(invocation.accounts, 17),
#          {:ok, pool_address} <- get_account_key(invocation.accounts, 1),
#          {:ok, token_balance_changes} <- get_token_balance_changes(confirmed_transaction),
#          {:ok, to_token, to_token_decimals} <- find_to_token(amount_in, token_balance_changes) do
#       action = %Actions.TokenSwap{
#         slot: confirmed_transaction.slot,
#         owner: owner,
#         from_token: B58.encode58(ExSolana.sol()),
#         from_token_decimals: 9,
#         to_token: to_token,
#         to_token_decimals: to_token_decimals,
#         pool_address: pool_address,
#         amount_in: amount_in,
#         amount_out: amount_out,
#         price: calculate_price(amount_in, amount_out),
#         fee: confirmed_transaction.additional.fee
#       }

#       {:ok, action}
#     end
#   end

#   @impl true
#   def analyze_invocation(%Core.Invocation{instruction: :unknown_instruction}, _decoded_txn) do
#     {:ok,
#      [
#        %Actions.Unknown{
#          description: "Unknown Raydium instruction",
#          details: %{}
#        }
#      ]}
#   end

#   @impl true
#   def analyze_invocation(%Core.Invocation{instruction: :error_decoding_instruction}, _decoded_txn) do
#     {:ok,
#      [
#        %Actions.Unknown{
#          description: "Error decoding Raydium instruction",
#          details: %{}
#        }
#      ]}
#   end

#   @impl true
#   def analyze_invocation(_invocation, _decoded_txn), do: {:ok, []}

#   defp get_amount(inner_invocations, index) do
#     case Enum.at(inner_invocations, index) do
#       %{params: %{amount: amount}} when is_number(amount) -> {:ok, amount}
#       _ -> {:error, "Invalid amount at index #{index}"}
#     end
#   end

#   defp get_account_key(accounts, index) do
#     case Enum.at(accounts, index) do
#       %{key: key} when is_binary(key) -> {:ok, key}
#       _ -> {:error, "Invalid account key at index #{index}"}
#     end
#   end

#   defp get_token_balance_changes(%{additional: %{token_balance_changes: changes}}) when is_list(changes),
#     do: {:ok, changes}

#   defp get_token_balance_changes(_), do: {:error, "Invalid token balance changes"}

#   defp find_to_token(amount, token_balance_changes) do
#     case Enum.find(token_balance_changes, fn change -> change.change == amount end) do
#       %{token_mint_address: address, ui_amount_after: %{decimals: decimals}} ->
#         {:ok, address, decimals}

#       _ ->
#         {:error, "Token not found for amount #{amount}"}
#     end
#   end

#   defp calculate_price(amount_in, amount_out) when is_number(amount_in) and is_number(amount_out) and amount_out != 0 do
#     Decimal.div(Decimal.new(amount_in), Decimal.new(amount_out))
#   end

#   defp calculate_price(_, _), do: Decimal.new(0)
# end
