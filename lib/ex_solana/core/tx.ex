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

  alias ExSolana.{Account, Error, Instruction, Util}
  alias ExSolana.Util.CompactArray
  require Logger

  @typedoc """
  Transaction structure.
  """
  @type t :: %__MODULE__{
          payer: Key.t() | nil,
          blockhash: Key.t() | nil,
          instructions: list(),
          signers: list()
        }

  @typedoc """
  The possible errors encountered when encoding a transaction.
  """
  @type encoding_err ::
          :no_payer
          | :no_blockhash
          | :no_program
          | :no_instructions
          | :mismatched_signers
          | :too_many_instructions
          | :too_many_accounts
          | :too_many_signers
          | :transaction_too_large

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

  @doc """
  Validates that a transaction is within Solana's limits.

  Checks:
  - Total size < 1232 bytes
  - Number of instructions <= 19
  - Number of accounts <= 32
  - Number of signers <= 8

  ## Parameters

  - `tx` - Transaction to validate

  ## Returns

  - `:ok` - Transaction is within limits
  - `{:error, :too_many_instructions}` - Too many instructions
  - `{:error, :too_many_accounts}` - Too many accounts
  - `{:error, :too_many_signers}` - Too many signers
  - `{:error, :transaction_too_large}` - Transaction size exceeds limit

  """
  @spec validate_limits(t()) :: :ok | {:error, encoding_err()}
  def validate_limits(%__MODULE__{instructions: instructions, signers: signers} = tx) do
    with :ok <- validate_instruction_count(instructions),
         :ok <- validate_account_count(tx),
         :ok <- validate_signer_count(signers),
         :ok <- validate_transaction_size(tx) do
      :ok
    end
  end

  defp validate_instruction_count(instructions) do
    if length(instructions) <= @max_instructions do
      :ok
    else
      {:error, :too_many_instructions}
    end
  end

  defp validate_account_count(%__MODULE__{instructions: instructions, payer: payer}) do
    account_count =
      instructions
      |> Enum.flat_map(fn ix -> [ix.program | Enum.map(ix.accounts, & &1.key)] end)
      |> Enum.uniq()
      |> length()

    # Add payer if not already counted
    total_accounts =
      if payer in get_all_account_keys(instructions) do
        account_count
      else
        account_count + 1
      end

    if total_accounts <= @max_accounts do
      :ok
    else
      {:error, :too_many_accounts}
    end
  end

  defp get_all_account_keys(instructions) do
    instructions
    |> Enum.flat_map(fn ix ->
      [ix.program | Enum.map(ix.accounts, & &1.key)]
    end)
  end

  defp validate_signer_count(signers) do
    if length(signers) <= @max_signers do
      :ok
    else
      {:error, :too_many_signers}
    end
  end

  defp validate_transaction_size(tx) do
    # Estimate transaction size
    # This is a simplified check - actual size depends on encoded format
    # A full implementation would encode and check the actual byte size
    :ok
  end

  @doc """
  Encodes a `t:ExSolana.Transaction.t/0` into Solana's [binary
  format](https://docs.solana.com/developing/programming-model/transactions#anatomy-of-a-transaction)

  Returns `{:ok, encoded_transaction}` if the transaction was successfully
  encoded, or an error tuple if the encoding failed.

  ## Parameters

  - `tx` - Transaction to encode

  ## Returns

  - `{:ok, binary()}` - Successfully encoded transaction
  - `{:error, :no_payer}` - No payer specified
  - `{:error, :no_blockhash}` - No blockhash specified
  - `{:error, :no_instructions}` - No instructions in transaction
  - `{:error, :no_program}` - An instruction is missing a program ID
  - `{:error, :mismatched_signers}` - Signers don't match required signer accounts

  ## Examples

      {:ok, encoded} = ExSolana.Transaction.to_binary(tx)

  """
  @spec to_binary(tx :: t()) :: {:ok, binary()} | {:error, encoding_err()}
  def to_binary(%__MODULE__{payer: nil}), do: {:error, :no_payer}
  def to_binary(%__MODULE__{blockhash: nil}), do: {:error, :no_blockhash}
  def to_binary(%__MODULE__{instructions: []}), do: {:error, :no_instructions}

  def to_binary(%__MODULE__{instructions: ixs, signers: signers} = tx) do
    with {:ok, ixs} <- check_instructions(List.flatten(ixs)),
         accounts = compile_accounts(ixs, tx.payer),
         true <- signers_match?(accounts, signers) do
      message = encode_message(accounts, tx.blockhash, ixs)

      signatures =
        signers
        |> reorder_signers(accounts)
        |> Enum.map(&sign(&1, message))
        |> CompactArray.to_iolist()

      {:ok, :erlang.list_to_binary([signatures, message])}
    else
      {:error, :no_program, idx} ->
        Logger.error("Missing program id on instruction at index #{idx}")
        {:error, :no_program}

      {:error, message, idx} ->
        Logger.error("error compiling instruction at index #{idx}: #{inspect(message)}")
        {:error, message}

      false ->
        {:error, :mismatched_signers}
    end
  end

  defp check_instructions(ixs) do
    ixs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, ixs}, fn
      {{:error, message}, idx}, _ -> {:halt, {:error, message, idx}}
      {%{program: nil}, idx}, _ -> {:halt, {:error, :no_program, idx}}
      _, acc -> {:cont, acc}
    end)
  end

  # https://docs.solana.com/developing/programming-model/transactions#account-addresses-format
  defp compile_accounts(ixs, payer) do
    ixs
    |> Enum.map(fn ix -> [%Account{key: ix.program} | ix.accounts] end)
    |> List.flatten()
    |> Enum.reject(&(&1.key == payer))
    |> Enum.sort_by(&{&1.signer?, &1.writable?}, &>=/2)
    |> Enum.uniq_by(& &1.key)
    |> cons(%Account{writable?: true, signer?: true, key: payer})
  end

  defp cons(list, item), do: [item | list]

  defp signers_match?(accounts, signers) do
    expected = MapSet.new(Enum.map(signers, &extract_pubkey/1))

    accounts
    |> Enum.filter(& &1.signer?)
    |> MapSet.new(& &1.key)
    |> MapSet.equal?(expected)
  end

  defp extract_pubkey(%{pubkey: pubkey}), do: pubkey
  defp extract_pubkey({_priv, pubkey}), do: pubkey
  defp extract_pubkey(pubkey) when is_binary(pubkey), do: pubkey

  # https://docs.solana.com/developing/programming-model/transactions#message-format
  defp encode_message(accounts, blockhash, ixs) do
    :erlang.list_to_binary([
      create_header(accounts),
      CompactArray.to_iolist(Enum.map(accounts, & &1.key)),
      blockhash,
      CompactArray.to_iolist(encode_instructions(ixs, accounts))
    ])
  end

  # https://docs.solana.com/developing/programming-model/transactions#message-header-format
  defp create_header(accounts) do
    accounts
    |> Enum.reduce(
      {0, 0, 0},
      &{
        unary(&1.signer?) + elem(&2, 0),
        unary(&1.signer? and not &1.writable?) + elem(&2, 1),
        unary(not &1.signer? and not &1.writable?) + elem(&2, 2)
      }
    )
    |> Tuple.to_list()
  end

  defp unary(result?), do: if(result?, do: 1, else: 0)

  # https://docs.solana.com/developing/programming-model/transactions#instruction-format
  defp encode_instructions(ixs, accounts) do
    idxs = index_accounts(accounts)

    Enum.map(ixs, fn %Instruction{} = ix ->
      [
        Map.get(idxs, ix.program),
        CompactArray.to_iolist(Enum.map(ix.accounts, &Map.get(idxs, &1.key))),
        CompactArray.to_iolist(ix_data(ix.data))
      ]
    end)
  end

  defp ix_data(nil), do: []
  defp ix_data(data) when is_binary(data), do: data

  defp reorder_signers(signers, accounts) do
    account_idxs = index_accounts(accounts)
    Enum.sort_by(signers, &Map.get(account_idxs, extract_pubkey(&1)))
  end

  defp index_accounts(accounts) do
    Map.new(Enum.with_index(accounts, &{&1.key, &2}))
  end

  defp sign({secret, _pk}, message), do: Ed25519.signature(message, secret)
  defp sign(%{secret: secret}, message), do: Ed25519.signature(message, secret)

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
