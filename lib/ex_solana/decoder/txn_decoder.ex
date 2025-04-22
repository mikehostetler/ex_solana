defmodule ExSolana.Decoder.TxnDecoder do
  @moduledoc """
  Decodes Solana transactions from Geyser GRPC feed efficiently.
  """
  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.Decoder.TokenChange
  alias ExSolana.Geyser.SubscribeUpdateTransaction
  alias ExSolana.Instruction
  alias ExSolana.Transaction.Core

  @reward_types %{
    0 => :Unspecified,
    1 => :Fee,
    2 => :Rent,
    3 => :Staking,
    4 => :Voting
  }

  def decode(%SubscribeUpdateTransaction{} = transaction) do
    debug("Decoding transaction", transaction: transaction)

    case do_decode(transaction) do
      {:ok, decoded_txn} ->
        additional_data = TokenChange.compute_additional_data(decoded_txn)
        decoded_txn_with_changes = Map.put(decoded_txn, :additional, additional_data)

        debug("Transaction decoded", result: decoded_txn_with_changes)
        {:ok, decoded_txn_with_changes}

      {:error, reason} ->
        debug("Failed to decode transaction", error: reason)
        {:error, reason}
    end
  end

  def decode(_), do: {:error, :invalid_transaction}

  defp do_decode(%{slot: slot, transaction: txn}) do
    debug("Decoding inner transaction", slot: slot)

    with {:ok, decoded_txn} <- decode_inner_transaction(txn) do
      result = %Core.ConfirmedTransaction{slot: slot, transaction: decoded_txn}
      debug("Inner transaction decoded", result: result)
      {:ok, result}
    end
  end

  defp do_decode(_), do: {:error, :invalid_transaction_structure}

  defp decode_inner_transaction(%{transaction: txn, signature: sig, meta: meta, is_vote: is_vote, index: index}) do
    debug("Decoding transaction components", signature: sig, is_vote: is_vote, index: index)

    with {:ok, decoded_txn} <- decode_transaction(txn),
         {:ok, decoded_meta} <- decode_transaction_meta(meta, get_account_keys(txn)) do
      result = %Core.TransactionInfo{
        signature: encode_signature(sig),
        is_vote: is_vote,
        transaction: decoded_txn,
        meta: decoded_meta,
        index: index
      }

      debug("Transaction components decoded", result: result)
      {:ok, result}
    end
  end

  defp decode_inner_transaction(_), do: {:error, :invalid_inner_transaction}

  defp decode_transaction(%{signatures: sigs, message: msg}) do
    debug("Decoding transaction", signatures: sigs)

    with {:ok, decoded_msg} <- decode_message(msg) do
      result = %Core.Transaction{
        signatures: Enum.map(sigs, &encode_signature/1),
        message: decoded_msg
      }

      debug("Transaction decoded", result: result)
      {:ok, result}
    end
  end

  defp decode_transaction(_), do: {:error, :invalid_transaction_structure}

  defp decode_message(%{
         header: header,
         account_keys: keys,
         recent_blockhash: blockhash,
         instructions: instructions,
         address_table_lookups: lookups,
         versioned: versioned
       }) do
    debug("Decoding message",
      header: header,
      account_keys: keys,
      recent_blockhash: blockhash,
      versioned: versioned
    )

    with {:ok, decoded_instructions} <- decode_instructions(instructions, keys),
         {:ok, decoded_lookups} <- decode_lookups(lookups) do
      result = %Core.Message{
        header: decode_header(header),
        account_keys: Enum.map(keys, &encode_key/1),
        recent_blockhash: encode_key(blockhash),
        instructions: decoded_instructions,
        address_table_lookups: decoded_lookups,
        versioned: versioned
      }

      debug("Message decoded", result: result)
      {:ok, result}
    end
  end

  defp decode_message(_), do: {:error, :invalid_message_structure}

  defp decode_header(%{
         num_required_signatures: req_sigs,
         num_readonly_signed_accounts: ro_signed,
         num_readonly_unsigned_accounts: ro_unsigned
       }) do
    debug("Decoding header", req_sigs: req_sigs, ro_signed: ro_signed, ro_unsigned: ro_unsigned)

    result = %Core.MessageHeader{
      num_required_signatures: req_sigs,
      num_readonly_signed_accounts: ro_signed,
      num_readonly_unsigned_accounts: ro_unsigned
    }

    debug("Header decoded", result: result)
    result
  end

  defp decode_header(_), do: %Core.MessageHeader{}

  defp decode_instructions(instructions, account_keys) do
    debug("Decoding instructions", instructions: instructions)

    result =
      instructions
      |> Enum.map(&decode_instruction(&1, account_keys))
      |> collect_results()

    debug("Instructions decoded", result: result)
    result
  end

  defp decode_instruction(%{program_id_index: pid_index, accounts: accs, data: data}, account_keys) do
    debug("Decoding instruction", program_id_index: pid_index, accounts: accs, data: data)
    program_id = Enum.at(account_keys, pid_index)
    decoded_accounts = decode_account_indexes(accs, account_keys)

    instruction = %Instruction{
      program: encode_key(program_id),
      accounts: decoded_accounts,
      data: data
    }

    debug("Instruction decoded", result: instruction)
    {:ok, instruction}
  end

  defp decode_instruction(_, _), do: {:error, :invalid_instruction}

  defp decode_lookups(lookups) do
    debug("Decoding lookups", lookups: lookups)

    result =
      lookups
      |> Enum.map(&decode_lookup/1)
      |> collect_results()

    debug("Lookups decoded", result: result)
    result
  end

  defp decode_lookup(%{account_key: key, writable_indexes: w_idx, readonly_indexes: ro_idx}) do
    debug("Decoding lookup", account_key: key, writable_indexes: w_idx, readonly_indexes: ro_idx)

    result = %Core.MessageAddressTableLookup{
      account_key: encode_key(key),
      writable_indexes: w_idx,
      readonly_indexes: ro_idx
    }

    debug("Lookup decoded", result: result)
    {:ok, result}
  end

  defp decode_lookup(_), do: {:error, :invalid_lookup}

  defp decode_transaction_meta(meta, account_keys) do
    debug("Decoding transaction meta", meta: meta)

    with {:ok, inner_instructions} <-
           decode_inner_instructions(meta.inner_instructions, account_keys),
         {:ok, pre_token_balances} <- decode_token_balances(meta.pre_token_balances),
         {:ok, post_token_balances} <- decode_token_balances(meta.post_token_balances),
         {:ok, rewards} <- decode_rewards(meta.rewards) do
      result = %Core.TransactionStatusMeta{
        err: decode_transaction_error(meta.err),
        fee: meta.fee,
        pre_balances: meta.pre_balances,
        post_balances: meta.post_balances,
        inner_instructions: inner_instructions,
        log_messages: meta.log_messages,
        pre_token_balances: pre_token_balances,
        post_token_balances: post_token_balances,
        rewards: rewards,
        loaded_writable_addresses: Enum.map(meta.loaded_writable_addresses, &encode_key/1),
        loaded_readonly_addresses: Enum.map(meta.loaded_readonly_addresses, &encode_key/1),
        return_data: decode_return_data(meta.return_data),
        compute_units_consumed: meta.compute_units_consumed,
        inner_instructions_none: meta.inner_instructions_none,
        log_messages_none: meta.log_messages_none,
        return_data_none: meta.return_data_none
      }

      debug("Transaction meta decoded", result: result)
      {:ok, result}
    end
  end

  defp decode_inner_instructions(instructions, account_keys) do
    debug("Decoding inner instructions", instructions: instructions)

    result =
      instructions
      |> Enum.map(&decode_inner_instruction(&1, account_keys))
      |> collect_results()

    debug("Inner instructions decoded", result: result)
    result
  end

  defp decode_inner_instruction(%{index: index, instructions: insts}, account_keys) do
    debug("Decoding inner instruction", index: index, instructions: insts)

    with {:ok, decoded_insts} <- decode_instructions(insts, account_keys) do
      result = %Core.InnerInstructions{index: index, instructions: decoded_insts}
      debug("Inner instruction decoded", result: result)
      {:ok, result}
    end
  end

  defp decode_inner_instruction(_, _), do: {:error, :invalid_inner_instruction}

  defp decode_token_balances(balances) do
    debug("Decoding token balances", balances: balances)

    result =
      balances
      |> Enum.map(&decode_token_balance/1)
      |> collect_results()

    debug("Token balances decoded", result: result)
    result
  end

  defp decode_token_balance(%{
         account_index: index,
         mint: mint,
         ui_token_amount: amount,
         owner: owner,
         program_id: program_id
       }) do
    debug("Decoding token balance",
      account_index: index,
      mint: mint,
      owner: owner,
      program_id: program_id
    )

    result = %Core.TokenBalance{
      account_index: index,
      mint: mint,
      ui_token_amount: decode_ui_token_amount(amount),
      owner: owner,
      program_id: program_id
    }

    debug("Token balance decoded", result: result)
    {:ok, result}
  end

  defp decode_token_balance(_), do: {:error, :invalid_token_balance}

  defp decode_ui_token_amount(%{
         ui_amount: ui_amount,
         decimals: decimals,
         amount: amount,
         ui_amount_string: ui_amount_string
       }) do
    debug("Decoding UI token amount",
      ui_amount: ui_amount,
      decimals: decimals,
      amount: amount,
      ui_amount_string: ui_amount_string
    )

    result = %Core.UiTokenAmount{
      ui_amount: ui_amount,
      decimals: decimals,
      amount: amount,
      ui_amount_string: ui_amount_string
    }

    debug("UI token amount decoded", result: result)
    result
  end

  defp decode_ui_token_amount(_), do: %Core.UiTokenAmount{}

  defp decode_rewards(rewards) do
    debug("Decoding rewards", rewards: rewards)

    result =
      rewards
      |> Enum.map(&decode_reward/1)
      |> collect_results()

    debug("Rewards decoded", result: result)
    result
  end

  defp decode_reward(%{
         pubkey: pubkey,
         lamports: lamports,
         post_balance: post_balance,
         reward_type: reward_type,
         commission: commission
       }) do
    debug("Decoding reward",
      pubkey: pubkey,
      lamports: lamports,
      post_balance: post_balance,
      reward_type: reward_type,
      commission: commission
    )

    result = %Core.Reward{
      pubkey: encode_key(pubkey),
      lamports: lamports,
      post_balance: post_balance,
      reward_type: decode_reward_type(reward_type),
      commission: commission
    }

    debug("Reward decoded", result: result)
    {:ok, result}
  end

  defp decode_reward(_), do: {:error, :invalid_reward}

  defp decode_transaction_error(nil), do: nil

  defp decode_transaction_error(%{err: err}) do
    debug("Decoding transaction error", err: err)
    result = %Core.TransactionError{err: Base.encode64(err)}
    debug("Transaction error decoded", result: result)
    result
  end

  defp decode_transaction_error(_), do: nil

  defp decode_return_data(nil), do: nil

  defp decode_return_data(%{program_id: program_id, data: data}) do
    debug("Decoding return data", program_id: program_id, data: data)

    result = %Core.ReturnData{
      program_id: encode_key(program_id),
      data: data
    }

    debug("Return data decoded", result: result)
    result
  end

  defp decode_return_data(_), do: nil

  defp decode_account_indexes(<<>>, _account_keys), do: []

  defp decode_account_indexes(accounts, account_keys) when is_binary(accounts) do
    debug("Decoding account indexes", accounts: accounts)

    result =
      for <<index <- accounts>> do
        pubkey = Enum.at(account_keys, index)
        %ExSolana.Account{key: encode_key(pubkey)}
      end

    debug("Account indexes decoded", result: result)
    result
  end

  defp decode_account_indexes(_, _), do: []

  defp decode_reward_type(type) do
    debug("Decoding reward type", type: type)
    result = Map.get(@reward_types, type, :Unspecified)
    debug("Reward type decoded", result: result)
    result
  end

  defp encode_signature(sig) do
    debug("Encoding signature", signature: sig)
    {:ok, signature} = ExSolana.Signature.encode(sig)
    debug("Signature encoded", result: signature)
    signature
  end

  defp encode_key(nil), do: nil

  defp encode_key(key) when is_binary(key) do
    debug("Encoding key", key: key)
    result = B58.encode58(key)
    debug("Key encoded", result: result)
    result
  end

  defp encode_key(key), do: key

  defp get_account_keys(%{message: %{account_keys: keys}}), do: keys
  defp get_account_keys(_), do: []

  defp collect_results(results) do
    debug("Collecting results", results: results)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        result = {:ok, Enum.map(oks, fn {:ok, v} -> v end)}
        debug("Results collected successfully", result: result)
        result

      {_, errors} ->
        result = {:error, "Failed to decode: #{inspect(errors)}"}
        error("Failed to collect results", errors: errors)
        result
    end
  end
end
