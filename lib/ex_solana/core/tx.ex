defmodule ExSolana.Transaction do
  @moduledoc """
  Solana transaction building and encoding.

  ## Overview

  Solana transactions are used to interact with programs on the blockchain.
  A transaction contains:
  - A list of instructions to execute
  - A recent blockhash for transaction validity
  - A list of accounts to read from or write to
  - Signatures authorizing the transaction

  ## Examples

      # Create a new transaction
      tx = ExSolana.Transaction.new(
        instructions: [ix],
        blockhash: blockhash,
        payer: payer_keypair,
        signers: [payer_keypair]
      )

      # Sign a transaction
      {:ok, signed_tx} = ExSolana.Transaction.sign(tx, [keypair])

  ## Limits

  - Max transaction size: 1232 bytes
  - Max instructions: 19
  - Max accounts: 32
  - Max signers: 8

  """

  alias ExSolana.{Error, Key, Account}

  @typedoc """
  Transaction structure.
  """
  @type t :: %__MODULE__{
          payer: Key.t() | nil,
          blockhash: Key.t() | nil,
          instructions: list(),
          signers: list()
        }

  @schema Zoi.struct(
            __MODULE__,
            %{
              payer:
                Zoi.string(description: "Payer account public key")
                |> Zoi.optional(),
              blockhash:
                Zoi.string(description: "Recent blockhash")
                |> Zoi.optional(),
              instructions:
                Zoi.list(Zoi.any(), description: "List of instructions")
                |> Zoi.default([]),
              signers:
                Zoi.list(Zoi.any(), description: "List of signer keypairs")
                |> Zoi.default([])
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t_schema :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  # Solana transaction limits
  @max_transaction_size 1232
  @max_instructions 19
  @max_accounts 32
  @max_signers 8

  @doc """
  Returns the maximum size of a Solana transaction in bytes.
  """
  @spec max_transaction_size() :: 1232
  def max_transaction_size, do: @max_transaction_size

  @doc """
  Returns the maximum number of instructions allowed in a single transaction.
  """
  @spec max_instructions() :: 19
  def max_instructions, do: @max_instructions

  @doc """
  Returns the maximum number of accounts that can be referenced.
  """
  @spec max_accounts() :: 32
  def max_accounts, do: @max_accounts

  @doc """
  Returns the maximum number of signers allowed.
  """
  @spec max_signers() :: 8
  def max_signers, do: @max_signers

  @doc """
  Creates a new transaction.

  ## Parameters

  - `instructions` - List of instructions to execute
  - `opts` - Transaction options:
    - `:blockhash` - Recent blockhash
    - `:payer` - Payer account (defaults to first signer)
    - `:signers` - List of signer keypairs

  ## Returns

  - `{:ok, transaction}` - Valid transaction
  - `{:error, %ValidationError{}}` - Invalid parameters

  ## Examples

      {:ok, tx} = ExSolana.Transaction.new(
        instructions: [ix],
        blockhash: blockhash,
        payer: pubkey,
        signers: [keypair]
      )

  """
  @spec new(list(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(instructions, opts \\ []) when is_list(instructions) do
    blockhash = Keyword.get(opts, :blockhash)
    payer = Keyword.get(opts, :payer)
    signers = Keyword.get(opts, :signers, [])

    tx = %__MODULE__{
      payer: payer,
      blockhash: blockhash,
      instructions: instructions,
      signers: signers
    }

    validate(tx)
  end

  @doc """
  Creates a new transaction, raising on error.

  ## Parameters

  - `instructions` - List of instructions
  - `opts` - Transaction options

  ## Returns

  - Transaction struct

  ## Raises

  - `Error.ValidationError` - If parameters are invalid

  """
  @spec new!(list(), keyword()) :: t()
  def new!(instructions, opts \\ []) do
    case new(instructions, opts) do
      {:ok, tx} ->
        tx

      {:error, %Error.ValidationError{} = error} ->
        raise error
    end
  end

  @doc """
  Validates a transaction.

  ## Parameters

  - `tx` - Transaction to validate

  ## Returns

  - `{:ok, tx}` - Valid transaction
  - `{:error, %ValidationError{}}` - Invalid transaction

  """
  @spec validate(t()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = tx) do
    with :ok <- validate_instructions(tx),
         :ok <- validate_blockhash(tx),
         :ok <- validate_signers(tx) do
      {:ok, tx}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_instructions(%__MODULE__{instructions: instructions}) do
    if length(instructions) > @max_instructions do
      {:error,
       Error.validation_error("Too many instructions",
         field: :instructions,
         value: length(instructions),
         details: %{max: @max_instructions}
       )}
    else
      :ok
    end
  end

  defp validate_instructions(_), do: :ok

  defp validate_blockhash(%__MODULE__{blockhash: nil}) do
    {:error, Error.validation_error("Blockhash required", field: :blockhash)}
  end

  defp validate_blockhash(%__MODULE__{blockhash: blockhash})
       when is_binary(blockhash) do
    if byte_size(blockhash) == 32 do
      :ok
    else
      {:error, Error.validation_error("Invalid blockhash length", field: :blockhash)}
    end
  end

  defp validate_blockhash(_) do
    {:error, Error.validation_error("Invalid blockhash", field: :blockhash)}
  end

  defp validate_signers(%__MODULE__{signers: signers}) do
    if length(signers) > @max_signers do
      {:error,
       Error.validation_error("Too many signers",
         field: :signers,
         value: length(signers),
         details: %{max: @max_signers}
       )}
    else
      :ok
    end
  end

  @doc """
  Adds an instruction to the transaction.

  ## Parameters

  - `tx` - Transaction
  - `instruction` - Instruction to add

  ## Returns

  - Updated transaction or error if max instructions exceeded

  """
  @spec add_instruction(t(), any()) :: {:ok, t()} | {:error, Error.t()}
  def add_instruction(%__MODULE__{instructions: instructions} = tx, instruction) do
    new_instructions = instructions ++ [instruction]

    if length(new_instructions) <= @max_instructions do
      {:ok, %{tx | instructions: new_instructions}}
    else
      {:error,
       Error.validation_error("Cannot add instruction: max reached",
         field: :instructions,
         details: %{max: @max_instructions, current: length(instructions)}
       )}
    end
  end

  @doc """
  Sets the blockhash for a transaction.

  ## Parameters

  - `tx` - Transaction
  - `blockhash` - 32-byte blockhash

  ## Returns

  - Updated transaction

  """
  @spec set_blockhash(t(), Key.t()) :: t()
  def set_blockhash(%__MODULE__{} = tx, blockhash) when is_binary(blockhash) do
    %{tx | blockhash: blockhash}
  end

  @doc """
  Adds a signer to the transaction.

  ## Parameters

  - `tx` - Transaction
  - `signer` - Signer keypair to add

  ## Returns

  - `{:ok, tx}` - Updated transaction
  - `{:error, %ValidationError{}}` - Max signers exceeded

  """
  @spec add_signer(t(), any()) :: {:ok, t()} | {:error, Error.t()}
  def add_signer(%__MODULE__{signers: signers} = tx, signer) do
    new_signers = signers ++ [signer]

    if length(new_signers) <= @max_signers do
      {:ok, %{tx | signers: new_signers}}
    else
      {:error,
       Error.validation_error("Cannot add signer: max reached",
         field: :signers,
         details: %{max: @max_signers, current: length(signers)}
       )}
    end
  end

  # ============================================================================
  # Encoded Transaction
  # ============================================================================

  defmodule Encoded do
    @moduledoc """
    An encoded, signed transaction ready for submission.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                data: Zoi.string(description: "Encoded transaction bytes"),
                signatures:
                  Zoi.list(Zoi.string(), description: "Transaction signatures")
                  |> Zoi.default([])
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc """
    Creates an encoded transaction from raw bytes and signatures.

    """
    @spec new(binary(), list(ExSolana.Signature.t())) :: t()
    def new(data, signatures \\ []) do
      %__MODULE__{
        data: data,
        signatures: signatures
      }
    end
  end
end
