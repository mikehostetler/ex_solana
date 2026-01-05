defmodule ExSolana.Solana.Storage.ConfirmedBlock.RewardType do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:Unspecified, 0)
  field(:Fee, 1)
  field(:Rent, 2)
  field(:Staking, 3)
  field(:Voting, 4)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.ConfirmedBlock do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:previous_blockhash, 1, type: :string, json_name: "previousBlockhash")
  field(:blockhash, 2, type: :string)
  field(:parent_slot, 3, type: :uint64, json_name: "parentSlot")

  field(:transactions, 4,
    repeated: true,
    type: ExSolana.Solana.Storage.ConfirmedBlock.ConfirmedTransaction
  )

  field(:rewards, 5, repeated: true, type: ExSolana.Solana.Storage.ConfirmedBlock.Reward)

  field(:block_time, 6,
    type: ExSolana.Solana.Storage.ConfirmedBlock.UnixTimestamp,
    json_name: "blockTime"
  )

  field(:block_height, 7,
    type: ExSolana.Solana.Storage.ConfirmedBlock.BlockHeight,
    json_name: "blockHeight"
  )

  field(:num_partitions, 8,
    type: ExSolana.Solana.Storage.ConfirmedBlock.NumPartitions,
    json_name: "numPartitions"
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.ConfirmedTransaction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:transaction, 1, type: ExSolana.Solana.Storage.ConfirmedBlock.Transaction)
  field(:meta, 2, type: ExSolana.Solana.Storage.ConfirmedBlock.TransactionStatusMeta)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.Transaction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:signatures, 1, repeated: true, type: :bytes)
  field(:message, 2, type: ExSolana.Solana.Storage.ConfirmedBlock.Message)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.Message do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:header, 1, type: ExSolana.Solana.Storage.ConfirmedBlock.MessageHeader)
  field(:account_keys, 2, repeated: true, type: :bytes, json_name: "accountKeys")
  field(:recent_blockhash, 3, type: :bytes, json_name: "recentBlockhash")

  field(:instructions, 4,
    repeated: true,
    type: ExSolana.Solana.Storage.ConfirmedBlock.CompiledInstruction
  )

  field(:versioned, 5, type: :bool)

  field(:address_table_lookups, 6,
    repeated: true,
    type: ExSolana.Solana.Storage.ConfirmedBlock.MessageAddressTableLookup,
    json_name: "addressTableLookups"
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.MessageHeader do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:num_required_signatures, 1, type: :uint32, json_name: "numRequiredSignatures")
  field(:num_readonly_signed_accounts, 2, type: :uint32, json_name: "numReadonlySignedAccounts")

  field(:num_readonly_unsigned_accounts, 3,
    type: :uint32,
    json_name: "numReadonlyUnsignedAccounts"
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.MessageAddressTableLookup do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:account_key, 1, type: :bytes, json_name: "accountKey")
  field(:writable_indexes, 2, type: :bytes, json_name: "writableIndexes")
  field(:readonly_indexes, 3, type: :bytes, json_name: "readonlyIndexes")
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.TransactionStatusMeta do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Solana.Storage.ConfirmedBlock.TokenBalance

  field(:err, 1, type: ExSolana.Solana.Storage.ConfirmedBlock.TransactionError)
  field(:fee, 2, type: :uint64)
  field(:pre_balances, 3, repeated: true, type: :uint64, json_name: "preBalances")
  field(:post_balances, 4, repeated: true, type: :uint64, json_name: "postBalances")

  field(:inner_instructions, 5,
    repeated: true,
    type: ExSolana.Solana.Storage.ConfirmedBlock.InnerInstructions,
    json_name: "innerInstructions"
  )

  field(:inner_instructions_none, 10, type: :bool, json_name: "innerInstructionsNone")
  field(:log_messages, 6, repeated: true, type: :string, json_name: "logMessages")
  field(:log_messages_none, 11, type: :bool, json_name: "logMessagesNone")

  field(:pre_token_balances, 7,
    repeated: true,
    type: TokenBalance,
    json_name: "preTokenBalances"
  )

  field(:post_token_balances, 8,
    repeated: true,
    type: TokenBalance,
    json_name: "postTokenBalances"
  )

  field(:rewards, 9, repeated: true, type: ExSolana.Solana.Storage.ConfirmedBlock.Reward)

  field(:loaded_writable_addresses, 12,
    repeated: true,
    type: :bytes,
    json_name: "loadedWritableAddresses"
  )

  field(:loaded_readonly_addresses, 13,
    repeated: true,
    type: :bytes,
    json_name: "loadedReadonlyAddresses"
  )

  field(:return_data, 14,
    type: ExSolana.Solana.Storage.ConfirmedBlock.ReturnData,
    json_name: "returnData"
  )

  field(:return_data_none, 15, type: :bool, json_name: "returnDataNone")

  field(:compute_units_consumed, 16,
    proto3_optional: true,
    type: :uint64,
    json_name: "computeUnitsConsumed"
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.TransactionError do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:err, 1, type: :bytes)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.InnerInstructions do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:index, 1, type: :uint32)

  field(:instructions, 2,
    repeated: true,
    type: ExSolana.Solana.Storage.ConfirmedBlock.InnerInstruction
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.InnerInstruction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:program_id_index, 1, type: :uint32, json_name: "programIdIndex")
  field(:accounts, 2, type: :bytes)
  field(:data, 3, type: :bytes)
  field(:stack_height, 4, proto3_optional: true, type: :uint32, json_name: "stackHeight")
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.CompiledInstruction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:program_id_index, 1, type: :uint32, json_name: "programIdIndex")
  field(:accounts, 2, type: :bytes)
  field(:data, 3, type: :bytes)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.TokenBalance do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:account_index, 1, type: :uint32, json_name: "accountIndex")
  field(:mint, 2, type: :string)

  field(:ui_token_amount, 3,
    type: ExSolana.Solana.Storage.ConfirmedBlock.UiTokenAmount,
    json_name: "uiTokenAmount"
  )

  field(:owner, 4, type: :string)
  field(:program_id, 5, type: :string, json_name: "programId")
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.UiTokenAmount do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:ui_amount, 1, type: :double, json_name: "uiAmount")
  field(:decimals, 2, type: :uint32)
  field(:amount, 3, type: :string)
  field(:ui_amount_string, 4, type: :string, json_name: "uiAmountString")
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.ReturnData do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:program_id, 1, type: :bytes, json_name: "programId")
  field(:data, 2, type: :bytes)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.Reward do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:pubkey, 1, type: :string)
  field(:lamports, 2, type: :int64)
  field(:post_balance, 3, type: :uint64, json_name: "postBalance")

  field(:reward_type, 4,
    type: ExSolana.Solana.Storage.ConfirmedBlock.RewardType,
    json_name: "rewardType",
    enum: true
  )

  field(:commission, 5, type: :string)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.Rewards do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:rewards, 1, repeated: true, type: ExSolana.Solana.Storage.ConfirmedBlock.Reward)

  field(:num_partitions, 2,
    type: ExSolana.Solana.Storage.ConfirmedBlock.NumPartitions,
    json_name: "numPartitions"
  )
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.UnixTimestamp do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:timestamp, 1, type: :int64)
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.BlockHeight do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:block_height, 1, type: :uint64, json_name: "blockHeight")
end

defmodule ExSolana.Solana.Storage.ConfirmedBlock.NumPartitions do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:num_partitions, 1, type: :uint64, json_name: "numPartitions")
end
