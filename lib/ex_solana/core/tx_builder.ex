defmodule ExSolana.Transaction.Builder do
  @moduledoc """
  A builder for creating and managing Solana transactions.

  ## Features

  - Fluent builder API for transaction construction
  - Automatic transaction splitting when size limits are exceeded
  - Support for Address Lookup Tables (ALT)
  - Built-in instruction helpers (Transfer, JitoTip, JupiterSwap)

  ## Examples

      # Create a new builder
      builder = ExSolana.Transaction.Builder.new()

      # Set payer and blockhash
      builder =
        builder
        |> ExSolana.Transaction.Builder.payer(payer_keypair)
        |> ExSolana.Transaction.Builder.blockhash()

      # Add instructions
      builder =
        builder
        |> ExSolana.Transaction.Builder.transfer(to: recipient, amount: 1000)
        |> ExSolana.Transaction.Builder.add_instruction(custom_instruction)

      # Build transaction
      {:ok, tx} = ExSolana.Transaction.Builder.build(builder)
  """

  alias ExSolana.{Error, Instruction, Key, Transaction}
  require Logger

  @schema Zoi.struct(
            __MODULE__,
            %{
              payer:
                Zoi.string(description: "Payer public key (32 bytes)")
                |> Zoi.optional(),
              blockhash:
                Zoi.string(description: "Recent blockhash for transaction")
                |> Zoi.optional(),
              instructions:
                Zoi.list(Zoi.any(), description: "Transaction instructions")
                |> Zoi.default([]),
              signers:
                Zoi.list(Zoi.any(), description: "Transaction signers")
                |> Zoi.default([]),
              address_lookup_tables:
                Zoi.list(Zoi.string(), description: "ALT addresses for transaction")
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  # ============================================================================
  # Constructor
  # ============================================================================

  @doc """
  Creates a new Transaction.Builder.

  ## Examples

      builder = ExSolana.Transaction.Builder.new()

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  # ============================================================================
  # Instruction Helpers (delegated to Ix modules)
  # ============================================================================

  @doc """
  Adds a SOL transfer instruction to the transaction.

  Delegates to `ExSolana.Ix.Transfer`.

  ## Options

    * `:to` - Recipient public key (required)
    * `:amount` - Amount in lamports (required)
    * `:from` - Sender keypair (defaults to builder's payer)

  """
  defdelegate transfer(builder, opts), to: ExSolana.Ix.Transfer

  @doc """
  Adds a Jito tip instruction to the transaction.

  Delegates to `ExSolana.Ix.JitoTip`.

  ## Options

    * `:to` - Tip recipient public key (required)
    * `:amount` - Tip amount in lamports (required)

  """
  defdelegate jito_tip(builder, opts), to: ExSolana.Ix.JitoTip

  @doc """
  Adds a Jupiter swap instruction to the transaction.

  Delegates to `ExSolana.Ix.JupiterSwap`.

  ## Parameters

    * `from_mint` - Source token mint address
    * `to_mint` - Destination token mint address
    * `amount` - Amount to swap (in smallest unit)
    * `slippage_bps` - Maximum slippage in basis points

  ## Options

    * `:user` - User public key (required)
    * `:min_out` - Minimum output amount (optional)

  """
  defdelegate jupiter_swap(builder, from_mint, to_mint, amount, slippage_bps, opts),
    to: ExSolana.Ix.JupiterSwap

  # ============================================================================
  # Builder Methods
  # ============================================================================

  @doc """
  Adds an instruction to the transaction.

  ## Examples

      instruction = ExSolana.Ix.new(...)
      builder = ExSolana.Transaction.Builder.add_instruction(builder, instruction)

  """
  @spec add_instruction(t(), Instruction.t()) :: t()
  def add_instruction(%__MODULE__{} = builder, %Instruction{} = instruction) do
    %{builder | instructions: builder.instructions ++ [instruction]}
  end

  @doc """
  Adds multiple instructions to the transaction.

  ## Examples

      instructions = [ix1, ix2, ix3]
      builder = ExSolana.Transaction.Builder.add_instructions(builder, instructions)

  """
  @spec add_instructions(t(), [Instruction.t()]) :: t()
  def add_instructions(%__MODULE__{} = builder, instructions) when is_list(instructions) do
    %{builder | instructions: builder.instructions ++ instructions}
  end

  @doc """
  Sets the payer for the transaction.

  The payer will pay the transaction fees and rent.

  ## Examples

      builder = ExSolana.Transaction.Builder.payer(builder, payer_keypair)

  """
  @spec payer(t(), Key.t() | Key.Keypair.t()) :: t()
  def payer(%__MODULE__{} = builder, payer) when is_binary(payer) do
    case Key.decode(payer) do
      {:ok, decoded_payer} ->
        %{builder | payer: decoded_payer}

      {:error, _reason} ->
        %{builder | payer: payer}
    end
  end

  def payer(%__MODULE__{} = builder, %Key.Keypair{pubkey: pubkey}) do
    %{builder | payer: pubkey}
  end

  @doc """
  Adds a signer to the transaction.

  ## Examples

      builder = ExSolana.Transaction.Builder.add_signer(builder, signer_keypair)

  """
  @spec add_signer(t(), Key.Keypair.t()) :: t()
  def add_signer(%__MODULE__{} = builder, signer) do
    %{builder | signers: builder.signers ++ [signer]}
  end

  @doc """
  Adds multiple signers to the transaction.

  ## Examples

      builder = ExSolana.Transaction.Builder.add_signers(builder, [signer1, signer2])

  """
  @spec add_signers(t(), [Key.Keypair.t()]) :: t()
  def add_signers(%__MODULE__{} = builder, signers) when is_list(signers) do
    %{builder | signers: builder.signers ++ signers}
  end

  @doc """
  Fetches the latest blockhash from the network and adds it to the transaction.

  This calls the RPC to get a recent blockhash, which is required for transaction validity.

  ## Examples

      builder = ExSolana.Transaction.Builder.blockhash(builder)

  """
  @spec blockhash(t()) :: t()
  def blockhash(%__MODULE__{} = builder) do
    # TODO: Integrate with RPC client or BlockhashServer
    # For now, return unchanged builder
    Logger.warning("blockhash/1 not yet implemented - requires RPC client integration")
    builder
  end

  @doc """
  Adds a raw instruction to the transaction builder.

  ## Examples

      instruction = %ExSolana.Instruction{...}
      builder = ExSolana.Transaction.Builder.add_raw_instruction(builder, instruction)

  """
  @spec add_raw_instruction(t(), Instruction.t()) :: t()
  def add_raw_instruction(%__MODULE__{} = builder, %Instruction{} = instruction) do
    %{builder | instructions: builder.instructions ++ [instruction]}
  end

  @doc """
  Adds Address Lookup Tables to the transaction builder.

  ALTs allow transactions to reference more accounts than would normally fit.

  ## Examples

      addresses = ["address1", "address2"]
      builder = ExSolana.Transaction.Builder.add_address_lookup_tables(builder, addresses)

  """
  @spec add_address_lookup_tables(t(), [Key.t()]) :: t()
  def add_address_lookup_tables(%__MODULE__{} = builder, address_lookup_tables)
      when is_list(address_lookup_tables) do
    %{builder | address_lookup_tables: builder.address_lookup_tables ++ address_lookup_tables}
  end

  # ============================================================================
  # Build
  # ============================================================================

  @doc """
  Builds the final transaction(s).

  If the transaction exceeds Solana's size limits, it will be automatically
  split into multiple transactions.

  ## Options

    * `:encode` - Whether to encode the transactions to base64. Defaults to `true`.

  ## Returns

    * `binary()` - Base64 encoded transaction (if encode: true)
    * `Transaction.t()` - Transaction struct (if encode: false)
    * `[binary()]` - List of base64 encoded transactions (if split and encode: true)
    * `[Transaction.t()]` - List of transactions (if split and encode: false)
    * `{:error, String.t()}` - Error message if build fails

  ## Examples

      {:ok, encoded_tx} = ExSolana.Transaction.Builder.build(builder)
      {:ok, tx} = ExSolana.Transaction.Builder.build(builder, encode: false)

  """
  @spec build(t(), keyword()) ::
          {:ok, Transaction.t() | [Transaction.t()] | binary() | [binary()]}
          | {:error, Error.t() | String.t()}
  def build(%__MODULE__{} = builder, opts \\ []) do
    encode = Keyword.get(opts, :encode, true)

    result =
      case create_transaction(builder) do
        {:ok, %Transaction{} = tx} ->
          case Transaction.validate_limits(tx) do
            :ok -> {:ok, tx}
            {:error, _reason} -> split_transaction(tx)
          end

        error ->
          error
      end

    case result do
      {:ok, %Transaction{} = tx} ->
        {:ok, maybe_encode(tx, encode)}

      {:ok, [%Transaction{} | _] = txs} ->
        {:ok, Enum.map(txs, &maybe_encode(&1, encode))}

      other ->
        other
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_encode(tx, true) do
    case Transaction.to_binary(tx) do
      {:ok, binary} -> Base.encode64(binary)
      {:error, reason} -> {:error, "Failed to encode transaction: #{inspect(reason)}"}
    end
  end

  defp maybe_encode(tx, false), do: tx

  defp create_transaction(%{blockhash: nil} = _builder) do
    {:error,
     Error.validation_error(
       "Blockhash not set. Call blockhash/1 before building the transaction.",
       field: :blockhash
     )}
  end

  defp create_transaction(%{payer: nil} = _builder) do
    {:error,
     Error.validation_error(
       "Payer not set. Call payer/2 before building the transaction.",
       field: :payer
     )}
  end

  defp create_transaction(builder) do
    tx = %Transaction{
      payer: builder.payer,
      blockhash: builder.blockhash,
      instructions: builder.instructions,
      signers: builder.signers
    }

    {:ok, tx}
  end

  defp split_transaction(%Transaction{} = tx) do
    split_transactions = do_split_transaction(tx, [])
    {:ok, split_transactions}
  end

  defp do_split_transaction(%Transaction{instructions: []} = _tx, acc) do
    Enum.reverse(acc)
  end

  defp do_split_transaction(%Transaction{} = tx, acc) do
    {valid_instructions, remaining_instructions} = split_instructions(tx)

    new_tx = %Transaction{
      payer: tx.payer,
      blockhash: tx.blockhash,
      instructions: valid_instructions,
      signers: tx.signers
    }

    remaining_tx = %Transaction{tx | instructions: remaining_instructions}
    do_split_transaction(remaining_tx, [new_tx | acc])
  end

  defp split_instructions(%Transaction{} = tx) do
    Enum.reduce_while(tx.instructions, {[], tx.instructions}, fn instruction,
                                                                 {valid, remaining} ->
      candidate_tx = %Transaction{tx | instructions: valid ++ [instruction]}

      case Transaction.validate_limits(candidate_tx) do
        :ok -> {:cont, {valid ++ [instruction], tl(remaining)}}
        {:error, _} -> {:halt, {valid, remaining}}
      end
    end)
  end
end
