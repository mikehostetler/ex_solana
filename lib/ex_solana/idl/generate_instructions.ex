# defmodule ExSolana.IDL.Generator.Instructions do
#   @moduledoc false

#   require Logger

#   def generate(instructions) when is_list(instructions) do
#     instructions
#     |> Enum.map(&generate_instruction/1)
#     |> Enum.join("\n\n")
#   end

#   def generate(_), do: nil

#   defp generate_instruction(instruction) do
#     schema = generate_schema(instruction)
#     function_name = Macro.underscore(instruction.name)

#     """
#     @#{function_name}_schema #{inspect(schema)}

#     @doc \"\"\"
#     Creates the instructions for the `#{instruction.name}` operation.

#     ## Options

#     #{NimbleOptions.docs(schema)}
#     \"\"\"
#     def #{function_name}(opts) do
#       case validate(opts, @#{function_name}_schema) do
#         {:ok, params} ->
#           %Instruction{
#             program: id(),
#             accounts: [
#               #{generate_accounts(instruction.accounts)}
#             ],
#             data: Instruction.encode_data([
#               #{generate_data(instruction)}
#             ])
#           }

#         error ->
#           error
#       end
#     end
#     """
#   end

#   defp generate_schema(instruction) do
#     instruction.accounts
#     |> Enum.map(&generate_account_schema/1)
#     |> Enum.concat(generate_args_schema(instruction.args))
#   end

#   defp generate_account_schema(account) do
#     {String.to_atom(account.name),
#      [
#        type: {:custom, ExSolana.Key, :check, []},
#        required: true,
#        doc: account_doc(account)
#      ]}
#   end

#   defp account_doc(account) do
#     base_doc = account.name
#     mut_doc = if account.isMut, do: " (writable)", else: ""
#     signer_doc = if account.isSigner, do: " (signer)", else: ""
#     base_doc <> mut_doc <> signer_doc
#   end

#   defp generate_args_schema(args) do
#     args
#     |> Enum.map(fn arg ->
#       {String.to_atom(arg.name),
#        [
#          type: map_type(arg.type),
#          required: true,
#          doc: arg.name
#        ]}
#     end)
#   end

#   defp map_type("u8"), do: :non_neg_integer
#   defp map_type("u16"), do: :non_neg_integer
#   defp map_type("u32"), do: :non_neg_integer
#   defp map_type("u64"), do: :non_neg_integer
#   defp map_type("i8"), do: :integer
#   defp map_type("i16"), do: :integer
#   defp map_type("i32"), do: :integer
#   defp map_type("i64"), do: :integer
#   defp map_type("f32"), do: :float
#   defp map_type("f64"), do: :float
#   defp map_type("bool"), do: :boolean
#   defp map_type("string"), do: :string
#   defp map_type("publicKey"), do: {:custom, ExSolana.Key, :check, []}
#   defp map_type(_), do: :any

#   defp generate_accounts(accounts) do
#     accounts
#     |> Enum.map_join(",\n      ", fn account ->
#       "%Account{key: params.#{account.name}, writable?: #{account.isMut}, signer?: #{account.isSigner}}"
#     end)
#   end

#   defp generate_data(instruction) do
#     [generate_discriminator(instruction) | generate_args(instruction.args)]
#     |> Enum.join(",\n      ")
#   end

#   defp generate_discriminator(instruction) do
#     case instruction.discriminator do
#       [discriminator] when is_integer(discriminator) ->
#         "#{discriminator}"

#       discriminator when is_list(discriminator) ->
#         "{#{Enum.join(discriminator, ", ")}, :discriminator}"

#       _ ->
#         Logger.warning("Unexpected discriminator format for instruction: #{instruction.name}")
#         "0"
#     end
#   end

#   defp generate_args(args) do
#     args
#     |> Enum.map(fn arg ->
#       case arg.type do
#         "u64" -> "{params.#{arg.name}, 64}"
#         _ -> "params.#{arg.name}"
#       end
#     end)
#   end
# end
