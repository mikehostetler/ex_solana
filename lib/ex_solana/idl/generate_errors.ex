# defmodule ExSolana.IDL.Generator.Errors do
#   def generate(errors) when is_list(errors) do
#     errors_map = generate_errors_map(errors)
#     functions = generate_error_functions()

#     """
#     @errors #{inspect(errors_map, pretty: true)}

#     #{functions}
#     """
#   end

#   def generate(_), do: nil

#   defp generate_errors_map(errors) do
#     errors
#     |> Enum.map(fn %{code: code, name: name, msg: msg} ->
#       {code, {String.to_atom(Macro.underscore(name)), msg || name}}
#     end)
#     |> Enum.into(%{})
#   end

#   defp generate_error_functions do
#     """
#     @doc \"\"\"
#     Returns the error details for a given error code.

#     ## Parameters

#     - `code`: The error code (integer)

#     ## Returns

#     A tuple containing `{:ok, {name, message}}` if the error code is found,
#     or `:error` if the code is not recognized.

#     ## Examples

#         iex> ErrorModule.get(0)
#         {:ok, {:"error_name", "Error message"}}

#         iex> ErrorModule.get(999)
#         :error
#     \"\"\"
#     def get(code) when is_integer(code) do
#       case Map.get(@errors, code) do
#         {name, message} -> {:ok, {name, message}}
#         nil -> :error
#       end
#     end

#     @doc \"\"\"
#     Returns the error message for a given error code.

#     ## Parameters

#     - `code`: The error code (integer)

#     ## Returns

#     The error message as a string if the error code is found,
#     or `"Unknown error"` if the code is not recognized.

#     ## Examples

#         iex> ErrorModule.message(0)
#         "Error message"

#         iex> ErrorModule.message(999)
#         "Unknown error"
#     \"\"\"
#     def message(code) when is_integer(code) do
#       case get(code) do
#         {:ok, {_, message}} -> message
#         :error -> "Unknown error"
#       end
#     end

#     @doc \"\"\"
#     Returns the error name for a given error code.

#     ## Parameters

#     - `code`: The error code (integer)

#     ## Returns

#     The error name as an atom if the error code is found,
#     or `:unknown_error` if the code is not recognized.

#     ## Examples

#         iex> ErrorModule.name(0)
#         :"error_name"

#         iex> ErrorModule.name(999)
#         :unknown_error
#     \"\"\"
#     def name(code) when is_integer(code) do
#       case get(code) do
#         {:ok, {name, _}} -> name
#         :error -> :unknown_error
#       end
#     end

#     @doc \"\"\"
#     Returns a list of all error codes.

#     ## Returns

#     A list of all error codes as integers.

#     ## Examples

#         iex> ErrorModule.codes()
#         [0, 1, 2, ...]
#     \"\"\"
#     def codes, do: Map.keys(@errors)

#     @doc \"\"\"
#     Returns a list of all error names.

#     ## Returns

#     A list of all error names as atoms.

#     ## Examples

#         iex> ErrorModule.names()
#         [:"error_name_1", :"error_name_2", ...]
#     \"\"\"
#     def names, do: @errors |> Map.values() |> Enum.map(fn {name, _} -> name end)
#     """
#   end
# end
