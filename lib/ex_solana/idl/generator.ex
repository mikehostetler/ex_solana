# defmodule ExSolana.IDL.Generator do
#   alias ExSolana.IDL.Core
#   alias ExSolana.IDL.Generator.Errors
#   alias ExSolana.IDL.Generator.Accounts
#   alias ExSolana.IDL.Generator.Instructions

#   @type generate_options :: [
#           base_path: String.t(),
#           module_name: atom(),
#           generate_accounts: boolean(),
#           generate_instructions: boolean(),
#           generate_types: boolean(),
#           generate_errors: boolean(),
#           generate_events: boolean(),
#           generate_constants: boolean()
#         ]

#   @type generated_file :: {String.t(), String.t()}

#   @spec generate(Core.idl(), generate_options()) ::
#           {:ok, [generated_file()]} | {:error, String.t()}
#   def generate(idl, opts \\ []) do
#     base_module = opts[:module_name] || module_name_from_idl(idl)
#     base_path = opts[:base_path] || "lib/generated"

#     files =
#       [
#         generate_main_module(idl, base_module, base_path),
#         generate_component_file(
#           idl.accounts,
#           opts,
#           base_module,
#           base_path,
#           :accounts,
#           &Accounts.generate/1
#         ),
#         generate_component_file(
#           idl.instructions,
#           opts,
#           base_module,
#           base_path,
#           :instructions,
#           &Instructions.generate/1
#         ),
#         generate_component_file(
#           idl.types,
#           opts,
#           base_module,
#           base_path,
#           :types,
#           &generate_types/1
#         ),
#         generate_component_file(
#           idl.errors,
#           opts,
#           base_module,
#           base_path,
#           :errors,
#           &Errors.generate/1
#         ),
#         generate_component_file(
#           idl.events,
#           opts,
#           base_module,
#           base_path,
#           :events,
#           &generate_events/1
#         ),
#         generate_component_file(
#           idl.constants,
#           opts,
#           base_module,
#           base_path,
#           :constants,
#           &generate_constants/1
#         )
#       ]
#       |> List.flatten()
#       |> Enum.reject(fn {_, content} -> is_nil(content) end)

#     {:ok, files}
#   end

#   defp module_name_from_idl(%Core{name: name}) do
#     name
#     |> String.split("_")
#     |> Enum.map(&String.capitalize/1)
#     |> Enum.join("")
#     |> then(&"ExSolana.Generated.#{&1}")
#   end

#   defp generate_main_module(idl, base_module, base_path) do
#     content = """
#     defmodule #{base_module} do
#       @moduledoc \"\"\"
#       Generated Elixir module for Solana program: #{idl.name}
#       Version: #{idl.version}
#       \"\"\"

#       # use ExSolana.IDL

#       #{generate_program_id(idl)}
#     end
#     """

#     file_path = Path.join([base_path, "#{Macro.underscore(base_module)}.ex"])
#     {file_path, content}
#   end

#   defp generate_component_file(data, opts, base_module, base_path, component, generate_fn) do
#     if Keyword.get(opts, :"generate_#{component}", true) and not is_nil(data) do
#       content = generate_fn.(data)
#       module_name = :"#{base_module}.#{Macro.camelize(to_string(component))}"

#       file_content = """
#       defmodule #{module_name} do
#         @moduledoc \"\"\"
#         Generated #{Macro.camelize(to_string(component))} for #{base_module}
#         \"\"\"

#         #{content}
#       end
#       """

#       file_path = Path.join([base_path, "#{Macro.underscore(to_string(module_name))}.ex"])
#       {file_path, file_content}
#     else
#       []
#     end
#   end

#   defp generate_program_id(%Core{metadata: metadata}) do
#     case metadata do
#       %{address: address} when is_binary(address) -> "@program_id \"#{address}\""
#       _ -> ""
#     end
#   end

#   # defp generate_instructions(instructions),
#   #   do: "# TODO: Generate instructions\n#{inspect(instructions, pretty: true)}"

