defmodule ExSolana.Transaction.Core do
  @moduledoc """
  Defines structs corresponding to Solana transaction structures,
  mirroring the Solana.Storage protobuf definitions.
  """
  use TypedStruct

  alias ExSolana.Signature

  @type reward_type :: :Unspecified | :Fee | :Rent | :Staking | :Voting
  @reward_types [:Unspecified, :Fee, :Rent, :Staking, :Voting]

  @spec reward_types() :: [reward_type()]
  def reward_types, do: @reward_types

  typedstruct module: TransactionError do
    field(:err, binary())
  end

  typedstruct module: AccountKey do
    field(:pubkey, ExSolana.Key.t())
    field(:signer, boolean(), default: false)
    field(:writable, boolean(), default: false)
  end

  typedstruct module: InnerInstruction do
    field(:program_id_index, non_neg_integer())
    field(:accounts, binary())
    field(:data, binary())
    field(:stack_height, non_neg_integer() | nil)
  end

  typedstruct module: InnerInstructions do
    field(:index, non_neg_integer())
    field(:instructions, list(InnerInstruction.t()))
  end

  typedstruct module: CompiledInstruction do
    field(:program_id_index, non_neg_integer())
    field(:accounts, binary())
    field(:data, binary())
    field(:stack_height, non_neg_integer() | nil)
    field(:parsed, map() | nil)
  end

  typedstruct module: UiTokenAmount do
    field(:ui_amount, float())
    field(:decimals, non_neg_integer())
    field(:amount, String.t())
    field(:ui_amount_string, String.t())
  end

  typedstruct module: TokenBalance do
    field(:account_index, non_neg_integer())
    field(:mint, String.t())
    field(:ui_token_amount, UiTokenAmount.t())
    field(:owner, String.t())
    field(:program_id, String.t())
  end

  typedstruct module: ReturnData do
    field(:program_id, binary())
    field(:data, binary())
  end

  typedstruct module: Reward do
    field(:pubkey, String.t())
    field(:lamports, integer())
    field(:post_balance, non_neg_integer())
    field(:reward_type, RewardType.t())
    field(:commission, String.t() | nil)
  end

  typedstruct module: UnixTimestamp do
    field(:timestamp, integer())
  end

  typedstruct module: BlockHeight do
    field(:block_height, non_neg_integer())
  end

  typedstruct module: NumPartitions do
    field(:num_partitions, non_neg_integer())
  end

  typedstruct module: LoadedAddress do
    field(:address, binary())
    field(:stack_height, non_neg_integer() | nil)
  end

  typedstruct module: LoadedAddresses do
    field(:writable, list(LoadedAddress.t()))
    field(:readonly, list(LoadedAddress.t()))
  end

  typedstruct module: TransactionStatusMeta do
    field(:err, TransactionError.t())
    field(:fee, non_neg_integer())
    field(:pre_balances, list(non_neg_integer()))
    field(:post_balances, list(non_neg_integer()))
    field(:inner_instructions, list(InnerInstructions.t()))
    field(:inner_instructions_none, boolean())
    field(:log_messages, list(String.t()))
    field(:log_messages_none, boolean())
    field(:pre_token_balances, list(TokenBalance.t()))
    field(:post_token_balances, list(TokenBalance.t()))
    field(:rewards, list(Reward.t()))
    field(:loaded_writable_addresses, list(binary()))
    field(:loaded_readonly_addresses, list(binary()))
    field(:loaded_addresses, LoadedAddresses.t())
    field(:status, String.t())
    field(:return_data, ReturnData.t())
    field(:return_data_none, boolean())
    field(:compute_units_consumed, non_neg_integer() | nil)
  end

  typedstruct module: MessageHeader do
    field(:num_required_signatures, non_neg_integer())
    field(:num_readonly_signed_accounts, non_neg_integer())
    field(:num_readonly_unsigned_accounts, non_neg_integer())
  end

  typedstruct module: MessageAddressTableLookup do
    field(:account_key, binary())
    field(:writable_indexes, binary())
    field(:readonly_indexes, binary())
  end

  typedstruct module: Message do
    field(:header, MessageHeader.t())
    field(:account_keys, list(binary()))
    field(:recent_blockhash, binary())
    field(:instructions, list(CompiledInstruction.t()))
    field(:versioned, boolean())
    field(:address_table_lookups, list(MessageAddressTableLookup.t()))
  end

  typedstruct module: Transaction do
    field(:signatures, list(binary()))
    field(:message, Message.t())
  end

  typedstruct module: TransactionInfo do
    field(:transaction, Transaction.t())
    field(:signature, Signature.t())
    field(:is_vote, boolean())
    field(:meta, TransactionStatusMeta.t())
    field(:index, non_neg_integer())
  end

  typedstruct module: ConfirmedTransaction do
    field(:transaction, Transaction.t())
    field(:slot, non_neg_integer())
    field(:block_time, non_neg_integer())
    field(:version, String.t())
  end

  typedstruct module: Invocation do
    field(:program_id, String.t())
    field(:instruction, atom())
    field(:params, map())
    field(:data, binary())
    field(:accounts, list(ExSolana.Account.t()))
    field(:logs, list(String.t()))
    field(:events, map() | nil)
    field(:analyzed_data, map() | nil)
    field(:actions, list(map()))
    field(:inner_invocations, list(Invocation.t()))
  end

  typedstruct module: ParsedIx do
    field(:id, non_neg_integer())
    field(:parent, non_neg_integer())
    field(:level, non_neg_integer())
    field(:children, list(non_neg_integer()))
    field(:logs, list(String.t()))
    field(:program, String.t())
    field(:ix, Instruction.t())
  end

  typedstruct module: AnalyzedIx do
    field(:id, non_neg_integer())
    field(:parent, non_neg_integer())
    field(:level, non_neg_integer())
    field(:children, list(non_neg_integer()))
    field(:logs, list(String.t()))
    field(:program, String.t())
    field(:ix, Instruction.t())
    field(:decoded_ix, map())
    field(:event, map())
    field(:action, map())
  end
end
