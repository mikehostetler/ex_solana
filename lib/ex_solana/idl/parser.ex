defmodule ExSolana.IDL.Parser do
  @moduledoc """
  Parser module for Solana IDL (Interface Definition Language).

  This module is responsible for parsing IDL JSON files and converting them
  into Elixir data structures for further processing and code generation.
  """

  alias ExSolana.IDL.Core

  require Logger

  @type parse_result :: {:ok, Core.idl()} | {:error, String.t()}

  @doc """
  Parses a Solana IDL JSON file and returns a structured Elixir representation.

  ## Parameters

  - `file_path`: Path to the IDL JSON file.

  ## Returns

  - `{:ok, idl}` if parsing is successful.
  - `{:error, reason}` if there's an error during parsing.
  """
  @spec parse_file(String.t()) :: parse_result
  def parse_file(file_path) do
    full_path = Path.join(File.cwd!(), file_path)

    with {:ok, json} <- File.read(full_path),
         {:ok, decoded} <- Jason.decode(json),
         {:ok, idl} <- parse_idl(decoded) do
      {:ok, idl}
    else
      {:error, reason} -> {:error, "Failed to parse IDL: #{inspect(reason)}"}
    end
  end

  def parse_file!(nil), do: nil

  def parse_file!(file_path) do
    case parse_file(file_path) do
      {:ok, idl} -> idl
      {:error, reason} -> raise "Failed to parse IDL: #{inspect(reason)}"
    end
  end

  def parse_idl(json) do
    with {:ok, version} <- parse_version(json["version"]),
         {:ok, name} <- parse_name(json["name"]),
         {:ok, instructions} <- parse_instructions(json["instructions"]),
         {:ok, accounts} <- parse_optional_accounts(json["accounts"]),
         {:ok, types} <- parse_optional_types(json["types"]),
         {:ok, events} <- parse_optional_events(json["events"]),
         {:ok, errors} <- parse_optional_errors(json["errors"]),
         {:ok, constants} <- parse_optional_constants(json["constants"]),
         {:ok, metadata} <- parse_optional_metadata(json["metadata"]) do
      {:ok,
       %ExSolana.IDL.Core{
         version: version,
         name: name,
         instructions: instructions,
         accounts: accounts,
         types: types,
         events: events,
         errors: errors,
         constants: constants,
         metadata: metadata
       }}
    end
  end

  # Update these functions to handle optional fields
  defp parse_optional_accounts(nil), do: {:ok, nil}
  defp parse_optional_accounts(accounts), do: parse_accounts(accounts)

  defp parse_optional_types(nil), do: {:ok, nil}
  defp parse_optional_types(types), do: parse_types(types)

  defp parse_optional_events(nil), do: {:ok, nil}
  defp parse_optional_events(events), do: parse_events(events)

  defp parse_optional_errors(nil), do: {:ok, nil}
  defp parse_optional_errors(errors), do: parse_errors(errors)

  defp parse_optional_constants(nil), do: {:ok, nil}
  defp parse_optional_constants(constants), do: parse_constants(constants)

  defp parse_optional_metadata(nil), do: {:ok, nil}
  defp parse_optional_metadata(metadata), do: parse_metadata(metadata)

  # Implement individual parsing functions for each IDL component
  defp parse_version(version) when is_binary(version) do
    if Regex.match?(
         ~r/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/,
         version
       ) do
      {:ok, version}
    else
      {:error, "Invalid semantic version format"}
    end
  end

  defp parse_version(_), do: {:error, "Invalid version format"}

  defp parse_name(name) when is_binary(name), do: {:ok, name}
  defp parse_name(_), do: {:error, "Invalid name format"}

  defp parse_instructions(instructions) when is_list(instructions) do
    parsed_instructions = Enum.map(instructions, &parse_instruction/1)

    if Enum.all?(parsed_instructions, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_instructions, fn {:ok, instr} -> instr end)}
    else
      {:error, "Failed to parse one or more instructions"}
    end
  end

  defp parse_instruction(instr) do
    with {:ok, name} <- parse_name(instr["name"]),
         {:ok, discriminator} <- parse_discriminator(instr["discriminator"]),
         {:ok, accounts} <- parse_instruction_accounts(instr["accounts"]),
         {:ok, args} <- parse_instruction_args(instr["args"]),
         {:ok, docs} <- parse_optional_docs(instr["docs"]),
         {:ok, returns} <- parse_optional_type(instr["returns"]) do
      {:ok,
       %{
         name: name,
         discriminator: discriminator,
         accounts: accounts,
         args: args,
         docs: docs,
         returns: returns
       }}
    end
  end

  defp parse_optional_docs(nil), do: {:ok, nil}
  defp parse_optional_docs(docs), do: parse_docs(docs)

  defp parse_optional_type(nil), do: {:ok, nil}
  defp parse_optional_type(type), do: parse_type(type)

  defp parse_accounts(accounts) when is_list(accounts) do
    parsed_accounts = Enum.map(accounts, &parse_account_def/1)

    if Enum.all?(parsed_accounts, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_accounts, fn {:ok, acc} -> acc end)}
    else
      {:error, "Failed to parse one or more accounts"}
    end
  end

  defp parse_account_def(account) do
    with {:ok, name} <- parse_name(account["name"]),
         {:ok, discriminator} <- parse_discriminator(account["discriminator"]),
         {:ok, type} <- parse_type_def_ty_struct(account["type"]),
         {:ok, docs} <- parse_optional_docs(account["docs"]) do
      {:ok,
       %{
         name: name,
         discriminator: discriminator,
         type: type,
         docs: docs
       }}
    end
  end

  defp parse_errors(errors) when is_list(errors) do
    parsed_errors = Enum.map(errors, &parse_error_code/1)

    if Enum.all?(parsed_errors, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_errors, fn {:ok, err} -> err end)}
    else
      {:error, "Failed to parse one or more errors"}
    end
  end

  defp parse_error_code(error) do
    with {:ok, code} <- parse_integer(error["code"]),
         {:ok, name} <- parse_name(error["name"]),
         {:ok, msg} <- parse_optional_string(error["msg"]) do
      {:ok,
       %{
         code: code,
         name: name,
         msg: msg
       }}
    end
  end

  defp parse_types(types) when is_list(types) do
    parsed_types = Enum.map(types, &parse_type_def/1)

    if Enum.all?(parsed_types, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_types, fn {:ok, type} -> type end)}
    else
      {:error, "Failed to parse one or more types"}
    end
  end

  defp parse_type_def(type) do
    with {:ok, name} <- parse_name(type["name"]),
         {:ok, type_def} <- parse_type_def_ty(type["type"]) do
      {:ok,
       %{
         name: name,
         type: type_def
       }}
    end
  end

  defp parse_events(events) when is_list(events) do
    parsed_events = Enum.map(events, &parse_event/1)

    if Enum.all?(parsed_events, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_events, fn {:ok, event} -> event end)}
    else
      {:error, "Failed to parse one or more events"}
    end
  end

  defp parse_event(event) do
    with {:ok, name} <- parse_name(event["name"]),
         {:ok, discriminator} <- parse_discriminator(event["discriminator"]),
         {:ok, fields} <- parse_event_fields(event["fields"]) do
      {:ok,
       %{
         name: name,
         discriminator: discriminator,
         fields: fields
       }}
    end
  end

  defp parse_constants(constants) when is_list(constants) do
    parsed_constants = Enum.map(constants, &parse_constant/1)

    if Enum.all?(parsed_constants, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_constants, fn {:ok, const} -> const end)}
    else
      {:error, "Failed to parse one or more constants"}
    end
  end

  defp parse_constant(constant) do
    with {:ok, name} <- parse_name(constant["name"]),
         {:ok, type} <- parse_type(constant["type"]),
         {:ok, value} <- parse_string(constant["value"]) do
      {:ok,
       %{
         name: name,
         type: type,
         value: value
       }}
    end
  end

  defp parse_metadata(metadata) when is_map(metadata) do
    {:ok,
     %{
       address: metadata["address"],
       origin: metadata["origin"],
       chainId: metadata["chainId"]
     }}
  end

  # Helper functions

  defp parse_discriminator(discriminator) when is_list(discriminator) do
    if Enum.all?(discriminator, &is_integer/1) do
      {:ok, discriminator}
    else
      {:error, "Invalid discriminator format"}
    end
  end

  defp parse_discriminator(discriminator) do
    {:ok, discriminator}
  end

  defp parse_docs(docs) when is_list(docs) or is_nil(docs), do: {:ok, docs}
  defp parse_docs(_), do: {:error, "Invalid docs format"}

  defp parse_instruction_accounts(accounts) when is_list(accounts) do
    parsed_accounts = Enum.map(accounts, &parse_instruction_account/1)

    if Enum.all?(parsed_accounts, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_accounts, fn {:ok, acc} -> acc end)}
    else
      {:error, "Failed to parse one or more instruction accounts"}
    end
  end

  defp parse_instruction_account(account) do
    with {:ok, name} <- parse_name(account["name"]),
         {:ok, is_mut} <- parse_boolean(account["isMut"]),
         {:ok, is_signer} <- parse_boolean(account["isSigner"]),
         {:ok, docs} <- parse_docs(account["docs"]),
         {:ok, optional} <- parse_optional_boolean(account["optional"]) do
      {:ok,
       %{
         name: name,
         isMut: is_mut,
         isSigner: is_signer,
         docs: docs,
         optional: optional
       }}
    end
  end

  defp parse_instruction_args(args) when is_list(args) do
    parsed_args = Enum.map(args, &parse_field/1)

    if Enum.all?(parsed_args, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_args, fn {:ok, arg} -> arg end)}
    else
      {:error, "Failed to parse one or more instruction args"}
    end
  end

  defp parse_field(field) do
    with {:ok, name} <- parse_name(field["name"]),
         {:ok, type} <- parse_type(field["type"]) do
      {:ok,
       %{
         name: name,
         type: type
       }}
    end
  end

  defp parse_type_def_ty_struct(type) do
    with {:ok, fields} <- parse_fields(type["fields"]) do
      {:ok,
       %{
         kind: :struct,
         fields: fields
       }}
    end
  end

  defp parse_type_def_ty(type) do
    cond do
      Map.has_key?(type, "kind") && type["kind"] == "struct" ->
        parse_type_def_ty_struct(type)

      Map.has_key?(type, "kind") && type["kind"] == "enum" ->
        parse_type_def_ty_enum(type)

      true ->
        {:error, "Invalid type definition"}
    end
  end

  defp parse_type_def_ty_enum(type) do
    with {:ok, name} <- parse_optional_string(type["name"]),
         {:ok, variants} <- parse_enum_variants(type["variants"]) do
      {:ok,
       %{
         kind: :enum,
         name: name,
         variants: variants
       }}
    end
  end

  defp parse_enum_variants(variants) when is_list(variants) do
    parsed_variants = Enum.map(variants, &parse_enum_variant/1)

    if Enum.all?(parsed_variants, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_variants, fn {:ok, variant} -> variant end)}
    else
      {:error, "Failed to parse one or more enum variants"}
    end
  end

  defp parse_enum_variant(variant) do
    with {:ok, name} <- parse_name(variant["name"]),
         {:ok, fields} <- parse_optional_fields(variant["fields"]) do
      {:ok,
       %{
         name: name,
         fields: fields
       }}
    end
  end

  defp parse_event_fields(fields) when is_list(fields) do
    parsed_fields = Enum.map(fields, &parse_event_field/1)

    if Enum.all?(parsed_fields, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_fields, fn {:ok, field} -> field end)}
    else
      {:error, "Failed to parse one or more event fields"}
    end
  end

  defp parse_event_field(field) do
    with {:ok, name} <- parse_name(field["name"]),
         {:ok, type} <- parse_type(field["type"]),
         {:ok, index} <- parse_boolean(field["index"]) do
      {:ok,
       %{
         name: name,
         type: type,
         index: index
       }}
    end
  end

  defp parse_type(type) when is_binary(type), do: {:ok, type}
  defp parse_type(%{"defined" => defined}), do: {:ok, %{defined: defined}}
  defp parse_type(%{"option" => option}), do: option |> parse_type() |> wrap_result(:option)
  defp parse_type(%{"coption" => coption}), do: coption |> parse_type() |> wrap_result(:coption)
  defp parse_type(%{"vec" => vec}), do: vec |> parse_type() |> wrap_result(:vec)
  defp parse_type(%{"array" => [type, size]}), do: parse_array_type(type, size)
  defp parse_type(_), do: {:error, "Invalid type"}

  defp parse_array_type(type, size) do
    with {:ok, parsed_type} <- parse_type(type),
         {:ok, parsed_size} <- parse_integer(size) do
      {:ok, %{array: {parsed_type, parsed_size}}}
    end
  end

  defp wrap_result({:ok, result}, wrapper), do: {:ok, %{wrapper => result}}
  defp wrap_result(error, _), do: error

  defp parse_fields(fields) when is_list(fields) do
    parsed_fields = Enum.map(fields, &parse_field/1)

    if Enum.all?(parsed_fields, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(parsed_fields, fn {:ok, field} -> field end)}
    else
      {:error, "Failed to parse one or more fields"}
    end
  end

  defp parse_optional_fields(nil), do: {:ok, nil}
  defp parse_optional_fields(fields), do: parse_fields(fields)

  defp parse_boolean(value) when is_boolean(value), do: {:ok, value}
  defp parse_boolean(_), do: {:error, "Invalid boolean value"}

  defp parse_optional_boolean(nil), do: {:ok, nil}
  defp parse_optional_boolean(value), do: parse_boolean(value)

  defp parse_integer(value) when is_integer(value), do: {:ok, value}
  defp parse_integer(_), do: {:error, "Invalid integer value"}

  defp parse_string(value) when is_binary(value), do: {:ok, value}
  defp parse_string(_), do: {:error, "Invalid string value"}

  defp parse_optional_string(nil), do: {:ok, nil}
  defp parse_optional_string(value), do: parse_string(value)
end
