defmodule ExSolana.Transaction.Builder do
  @moduledoc """
  A builder for creating and managing Solana transactions.
  """

  alias ExSolana.Instruction
  alias ExSolana.RPC.BlockhashServer
  alias ExSolana.RPC.Request.Helpers
  alias ExSolana.Transaction

  require Logger

  defstruct [
    :payer,
    :blockhash,
    instructions: [],
    signers: [],
    address_lookup_tables: []
  ]

  @type t :: %__MODULE__{
          payer: ExSolana.key() | nil,
          blockhash: binary() | nil,
          instructions: [ExSolana.Instruction.t()],
          signers: [ExSolana.keypair()],
          address_lookup_tables: [binary()]
        }

  @doc """
  Creates a new TxBuilder.
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  defdelegate transfer(builder, opts), to: ExSolana.Ix.Transfer
  defdelegate jito_tip(builder, opts), to: ExSolana.Ix.JitoTip

  defdelegate jupiter_swap(builder, from_mint, to_mint, amount, slippage_bps, opts),
    to: ExSolana.Ix.JupiterSwap

  @doc """
  Adds an instruction to the transaction.
  """
  @spec add_instruction(t(), ExSolana.Instruction.t()) :: t()
  def add_instruction(%__MODULE__{} = builder, instruction) do
    %{builder | instructions: builder.instructions ++ [instruction]}
  end

  @doc """
  Adds multiple instructions to the transaction.
  """
  @spec add_instructions(t(), [ExSolana.Instruction.t()]) :: t()
  def add_instructions(%__MODULE__{} = builder, instructions) when is_list(instructions) do
    %{builder | instructions: builder.instructions ++ instructions}
  end

  @doc """
  Sets the payer for the transaction.
  """
  @spec payer(t(), ExSolana.key()) :: t()
  def payer(%__MODULE__{} = builder, payer) do
    {:ok, decoded_payer} = Helpers.decode_if_base58(payer)
    %{builder | payer: decoded_payer}
  end

  @doc """
  Adds a signer to the transaction.
  """
  @spec add_signer(t(), ExSolana.keypair()) :: t()
  def add_signer(%__MODULE__{} = builder, signer) do
    %{builder | signers: builder.signers ++ [signer]}
  end

  @doc """
  Adds multiple signers to the transaction.
  """
  @spec add_signers(t(), [ExSolana.keypair()]) :: t()
  def add_signers(%__MODULE__{} = builder, signers) when is_list(signers) do
    %{builder | signers: builder.signers ++ signers}
  end

  @doc """
  Fetches the latest blockhash from the BlockhashServer and adds it to the transaction.
  """
  @spec blockhash(t()) :: t()
  def blockhash(%__MODULE__{} = builder) do
    with {:ok, blockhash} <- BlockhashServer.get_latest_blockhash(),
         {:ok, decoded_blockhash} <- Helpers.decode_if_base58(blockhash) do
      %{builder | blockhash: decoded_blockhash}
    else
      {:error, reason} ->
        Logger.warning("Failed to fetch or decode blockhash: #{inspect(reason)}")
        builder
    end
  end

  @doc """
  Adds a raw instruction to the transaction builder.
  """
  @spec add_raw_instruction(t(), Instruction.t()) :: t()
  def add_raw_instruction(%__MODULE__{} = builder, %Instruction{} = instruction) do
    %{builder | instructions: builder.instructions ++ [instruction]}
  end

  @doc """
  Adds Address Lookup Tables to the transaction builder.
  """
  @spec add_address_lookup_tables(t(), [binary()]) :: t()
  def add_address_lookup_tables(%__MODULE__{} = builder, address_lookup_tables) when is_list(address_lookup_tables) do
    %{builder | address_lookup_tables: builder.address_lookup_tables ++ address_lookup_tables}
  end

  @doc """
  Builds the final transaction(s).

  ## Options

    * `:encode` - Whether to encode the transactions to binary. Defaults to `true`.

  """
  @spec build(t(), keyword()) ::
          ExSolana.Transaction.t()
          | [ExSolana.Transaction.t()]
          | binary()
          | [binary()]
          | {:error, String.t()}
  def build(%__MODULE__{} = builder, opts \\ []) do
    encode = Keyword.get(opts, :encode, true)

    result =
      case create_transaction(builder) do
        {:ok, tx} ->
          case ExSolana.Transaction.validate_limits(tx) do
            :ok -> {:ok, tx}
            {:error, _reason} -> split_transaction(tx)
          end

        error ->
          error
      end

    case result do
      {:ok, %ExSolana.Transaction{} = tx} ->
        maybe_encode(tx, encode, builder.address_lookup_tables)

      {:ok, [%ExSolana.Transaction{} | _] = txs} ->
        Enum.map(txs, &maybe_encode(&1, encode, builder.address_lookup_tables))

      other ->
        other
    end
  end

  defp maybe_encode(tx, true, _address_lookup_tables) do
    case ExSolana.Transaction.to_binary(tx) do
      {:ok, binary} -> Base.encode64(binary)
      {:error, reason} -> {:error, "Failed to encode transaction: #{inspect(reason)}"}
    end
  end

  defp maybe_encode(tx, false, _address_lookup_tables), do: tx

  defp create_transaction(%{blockhash: nil} = _builder) do
    {:error, "Blockhash not set. Call blockhash/1 before building the transaction."}
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

  defp split_transaction(tx) do
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
    Enum.reduce_while(tx.instructions, {[], tx.instructions}, fn instruction, {valid, remaining} ->
      candidate_tx = %Transaction{tx | instructions: valid ++ [instruction]}

      case Transaction.validate_limits(candidate_tx) do
        :ok -> {:cont, {valid ++ [instruction], tl(remaining)}}
        {:error, _} -> {:halt, {valid, remaining}}
      end
    end)
  end
end
