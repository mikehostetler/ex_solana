defmodule ExSolana.Transaction do
  @moduledoc """
  Functions for building and encoding Solana
  [transactions](https://docs.solana.com/developing/programming-model/transactions)
  """

  alias ExSolana.Account
  alias ExSolana.Borsh
  alias ExSolana.CompactArray
  alias ExSolana.Instruction

  require Logger

  @typedoc """
  All the details needed to encode a transaction.
  """
  @type t :: %__MODULE__{
          payer: ExSolana.key() | nil,
          blockhash: binary | nil,
          instructions: [Instruction.t()],
          signers: [ExSolana.keypair()]
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

  defstruct [
    :payer,
    :blockhash,
    instructions: [],
    signers: []
  ]

  # Solana transaction limits
  @max_transaction_size 1232
  @max_instructions 19
  @max_accounts 32
  @max_signers 8
  @doc """
  Returns the maximum size of a Solana transaction in bytes.
  """
  def max_transaction_size, do: @max_transaction_size

  @doc """
  Returns the maximum number of instructions allowed in a single Solana transaction.
  """
  def max_instructions, do: @max_instructions

  @doc """
  Returns the maximum number of accounts that can be referenced in a single Solana transaction.
  """
  def max_accounts, do: @max_accounts

  @doc """
  Returns the maximum number of signers allowed in a single Solana transaction.
  """
  def max_signers, do: @max_signers

  @doc """
  decodes a base58-encoded signature and returns it in a tuple.

  If it fails, return an error tuple.
  """
  @spec decode(encoded :: binary) :: {:ok, binary} | {:error, binary}
  def decode(encoded) when is_binary(encoded) do
    case B58.decode58(encoded) do
      {:ok, decoded} -> check(decoded)
      _ -> {:error, "invalid signature"}
    end
  end

  def decode(_), do: {:error, "invalid signature"}

  @doc """
  decodes a base58-encoded signature and returns it.

  Throws an `ArgumentError` if it fails.
  """
  @spec decode!(encoded :: binary) :: binary
  def decode!(encoded) when is_binary(encoded) do
    case decode(encoded) do
      {:ok, key} ->
        key

      {:error, _} ->
        raise ArgumentError, "invalid signature input: #{encoded}"
    end
  end

  @doc """
  Checks to see if a transaction's signature is valid.

  Returns `{:ok, signature}` if it is, and an error tuple if it isn't.
  """
  @spec check(binary) :: {:ok, binary} | {:error, :invalid_signature}
  def check(signature)
  def check(<<signature::binary-64>>), do: {:ok, signature}
  def check(_), do: {:error, :invalid_signature}

  @doc """
  Encodes a `t:Solana.Transaction.t/0` into a [binary
  format](https://docs.solana.com/developing/programming-model/transactions#anatomy-of-a-transaction)

  Returns `{:ok, encoded_transaction}` if the transaction was successfully
  encoded, or an error tuple if the encoding failed -- plus more error details
  via `Logger.error/1`.
  """
  @spec to_binary(tx :: t) :: {:ok, binary()} | {:error, encoding_err()}
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
    expected = MapSet.new(Enum.map(signers, &elem(&1, 1)))

    accounts
    |> Enum.filter(& &1.signer?)
    |> MapSet.new(& &1.key)
    |> MapSet.equal?(expected)
  end

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
        unary(&1.signer? && !&1.writable?) + elem(&2, 1),
        unary(!&1.signer? && !&1.writable?) + elem(&2, 2)
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
        CompactArray.to_iolist(ix.data)
      ]
    end)
  end

  defp reorder_signers(signers, accounts) do
    account_idxs = index_accounts(accounts)
    Enum.sort_by(signers, &Map.get(account_idxs, elem(&1, 1)))
  end

  defp index_accounts(accounts) do
    Map.new(Enum.with_index(accounts, &{&1.key, &2}))
  end

  defp sign({secret, pk}, message), do: Ed25519.signature(message, secret, pk)

  def parse(encoded) do
    with {:ok, signatures, rest} <- decode_signatures(encoded),
         {:ok, message, _rest} <- decode_message(rest) do
      {:ok,
       %{
         signatures: signatures,
         message: message
       }}
    else
      {:error, step, reason} ->
        Logger.warning("Error parsing transaction: #{step} - #{inspect(reason)}")
        {:error, {step, reason}}
    end
  end

  defp decode_signatures(encoded) do
    case CompactArray.decode_and_split(encoded, 64) do
      {signatures, rest, _count} -> {:ok, signatures, rest}
      error -> {:error, :signatures, error}
    end
  end

  defp decode_message(encoded) do
    with {:ok, header, rest} <- decode_header(encoded),
         {:ok, account_keys, rest} <- decode_account_keys(rest),
         {:ok, blockhash, rest} <- decode_blockhash(rest),
         {:ok, instructions, rest} <- decode_instructions(rest) do
      {:ok,
       %{
         header: header,
         account_keys: account_keys,
         blockhash: blockhash,
         instructions: instructions
       }, rest}
    end
  end

  defp decode_header(
         <<num_required_signatures, num_readonly_signed_accounts, num_readonly_unsigned_accounts, rest::binary>>
       ) do
    {:ok,
     %{
       num_required_signatures: num_required_signatures,
       num_readonly_signed_accounts: num_readonly_signed_accounts,
       num_readonly_unsigned_accounts: num_readonly_unsigned_accounts
     }, rest}
  end

  defp decode_header(_), do: {:error, :header, "Invalid header format"}

  defp decode_account_keys(encoded) do
    case CompactArray.decode_and_split(encoded, 32) do
      {account_keys, rest, _count} -> {:ok, account_keys, rest}
      error -> {:error, :account_keys, error}
    end
  end

  defp decode_blockhash(<<blockhash::binary-size(32), rest::binary>>), do: {:ok, blockhash, rest}
  defp decode_blockhash(_), do: {:error, :blockhash, "Invalid blockhash format"}

  defp decode_instructions(encoded) do
    case CompactArray.decode_and_split(encoded) do
      {rest, count} ->
        # Decode count number of variable-length instructions
        case decode_variable_instructions(rest, count, []) do
          {:ok, instructions, remaining_rest} ->
            {:ok, instructions, remaining_rest}
          {:error, reason} ->
            {:error, :instructions, reason}
        end

      error ->
        {:error, :instructions, error}
    end
  end

  defp decode_variable_instructions(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_variable_instructions(rest, count, acc) when count > 0 do
    # Each instruction is: program_id_index(u8) + accounts_len(u8) + accounts(accounts_len bytes) + data_len(u8) + data(data_len bytes)
    case rest do
      <<program_id_index, accounts_len, accounts::binary-size(accounts_len), data_len, data::binary-size(data_len), remaining::binary>> ->
        # Reconstruct the instruction in the format that decode_instruction expects
        instruction_binary = <<program_id_index, accounts_len>> <> accounts <> <<data_len>> <> data
        decoded_instruction = decode_instruction(instruction_binary)
        decode_variable_instructions(remaining, count - 1, [decoded_instruction | acc])
      _ ->
        {:error, "invalid instruction format"}
    end
  end

  defp decode_instruction(encoded) do
    instruction_schema = [
      program_id_index: "u8",
      accounts: ["u8"],
      data: ["u8"]
    ]

    case Borsh.decode(encoded, instruction_schema) do
      {:ok, {decoded, _rest}} -> decoded
      error -> {:error, :instruction, error}
    end
  end

  @doc """
  Parses a `t:Solana.Transaction.t/0` from data encoded in Solana's [binary
  format](https://docs.solana.com/developing/programming-model/transactions#anatomy-of-a-transaction)

  Returns `{transaction, extras}` if the transaction was successfully
  parsed, or `:error` if the provided binary could not be parsed. `extras`
  is a keyword list containing information about the encoded transaction,
  namely:

  - `:header` - the [transaction message
  header](https://docs.solana.com/developing/programming-model/transactions#message-header-format)
  - `:accounts` - an [ordered array of
  accounts](https://docs.solana.com/developing/programming-model/transactions#account-addresses-format)
  - `:signatures` - a [list of signed copies of the transaction
  message](https://docs.solana.com/developing/programming-model/transactions#signatures)
  """

  # @spec parse(encoded :: binary) :: {t(), keyword} | :error
  # def parse(encoded) do
  #   with {:ok, [signatures, message, _count]} <-
  #          debug_step(CompactArray.decode_and_split(encoded, 64), "Decoding signatures"),
  #        {:ok, header, contents} <- debug_step(match_header(message), "Matching header"),
  #        {:ok, account_keys, hash_and_ixs, key_count} <-
  #          debug_step(CompactArray.decode_and_split(contents, 32), "Decoding account keys"),
  #        {:ok, blockhash, ix_data} <-
  #          debug_step(match_blockhash(hash_and_ixs), "Matching blockhash"),
  #        {:ok, instructions} <-
  #          debug_step(extract_instructions(ix_data), "Extracting instructions") do
  #     tx_accounts = derive_accounts(account_keys, key_count, header)
  #     indices = Map.new(Enum.with_index(tx_accounts, &{&2, &1}))

  #     {
  #       %__MODULE__{
  #         payer: tx_accounts |> List.first() |> Map.get(:key),
  #         blockhash: blockhash,
  #         instructions:
  #           Enum.map(instructions, fn {program, accounts, data} ->
  #             %Instruction{
  #               data: if(data == "", do: nil, else: :binary.list_to_bin(data)),
  #               program: indices |> Map.get(program) |> Map.get(:key),
  #               accounts: Enum.map(accounts, &Map.get(indices, &1))
  #             }
  #           end)
  #       },
  #       [
  #         accounts: tx_accounts,
  #         header: header,
  #         signatures: signatures
  #       ]
  #     }
  #   else
  #     {:error, step, reason} ->
  #       IO.puts("Error in step: #{step}")
  #       IO.inspect(reason, label: "Reason")
  #       :error
  #   end
  # end

  # defp debug_step({:ok, result}, step) when is_tuple(result), do: {:ok, Tuple.to_list(result)}
  # defp debug_step({:ok, result}, step), do: {:ok, result}
  # defp debug_step(:error, step), do: {:error, step, "Decoding failed"}
  # defp debug_step(other, step), do: {:error, step, "Unexpected result: #{inspect(other)}"}

  # defp match_header(<<header::binary-size(3), contents::binary>>), do: {:ok, header, contents}
  # defp match_header(_), do: {:error, "Invalid header format"}

  # defp match_blockhash(<<blockhash::binary-size(32), ix_data::binary>>),
  #   do: {:ok, blockhash, ix_data}

  # defp match_blockhash(_), do: {:error, "Invalid blockhash format"}

  # defp extract_instructions(data) do
  #   case CompactArray.decode_and_split(data) do
  #     {:ok, {instructions, _rest, _count}} -> {:ok, instructions}
  #     error -> error
  #   end
  # end

  # defp extract_instructions(data, count) do
  #   Enum.reduce_while(1..count, {[], data}, fn _, {acc, raw} ->
  #     case extract_instruction(raw) do
  #       {ix, rest} -> {:cont, {[ix | acc], rest}}
  #       _ -> {:halt, :error}
  #     end
  #   end)
  # end

  # defp extract_instruction(raw) do
  #   with <<program::8, rest::binary>> <- raw,
  #        {accounts, rest, _} <- CompactArray.decode_and_split(rest, 1),
  #        {data, rest, _} <- extract_instruction_data(rest) do
  #     {{program, Enum.map(accounts, &:binary.decode_unsigned/1), data}, rest}
  #   else
  #     _ -> :error
  #   end
  # end

  # defp extract_instruction_data(""), do: {"", "", 0}
  # defp extract_instruction_data(raw), do: CompactArray.decode_and_split(raw, 1)

  # defp derive_accounts(keys, total, header) do
  #   <<signers_count::8, signers_readonly_count::8, nonsigners_readonly_count::8>> = header
  #   {signers, nonsigners} = Enum.split(keys, signers_count)
  #   {signers_write, signers_read} = Enum.split(signers, signers_count - signers_readonly_count)

  #   {nonsigners_write, nonsigners_read} =
  #     Enum.split(nonsigners, total - signers_count - nonsigners_readonly_count)

  #   List.flatten([
  #     Enum.map(signers_write, &%Account{key: &1, writable?: true, signer?: true}),
  #     Enum.map(signers_read, &%Account{key: &1, signer?: true}),
  #     Enum.map(nonsigners_write, &%Account{key: &1, writable?: true}),
  #     Enum.map(nonsigners_read, &%Account{key: &1})
  #   ])
  # end

  # @doc """
  # Validates that a transaction does not exceed Solana's limits.
  # """
  # @spec validate_limits(t()) :: :ok | {:error, encoding_err()}
  def validate_limits(%__MODULE__{instructions: instructions, signers: signers} = tx) do
    cond do
      length(instructions) > @max_instructions ->
        {:error, :too_many_instructions}

      length(get_unique_accounts(tx)) > @max_accounts ->
        {:error, :too_many_accounts}

      length(signers) > @max_signers ->
        {:error, :too_many_signers}

      true ->
        :ok
    end
  end

  # Helper function to get unique accounts from a transaction
  defp get_unique_accounts(%__MODULE__{instructions: instructions, payer: payer}) do
    accounts =
      instructions
      |> Enum.flat_map(fn
        %{program: program, accounts: accounts} ->
          [program | Enum.map(accounts, & &1.key)]

        _ ->
          []
      end)
      |> Enum.uniq()

    if payer, do: [payer | accounts], else: accounts
  end
end
