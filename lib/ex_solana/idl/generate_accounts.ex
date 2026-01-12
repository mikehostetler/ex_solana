# defmodule ExSolana.IDL.Generator.Accounts do
#   @moduledoc """
#   Generator module for Solana IDL account structures.

#   This module is responsible for generating Elixir code representations
#   of Solana program account types defined in the IDL.
#   """

#   # Implement these functions to generate specific components
#   def generate(accounts) when is_list(accounts) do
#     account_modules = Enum.map(accounts, &generate_account_module/1)

#     """
#     defmodule Account do
#       @moduledoc \"\"\"
#       Generated account structs and decoding functions for the program.
#       \"\"\"

#       #{Enum.join(account_modules, "\n\n")}

#       @doc \"\"\"
#       Decodes an account based on its discriminator.
#       \"\"\"
#       def decode(data) do
#         <<discriminator::binary-size(8), rest::binary>> = data
#         case discriminator do
#           #{Enum.map(accounts, &generate_account_match/1)}
#           _ -> {:error, :unknown_account}
#         end
#       end
#     end
#     """
#   end

#   def generate(_), do: nil

#   defp generate_account_module(account) do
#     %{name: name, type: %{fields: fields}} = account
#     module_name = Macro.camelize(name)
#     struct_fields = Enum.map(fields, fn %{name: field_name} -> "#{field_name}: nil" end)
#     decode_map = generate_decode_map(fields)

#     """
#     defmodule #{module_name} do
#       @moduledoc \"\"\"
#       Account struct and decoding function for #{name}.
#       \"\"\"

#       defstruct [#{Enum.join(struct_fields, ", ")}]

#       @decode_map #{inspect(decode_map, pretty: true)}

#       def decode(data) do
#         {struct, _rest} = ExSolana.BinaryDecoder.decode_with_map(data, @decode_map, __MODULE__)
#         {:ok, struct}
#       end
#     end
#     """
#   end

#   defp generate_decode_map(fields) do
#     fields
#     |> Enum.map(fn %{name: name, type: type} -> {String.to_atom(name), translate_type(type)} end)
#     |> Enum.into(%{})
#   end

#   defp translate_type("u8"), do: {:u, 8}
#   defp translate_type("u16"), do: {:u, 16}
#   defp translate_type("u32"), do: {:u, 32}
#   defp translate_type("u64"), do: {:u, 64}
#   defp translate_type("u128"), do: {:u, 128}
#   defp translate_type("i8"), do: {:i, 8}
#   defp translate_type("i16"), do: {:i, 16}
#   defp translate_type("i32"), do: {:i, 32}
#   defp translate_type("i64"), do: {:i, 64}
#   defp translate_type("i128"), do: {:i, 128}
#   defp translate_type("bool"), do: :bool
#   defp translate_type("string"), do: :string
#   defp translate_type("publicKey"), do: {:bytes, 32}
#   defp translate_type(%{array: [type, size]}), do: {:array, translate_type(type), size}
#   defp translate_type(%{vec: type}), do: {:vec, translate_type(type)}
#   defp translate_type(%{option: type}), do: {:option, translate_type(type)}
#   defp translate_type(%{defined: type}), do: {:defined, String.to_atom(type)}

#   defp generate_account_match(%{name: name, discriminator: discriminator}) do
#     module_name = Macro.camelize(name)
#     "<<#{format_discriminator(discriminator)}>> -> #{module_name}.decode(rest)"
#   end

#   defp format_discriminator(discriminator) when is_list(discriminator) do
#     discriminator
#     |> Enum.map(&to_string/1)
#     |> Enum.join(", ")
#   end

#   defp format_discriminator(discriminator) when is_integer(discriminator) do
#     to_string(discriminator)
#   end

#   defp format_discriminator(nil), do: ""
# end
