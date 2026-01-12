# defmodule ExSolana.Native.SystemProgram.Parser do
#   @behaviour ExSolana.ProgramParser

#   alias ExSolana.Native.SystemProgram
#   alias ExSolana.Key

#   @create_account 0
#   @assign 1
#   @transfer 2
#   @create_account_with_seed 3
#   @advance_nonce_account 4
#   @withdraw_nonce_account 5
#   @initialize_nonce_account 6
#   @authorize_nonce_account 7
#   @allocate 8
#   @allocate_with_seed 9
#   @assign_with_seed 10
#   @transfer_with_seed 11

#   @impl ExSolana.ProgramParser
#   def parse_invocation(invocation) do
#     case parse_instruction(invocation.data) do
#       {:ok, instruction_type, parsed_data} ->
#         {:ok,
#          %{
#            program: :system,
#            type: instruction_type,
#            data: parsed_data,
#            accounts: parse_accounts(invocation.accounts, instruction_type)
#          }}

#       {:error, reason} ->
#         {:error, reason}
#     end
#   end

#   @impl ExSolana.ProgramParser
#   def program_id, do: SystemProgram.id()

#   defp parse_instruction(<<instruction_type::little-integer-32, rest::binary>>) do
#     case instruction_type do
#       @create_account -> parse_create_account(rest)
#       @assign -> parse_assign(rest)
#       @transfer -> parse_transfer(rest)
#       @create_account_with_seed -> parse_create_account_with_seed(rest)
#       @allocate -> parse_allocate(rest)
#       @allocate_with_seed -> parse_allocate_with_seed(rest)
#       @assign_with_seed -> parse_assign_with_seed(rest)
#       @transfer_with_seed -> parse_transfer_with_seed(rest)
#       _ -> {:error, :unknown_instruction}
#     end
#   end

#   defp parse_create_account(
#          <<lamports::little-integer-64, space::little-integer-64, owner::binary-32>>
#        ) do
#     {:ok, :create_account,
#      %{
#        lamports: lamports,
#        space: space,
#        owner: Key.to_base58(owner)
#      }}
#   end

#   defp parse_assign(<<owner::binary-32>>) do
#     {:ok, :assign,
#      %{
#        owner: Key.to_base58(owner)
#      }}
#   end

#   defp parse_transfer(<<lamports::little-integer-64>>) do
#     {:ok, :transfer,
#      %{
#        lamports: lamports
#      }}
#   end

#   defp parse_create_account_with_seed(
#          <<base::binary-32, seed_len::little-integer-64, seed::binary-size(seed_len),
#            lamports::little-integer-64, space::little-integer-64, owner::binary-32>>
#        ) do
#     {:ok, :create_account_with_seed,
#      %{
#        base: Key.to_base58(base),
#        seed: seed,
#        lamports: lamports,
#        space: space,
#        owner: Key.to_base58(owner)
#      }}
#   end

#   defp parse_allocate(<<space::little-integer-64>>) do
#     {:ok, :allocate,
#      %{
#        space: space
#      }}
#   end

#   defp parse_allocate_with_seed(
#          <<base::binary-32, seed_len::little-integer-64, seed::binary-size(seed_len),
#            space::little-integer-64, owner::binary-32>>
#        ) do
#     {:ok, :allocate_with_seed,
#      %{
#        base: Key.to_base58(base),
#        seed: seed,
#        space: space,
#        owner: Key.to_base58(owner)
#      }}
#   end

#   defp parse_assign_with_seed(
#          <<base::binary-32, seed_len::little-integer-64, seed::binary-size(seed_len),
#            owner::binary-32>>
#        ) do
#     {:ok, :assign_with_seed,
#      %{
#        base: Key.to_base58(base),
#        seed: seed,
#        owner: Key.to_base58(owner)
#      }}
#   end

#   defp parse_transfer_with_seed(
#          <<lamports::little-integer-64, seed_len::little-integer-64, seed::binary-size(seed_len),
#            program_id::binary-32>>
#        ) do
#     {:ok, :transfer_with_seed,
#      %{
#        lamports: lamports,
#        seed: seed,
#        program_id: Key.to_base58(program_id)
#      }}
#   end

#   defp parse_accounts(accounts, instruction_type) do
#     account_roles = get_account_roles(instruction_type)

#     Enum.zip(accounts, account_roles)
#     |> Enum.map(fn {account, role} ->
#       %{pubkey: Key.to_base58(account.pubkey), role: role}
#     end)
#   end

#   defp get_account_roles(:create_account), do: [:from, :new]
#   defp get_account_roles(:assign), do: [:assigned]
#   defp get_account_roles(:transfer), do: [:from, :to]
#   defp get_account_roles(:create_account_with_seed), do: [:from, :to, :base]
#   defp get_account_roles(:allocate), do: [:allocated]
#   defp get_account_roles(:allocate_with_seed), do: [:allocated, :base]
#   defp get_account_roles(:assign_with_seed), do: [:assigned, :base]
#   defp get_account_roles(:transfer_with_seed), do: [:from, :base, :to]
#   defp get_account_roles(_), do: []
# end
