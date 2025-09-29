defmodule ExSolana.RPC.TransactionDecoder do
  @moduledoc """
  Decodes Solana transactions from RPC responses into ExSolana.Transaction.Core structs.
  """

  alias ExSolana.Key
  alias ExSolana.Signature
  alias ExSolana.Transaction.Core

  require Logger

  @type decode_result :: {:ok, Core.ConfirmedTransaction.t()} | {:error, String.t()}

  def decode(
        %{
          "blockTime" => block_time,
          "meta" => meta,
          "slot" => slot,
          "transaction" => transaction,
          "version" => version
        },
        signature
      ) do
    with {:ok, decoded_transaction} <- decode_transaction(transaction),
         {:ok, decoded_meta} <- decode_meta(meta) do
      tx_info = %Core.TransactionInfo{
        transaction: decoded_transaction,
        signature: signature,
        is_vote: false,
        meta: decoded_meta,
        index: 0
      }

      {:ok,
       %Core.ConfirmedTransaction{
         transaction: tx_info,
         slot: slot,
         block_time: block_time,
         version: version
       }}
    else
      {:error, reason} -> {:error, "Failed to decode transaction: #{reason}"}
    end
  end

  defp decode_transaction(%{"message" => message, "signatures" => signatures}) do
    with {:ok, decoded_message} <- decode_message(message) do
      {:ok,
       %Core.Transaction{
         signatures: Enum.map(signatures, &decode_signature/1),
         message: decoded_message
       }}
    end
  end

  defp decode_message(message) do
    {:ok,
     %Core.Message{
       header: decode_header(message["header"]),
       account_keys: decode_account_keys(message["accountKeys"]),
       recent_blockhash: decode_pubkey(message["recentBlockhash"]),
       instructions: decode_instructions(message["instructions"]),
       address_table_lookups: decode_address_table_lookups(message["addressTableLookups"])
     }}
  end

  defp decode_header(nil), do: nil

  defp decode_header(header) do
    %Core.MessageHeader{
      num_required_signatures: header["numRequiredSignatures"],
      num_readonly_signed_accounts: header["numReadonlySignedAccounts"],
      num_readonly_unsigned_accounts: header["numReadonlyUnsignedAccounts"]
    }
  end

  defp decode_account_keys(account_keys) do
    Enum.map(account_keys, fn key ->
      %Core.AccountKey{
        pubkey: decode_pubkey(key["pubkey"]),
        signer: key["signer"],
        writable: key["writable"]
      }
    end)
  end

  defp decode_instructions(instructions) do
    Enum.map(instructions, fn instruction ->
      %Core.CompiledInstruction{
        program_id_index: instruction["programIdIndex"],
        accounts: instruction["accounts"],
        data: instruction["data"],
        stack_height: Map.get(instruction, "stackHeight"),
        parsed: decode_parsed_instruction(instruction["parsed"])
      }
    end)
  end

  defp decode_parsed_instruction(nil), do: nil

  defp decode_parsed_instruction(parsed) do
    %{
      type: parsed["type"],
      info: parsed["info"]
    }
  end

  defp decode_address_table_lookups(nil), do: []

  defp decode_address_table_lookups(lookups) do
    Enum.map(lookups, fn lookup ->
      %Core.MessageAddressTableLookup{
        account_key: decode_pubkey(lookup["accountKey"]),
        writable_indexes: lookup["writableIndexes"],
        readonly_indexes: lookup["readonlyIndexes"]
      }
    end)
  end

  defp decode_meta(meta) do
    {:ok,
     %Core.TransactionStatusMeta{
       err: decode_error(meta["err"]),
       fee: meta["fee"],
       pre_balances: meta["preBalances"],
       post_balances: meta["postBalances"],
       inner_instructions: decode_inner_instructions(meta["innerInstructions"]),
       log_messages: meta["logMessages"],
       pre_token_balances: decode_token_balances(meta["preTokenBalances"]),
       post_token_balances: decode_token_balances(meta["postTokenBalances"]),
       rewards: decode_rewards(meta["rewards"]),
       status: decode_status(meta["status"]),
       compute_units_consumed: meta["computeUnitsConsumed"]
     }}
  end

  defp decode_error(nil), do: nil
  defp decode_error(err), do: %Core.TransactionError{err: err}

  defp decode_inner_instructions(nil), do: []

  defp decode_inner_instructions(inner_instructions) do
    Enum.map(inner_instructions, fn inner ->
      %Core.InnerInstructions{
        index: inner["index"],
        instructions: Enum.map(inner["instructions"], &decode_compiled_instruction/1)
      }
    end)
  end

  defp decode_compiled_instruction(inst) do
    %Core.CompiledInstruction{
      program_id_index: inst["programIdIndex"],
      accounts: inst["accounts"],
      data: inst["data"],
      stack_height: Map.get(inst, "stackHeight"),
      parsed: decode_parsed_instruction(inst["parsed"])
    }
  end

  defp decode_token_balances(nil), do: []

  defp decode_token_balances(token_balances) do
    Enum.map(token_balances, fn balance ->
      %Core.TokenBalance{
        account_index: balance["accountIndex"],
        mint: decode_pubkey(balance["mint"]),
        owner: decode_pubkey(balance["owner"]),
        ui_token_amount: decode_ui_token_amount(balance["uiTokenAmount"]),
        program_id: decode_pubkey(balance["programId"])
      }
    end)
  end

  defp decode_ui_token_amount(nil), do: nil

  defp decode_ui_token_amount(amount) do
    %Core.UiTokenAmount{
      ui_amount: amount["uiAmount"],
      decimals: amount["decimals"],
      amount: amount["amount"],
      ui_amount_string: amount["uiAmountString"]
    }
  end

  defp decode_rewards(nil), do: []

  defp decode_rewards(rewards) do
    Enum.map(rewards, fn reward ->
      %Core.Reward{
        pubkey: decode_pubkey(reward["pubkey"]),
        lamports: reward["lamports"],
        post_balance: reward["postBalance"],
        reward_type: decode_reward_type(reward["rewardType"]),
        commission: reward["commission"]
      }
    end)
  end

  defp decode_reward_type(type) when is_binary(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> String.to_atom(type)
  end

  defp decode_reward_type(type), do: type

  defp decode_status(%{"Ok" => nil}), do: :ok
  defp decode_status(status), do: status

  defp decode_signature(signature) do
    case Signature.decode(signature) do
      {:ok, decoded} ->
        decoded

      {:error, reason} ->
        Logger.warning("Failed to decode signature: #{reason}")
        signature
    end
  end

  defp decode_pubkey(pubkey) do
    case Key.decode(pubkey) do
      {:ok, decoded} ->
        decoded

      {:error, reason} ->
        Logger.warning("Failed to decode pubkey: #{reason}")
        pubkey
    end
  end
end
