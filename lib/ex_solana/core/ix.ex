defmodule ExSolana.Instruction do
  @moduledoc """
  Functions, types, and structures related to Solana
  [instructions](https://docs.solana.com/developing/programming-model/transactions#instructions).
  """
  alias ExSolana.Account
  alias ExSolana.Transaction.Core.CompiledInstruction

  @typedoc """
  All the details needed to encode an instruction.
  """
  @type t :: %__MODULE__{
          program: ExSolana.key() | nil,
          accounts: [Account.t()],
          data: binary | nil
        }

  defstruct [
    :data,
    :program,
    accounts: []
  ]

  @doc """
  Creates a new Instruction struct.
  It can handle both regular instructions and decoded CompiledInstructions.
  """
  @spec new(map() | CompiledInstruction.t()) :: t()
  def new(%CompiledInstruction{} = instruction) do
    %__MODULE__{
      # We don't have program information in CompiledInstruction
      program: nil,
      accounts: decode_accounts(instruction.accounts, %{}),
      data: instruction.data
    }
  end

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
        %ExSolana.Account{} = acc ->
          acc

        %{key: key, signer?: signer?, writable?: writable?} ->
          %ExSolana.Account{key: key, signer?: signer?, writable?: writable?}

        _ ->
          raise ArgumentError, "Invalid account format: #{inspect(account)}"
      end
    end)
  end

  @doc """
  Decodes a CompiledInstruction into an Instruction struct.
  """
  @spec decode(Core.CompiledInstruction.t(), [ExSolana.key()]) :: t()
  def decode(instruction, account_keys) do
    program = Enum.at(account_keys, instruction.program_id_index)
    accounts = decode_accounts(instruction.accounts, account_keys)

    %__MODULE__{
      program: program,
      accounts: accounts,
      data: instruction.data
    }
  end

  @doc """
  Encodes the instruction data.
  """
  @spec encode_data(list() | binary()) :: binary()
  def encode_data(data) when is_list(data) do
    Enum.into(data, <<>>, &encode_value/1)
  end

  def encode_data(data) when is_binary(data), do: data

  @doc """
  Decodes the instruction data.
  """
  @spec decode_data(binary()) :: list()
  def decode_data(data) when is_binary(data) do
    # This is a placeholder. You'll need to implement the actual decoding logic
    # based on your specific needs and the structure of your instruction data.
    data
  end

  # Private helper functions

  defp decode_accounts(accounts, account_keys) when is_list(accounts) do
    Enum.map(accounts, fn index ->
      pubkey = Enum.at(account_keys, index)
      %ExSolana.Account{key: pubkey, signer?: false, writable?: true}
    end)
  end

  defp decode_accounts(accounts, account_keys) when is_binary(accounts) do
    for <<index <- accounts>> do
      pubkey = Enum.at(account_keys, index)
      %ExSolana.Account{key: pubkey, signer?: false, writable?: true}
    end
  end

  # encodes a string in Rust's expected format
  defp encode_value({value, "str"}) when is_binary(value) do
    <<byte_size(value)::little-size(32), 0::32, value::binary>>
  end

  # encodes a string in Borsh's expected format
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