#   defp generate_types(types), do: "# TODO: Generate types\n#{inspect(types, pretty: true)}"

#   # defp generate_errors(errors) when is_list(errors) do
#   #   errors_map = generate_errors_map(errors)
#   #   functions = generate_error_functions()

#   #   """
#   #   @errors #{inspect(errors_map, pretty: true)}

#   #   #{functions}
#   #   """
#   # end

#   # defp generate_errors(_), do: nil

#   # defp generate_errors_map(errors) do
#   #   errors
#   #   |> Enum.map(fn %{code: code, name: name, msg: msg} ->
#   #     {code, {String.to_atom(Macro.underscore(name)), msg || name}}
#   #   end)
#   #   |> Enum.into(%{})
#   # end

#   # defp generate_error_functions do
#   #   """
#   #   @doc \"\"\"
#   #   Returns the error details for a given error code.

#   #   ## Parameters

#   #   - `code`: The error code (integer)

#   #   ## Returns

#   #   A tuple containing `{:ok, {name, message}}` if the error code is found,
#   #   or `:error` if the code is not recognized.

#   #   ## Examples

#   #       iex> ErrorModule.get(0)
#   #       {:ok, {:"error_name", "Error message"}}

#   #       iex> ErrorModule.get(999)
#   #       :error
#   #   \"\"\"
#   #   def get(code) when is_integer(code) do
#   #     case Map.get(@errors, code) do
#   #       {name, message} -> {:ok, {name, message}}
#   #       nil -> :error
#   #     end
#   #   end

#   #   @doc \"\"\"
#   #   Returns the error message for a given error code.

#   #   ## Parameters

#   #   - `code`: The error code (integer)

#   #   ## Returns

#   #   The error message as a string if the error code is found,
#   #   or `"Unknown error"` if the code is not recognized.

#   #   ## Examples

#   #       iex> ErrorModule.message(0)
#   #       "Error message"

#   #       iex> ErrorModule.message(999)
#   #       "Unknown error"
#   #   \"\"\"
#   #   def message(code) when is_integer(code) do
#   #     case get(code) do
#   #       {:ok, {_, message}} -> message
#   #       :error -> "Unknown error"
#   #     end
#   #   end

#   #   @doc \"\"\"
#   #   Returns the error name for a given error code.

#   #   ## Parameters

#   #   - `code`: The error code (integer)

#   #   ## Returns

#   #   The error name as an atom if the error code is found,
#   #   or `:unknown_error` if the code is not recognized.

#   #   ## Examples

#   #       iex> ErrorModule.name(0)
#   #       :"error_name"

#   #       iex> ErrorModule.name(999)
#   #       :unknown_error
#   #   \"\"\"
#   #   def name(code) when is_integer(code) do
#   #     case get(code) do
#   #       {:ok, {name, _}} -> name
#   #       :error -> :unknown_error
#   #     end
#   #   end

#   #   @doc \"\"\"
#   #   Returns a list of all error codes.

#   #   ## Returns

#   #   A list of all error codes as integers.

#   #   ## Examples

#   #       iex> ErrorModule.codes()
#   #       [0, 1, 2, ...]
#   #   \"\"\"
#   #   def codes, do: Map.keys(@errors)

#   #   @doc \"\"\"
#   #   Returns a list of all error names.

#   #   ## Returns

#   #   A list of all error names as atoms.

#   #   ## Examples

#   #       iex> ErrorModule.names()
#   #       [:"error_name_1", :"error_name_2", ...]
#   #   \"\"\"
#   #   def names, do: @errors |> Map.values() |> Enum.map(fn {name, _} -> name end)
#   #   """
#   # end

#   defp generate_events(events), do: "# TODO: Generate events\n#{inspect(events, pretty: true)}"

#   defp generate_constants(constants),
#     do: "# TODO: Generate constants\n#{inspect(constants, pretty: true)}"
# end
