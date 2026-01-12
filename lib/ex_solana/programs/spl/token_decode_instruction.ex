# defmodule ExSolana.SPL.Token.DecodeInstruction do
#   @moduledoc """
#   Decoder for SPL Token Program instructions
#   """

#   @instructions %{
#     0 => :initialize_mint,
#     1 => :initialize_account,
#     2 => :initialize_multisig,
#     3 => :transfer,
#     4 => :approve,
#     5 => :revoke,
#     6 => :set_authority,
#     7 => :mint_to,
#     8 => :burn,
#     9 => :close_account,
#     10 => :freeze_account,
#     11 => :thaw_account,
#     12 => :transfer_checked,
#     13 => :approve_checked,
#     14 => :mint_to_checked,
#     15 => :burn_checked,
#     16 => :initialize_account2,
#     17 => :sync_native,
#     18 => :initialize_account3,
#     19 => :initialize_multisig2,
#     20 => :initialize_mint2,
#     21 => :get_account_data_size,
#     22 => :initialize_immutable_owner,
#     23 => :amount_to_ui_amount,
#     24 => :ui_amount_to_amount
#   }

#   def decode_instruction(data) do
#     case data do
#       <<discriminant::little-unsigned-integer-size(8), rest::binary>> ->
#         instruction_type = @instructions[discriminant]
#         decode_instruction_data(instruction_type, rest)

#       _ ->
#         {:error, :invalid_instruction_data}
#     end
#   end

#   defp decode_instruction_data(
#          :initialize_mint,
#          <<decimals::8, mint_authority::binary-size(32), freeze_authority::binary>>
#        ) do
#     {:initialize_mint,
#      %{
#        decimals: decimals,
#        mint_authority: B58.encode58(mint_authority),
#        freeze_authority: decode_optional_pubkey(freeze_authority)
#      }}
#   end

#   defp decode_instruction_data(:initialize_account, _data) do
#     {:initialize_account, %{}}
#   end

#   defp decode_instruction_data(:transfer, <<amount::little-64>>) do
#     {:transfer, %{amount: amount}}
#   end

#   defp decode_instruction_data(:approve, <<amount::little-64>>) do
#     {:approve, %{amount: amount}}
#   end

#   defp decode_instruction_data(:revoke, _data) do
#     {:revoke, %{}}
#   end

#   defp decode_instruction_data(
#          :set_authority,
#          <<authority_type, has_new_authority, rest::binary>>
#        ) do
#     new_authority = if has_new_authority == 1, do: B58.encode58(rest), else: nil

#     {:set_authority,
#      %{
#        authority_type: decode_authority_type(authority_type),
#        new_authority: new_authority
#      }}
#   end

#   defp decode_instruction_data(:mint_to, <<amount::little-64>>) do
#     {:mint_to, %{amount: amount}}
#   end

#   defp decode_instruction_data(:burn, <<amount::little-64>>) do
#     {:burn, %{amount: amount}}
#   end

#   defp decode_instruction_data(:close_account, _data) do
#     {:close_account, %{}}
#   end

#   defp decode_instruction_data(:freeze_account, _data) do
#     {:freeze_account, %{}}
#   end

#   defp decode_instruction_data(:thaw_account, _data) do
#     {:thaw_account, %{}}
#   end

#   defp decode_instruction_data(:transfer_checked, <<amount::little-64, decimals::8>>) do
#     {:transfer_checked, %{amount: amount, decimals: decimals}}
#   end

#   defp decode_instruction_data(:approve_checked, <<amount::little-64, decimals::8>>) do
#     {:approve_checked, %{amount: amount, decimals: decimals}}
#   end

#   defp decode_instruction_data(:mint_to_checked, <<amount::little-64, decimals::8>>) do
#     {:mint_to_checked, %{amount: amount, decimals: decimals}}
#   end

#   defp decode_instruction_data(:burn_checked, <<amount::little-64, decimals::8>>) do
#     {:burn_checked, %{amount: amount, decimals: decimals}}
#   end

#   defp decode_instruction_data(instruction_type, _data) do
#     {instruction_type, %{}}
#   end

#   defp decode_optional_pubkey(<<0::32*8>>), do: nil
#   defp decode_optional_pubkey(pubkey), do: B58.encode58(pubkey)

#   defp decode_authority_type(0), do: :mint_tokens
#   defp decode_authority_type(1), do: :freeze_account
#   defp decode_authority_type(2), do: :account_owner
#   defp decode_authority_type(3), do: :close_account
#   defp decode_authority_type(_), do: :unknown
# end
