# defmodule ExSolana.IDL do
#   @moduledoc """
#   Main module for generating Elixir code from Solana IDL.
#   """

#   alias ExSolana.IDL.{Core, Parser, Generator}

#   @type generate_options :: [
#           output_path: String.t(),
#           module_name: atom(),
#           generate_accounts: boolean(),
#           generate_instructions: boolean(),
#           generate_types: boolean(),
#           generate_errors: boolean(),
#           generate_events: boolean(),
#           generate_constants: boolean()
#         ]

#   @doc """
#   Loads an IDL from a file, parses it, and generates Elixir code.

#   ## Parameters

#   - `file_path`: Path to the IDL JSON file.
#   - `opts`: Options for code generation. See `t:generate_options/0`.

#   ## Options

#   - `:output_path` - Path to save the generated code. If not provided, code is returned as a string.
#   - `:module_name` - Name of the generated module. Defaults to a name based on the IDL name.
#   - `:generate_accounts` - Whether to generate account structs. Defaults to `true`.
#   - `:generate_instructions` - Whether to generate instruction functions. Defaults to `true`.
#   - `:generate_types` - Whether to generate type structs. Defaults to `true`.
#   - `:generate_errors` - Whether to generate error modules. Defaults to `true`.
#   - `:generate_events` - Whether to generate event structs. Defaults to `true`.
#   - `:generate_constants` - Whether to generate constants. Defaults to `true`.

#   ## Returns

#   - `{:ok, code}` if generation is successful and no output path is provided.
#   - `{:ok, :file_written}` if generation is successful and the code is written to a file.
#   - `{:error, reason}` if there's an error during parsing or generation.
#   """
#   @spec generate_from_file(String.t(), generate_options()) ::
#           {:ok, [String.t()]} | {:error, String.t()}
#   def generate_from_file(file_path, opts \\ []) do
#     with {:ok, idl} <- Parser.parse_file(file_path),
#          {:ok, files} <- Generator.generate(idl, opts) do
#       write_files(files)
#     end
#   end

#   @doc """
#   Generates Elixir code from a parsed IDL.

#   ## Parameters

#   - `idl`: The parsed IDL struct.
#   - `opts`: Options for code generation. See `t:generate_options/0`.

#   ## Returns

#   - `{:ok, code}` if generation is successful.
#   - `{:error, reason}` if there's an error during generation.
#   """
#   @spec generate(Core.idl(), generate_options()) :: {:ok, [String.t()]} | {:error, String.t()}
#   def generate(idl, opts \\ []) do
#     with {:ok, files} <- Generator.generate(idl, opts) do
#       write_files(files)
#     end
#   end

#   defp write_files(files) do
#     results =
#       Enum.map(files, fn {file_path, content} ->
#         dir_path = Path.dirname(file_path)
#         File.mkdir_p!(dir_path)
#         File.write(file_path, content)
#       end)

#     if Enum.all?(results, &(&1 == :ok)) do
#       {:ok, Enum.map(files, fn {file_path, _} -> file_path end)}
#     else
#       {:error, "Failed to write one or more files"}
#     end
#   end
# end
