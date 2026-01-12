defmodule ExSolana.Instruction do
  @moduledoc """
  Solana instruction structures and utilities.

  An instruction contains all the information needed to invoke a Solana program:
  - Program ID to invoke
  - List of accounts to read/write
  - Instruction data byte array

  ## Examples

      # Create a simple instruction
      instruction = %ExSolana.Instruction{
        program: program_id,
        accounts: [%ExSolana.Account{key: pubkey, signer?: true, writable?: false}],
        data: <<1, 2, 3>>
      }

  """

  alias ExSolana.Account
  alias ExSolana.Error

  @typedoc """
  A Solana instruction.

  ## Fields

  - `:program` - The program ID to invoke (32 bytes)
  - `:accounts` - List of accounts involved in the instruction
  - `:data` - Instruction data byte array

  """
  @type t :: %__MODULE__{
          program: ExSolana.Key.t() | nil,
          accounts: [Account.t()],
          data: binary() | nil
        }

  defstruct [
    :data,
    :program,
    accounts: []
  ]

  @doc """
  Creates a new Instruction struct.

  ## Parameters

  - `params` - A map containing:
    - `:program` - Program ID (32 bytes)
    - `:accounts` - List of account maps or Account structs
    - `:data` - Instruction data (binary)

  ## Returns

  An `%ExSolana.Instruction{}` struct.

  ## Examples

      # Create from map
      instruction = ExSolana.Instruction.new(%{
        program: pubkey,
        accounts: [%{key: account_key, signer?: true, writable?: false}],
        data: <<1, 2, 3>>
      })

  """
  @spec new(map()) :: t()
  def new(params) when is_map(params) do
    %__MODULE__{
      program: Map.get(params, :program),
      accounts: parse_accounts(Map.get(params, :accounts, [])),
      data: Map.get(params, :data)
    }
  end

  defp parse_accounts(accounts) do
    Enum.map(accounts, fn account ->
      case account do
        %Account{} = acc ->
          acc

        %{key: key, signer?: signer?, writable?: writable?} ->
          %Account{key: key, signer?: signer?, writable?: writable?}

        %{key: key, signer: signer, writable: writable} ->
          # Support both atom styles
          %Account{key: key, signer?: signer, writable?: writable}

        _ ->
          raise ArgumentError,
                "Invalid account format: #{inspect(account)}. " <>
                  "Expected %ExSolana.Account{} or %{key: ..., signer?: ..., writable?: ...}"
      end
    end)
  end

  @doc """
  Encodes instruction data from a list of values.

  ## Parameters

  - `data` - List of values to encode or binary data

  ## Returns

  Encoded binary data.

  ## Encoding Formats

  - `{value, "str"}` - Rust string format (length + 4-byte padding + bytes)
  - `{value, "borsh"}` - Borsh string format (length + bytes)
  - `{value, size}` - Little-endian integer
  - `{value, size, :big}` - Big-endian integer
  - `{value, size, :little}` - Little-endian integer
  - `binary` - Raw bytes
  - `integer` - Single byte
  - `boolean` - 1 or 0

  ## Examples

      # Encode Rust string
      ExSolana.Instruction.encode_data([{"hello", "str"}])
      #=> <<5, 0, 0, 0, 0, 0, 0, 0, 104, 101, 108, 108, 111>>

      # Encode little-endian 32-bit integer
      ExSolana.Instruction.encode_data([{1000, 32}])
      #=> <<232, 3, 0, 0>>

      # Encode boolean
      ExSolana.Instruction.encode_data([true])
      #=> <<1>>

  """
  @spec encode_data(list() | binary()) :: binary()
  def encode_data(data) when is_list(data) do
    Enum.into(data, <<>>, &encode_value/1)
  end

  def encode_data(data) when is_binary(data), do: data

  @doc """
  Decodes instruction data (placeholder).

  This is a placeholder function. Actual decoding logic depends on the
  specific program's instruction format and should be implemented per-program.

  ## Examples

      data = <<1, 2, 3>>
      ExSolana.Instruction.decode_data(data)
      #=> <<1, 2, 3>>

  """
  @spec decode_data(binary()) :: binary()
  def decode_data(data) when is_binary(data), do: data

  # Private helper functions

  # Encodes a string in Rust's expected format
  defp encode_value({value, "str"}) when is_binary(value) do
    <<byte_size(value)::little-size(32), 0::32, value::binary>>
  end

  # Encodes a string in Borsh's expected format
  # https://borsh.io/#pills-specification
  defp encode_value({value, "borsh"}) when is_binary(value) do
    <<byte_size(value)::little-size(32), value::binary>>
  end

  defp encode_value({value, size}), do: encode_value({value, size, :little})
  defp encode_value({value, size, :big}), do: <<value::size(size)-big>>
  defp encode_value({value, size, :little}), do: <<value::size(size)-little>>
  defp encode_value(value) when is_binary(value), do: value
  defp encode_value(value) when is_integer(value), do: <<value>>
  defp encode_value(value) when is_boolean(value), do: <<unary(value)>>

  defp unary(val), do: if(val, do: 1, else: 0)
end
