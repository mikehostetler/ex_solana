defmodule ExSolana.Geyser.CommitmentLevel do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:PROCESSED, 0)
  field(:CONFIRMED, 1)
  field(:FINALIZED, 2)
end

defmodule ExSolana.Geyser.SubscribeRequest.AccountsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterAccounts)
end

defmodule ExSolana.Geyser.SubscribeRequest.SlotsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterSlots)
end

defmodule ExSolana.Geyser.SubscribeRequest.TransactionsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterTransactions)
end

defmodule ExSolana.Geyser.SubscribeRequest.TransactionsStatusEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterTransactions)
end

defmodule ExSolana.Geyser.SubscribeRequest.BlocksEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterBlocks)
end

defmodule ExSolana.Geyser.SubscribeRequest.BlocksMetaEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterBlocksMeta)
end

defmodule ExSolana.Geyser.SubscribeRequest.EntryEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Geyser.SubscribeRequestFilterEntry)
end

defmodule ExSolana.Geyser.SubscribeRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:accounts, 1,
    repeated: true,
    type: ExSolana.Geyser.SubscribeRequest.AccountsEntry,
    map: true
  )

  field(:slots, 2, repeated: true, type: ExSolana.Geyser.SubscribeRequest.SlotsEntry, map: true)

  field(:transactions, 3,
    repeated: true,
    type: ExSolana.Geyser.SubscribeRequest.TransactionsEntry,
    map: true
  )

  field(:transactions_status, 10,
    repeated: true,
    type: ExSolana.Geyser.SubscribeRequest.TransactionsStatusEntry,
    json_name: "transactionsStatus",
    map: true
  )

  field(:blocks, 4, repeated: true, type: ExSolana.Geyser.SubscribeRequest.BlocksEntry, map: true)

  field(:blocks_meta, 5,
    repeated: true,
    type: ExSolana.Geyser.SubscribeRequest.BlocksMetaEntry,
    json_name: "blocksMeta",
    map: true
  )

  field(:entry, 8, repeated: true, type: ExSolana.Geyser.SubscribeRequest.EntryEntry, map: true)
  field(:commitment, 6, proto3_optional: true, type: ExSolana.Geyser.CommitmentLevel, enum: true)

  field(:accounts_data_slice, 7,
    repeated: true,
    type: ExSolana.Geyser.SubscribeRequestAccountsDataSlice,
    json_name: "accountsDataSlice"
  )

  field(:ping, 9, proto3_optional: true, type: ExSolana.Geyser.SubscribeRequestPing)
end

defmodule ExSolana.Geyser.SubscribeRequestFilterAccounts do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:account, 2, repeated: true, type: :string)
  field(:owner, 3, repeated: true, type: :string)
  field(:filters, 4, repeated: true, type: ExSolana.Geyser.SubscribeRequestFilterAccountsFilter)
end

defmodule ExSolana.Geyser.SubscribeRequestFilterAccountsFilter do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:filter, 0)

  field(:memcmp, 1, type: ExSolana.Geyser.SubscribeRequestFilterAccountsFilterMemcmp, oneof: 0)
  field(:datasize, 2, type: :uint64, oneof: 0)
  field(:token_account_state, 3, type: :bool, json_name: "tokenAccountState", oneof: 0)
end

defmodule ExSolana.Geyser.SubscribeRequestFilterAccountsFilterMemcmp do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:data, 0)

  field(:offset, 1, type: :uint64)
  field(:bytes, 2, type: :bytes, oneof: 0)
  field(:base58, 3, type: :string, oneof: 0)
  field(:base64, 4, type: :string, oneof: 0)
end

defmodule ExSolana.Geyser.SubscribeRequestFilterSlots do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:filter_by_commitment, 1,
    proto3_optional: true,
    type: :bool,
    json_name: "filterByCommitment"
  )
end

defmodule ExSolana.Geyser.SubscribeRequestFilterTransactions do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:vote, 1, proto3_optional: true, type: :bool)
  field(:failed, 2, proto3_optional: true, type: :bool)
  field(:signature, 5, proto3_optional: true, type: :string)
  field(:account_include, 3, repeated: true, type: :string, json_name: "accountInclude")
  field(:account_exclude, 4, repeated: true, type: :string, json_name: "accountExclude")
  field(:account_required, 6, repeated: true, type: :string, json_name: "accountRequired")
end

defmodule ExSolana.Geyser.SubscribeRequestFilterBlocks do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:account_include, 1, repeated: true, type: :string, json_name: "accountInclude")

  field(:include_transactions, 2,
    proto3_optional: true,
    type: :bool,
    json_name: "includeTransactions"
  )

  field(:include_accounts, 3, proto3_optional: true, type: :bool, json_name: "includeAccounts")
  field(:include_entries, 4, proto3_optional: true, type: :bool, json_name: "includeEntries")
end

defmodule ExSolana.Geyser.SubscribeRequestFilterBlocksMeta do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Geyser.SubscribeRequestFilterEntry do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Geyser.SubscribeRequestAccountsDataSlice do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:offset, 1, type: :uint64)
  field(:length, 2, type: :uint64)
end

defmodule ExSolana.Geyser.SubscribeRequestPing do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:id, 1, type: :int32)
end

defmodule ExSolana.Geyser.SubscribeUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:update_oneof, 0)

  field(:filters, 1, repeated: true, type: :string)
  field(:account, 2, type: ExSolana.Geyser.SubscribeUpdateAccount, oneof: 0)
  field(:slot, 3, type: ExSolana.Geyser.SubscribeUpdateSlot, oneof: 0)
  field(:transaction, 4, type: ExSolana.Geyser.SubscribeUpdateTransaction, oneof: 0)

  field(:transaction_status, 10,
    type: ExSolana.Geyser.SubscribeUpdateTransactionStatus,
    json_name: "transactionStatus",
    oneof: 0
  )

  field(:block, 5, type: ExSolana.Geyser.SubscribeUpdateBlock, oneof: 0)
  field(:ping, 6, type: ExSolana.Geyser.SubscribeUpdatePing, oneof: 0)
  field(:pong, 9, type: ExSolana.Geyser.SubscribeUpdatePong, oneof: 0)

  field(:block_meta, 7,
    type: ExSolana.Geyser.SubscribeUpdateBlockMeta,
    json_name: "blockMeta",
    oneof: 0
  )

  field(:entry, 8, type: ExSolana.Geyser.SubscribeUpdateEntry, oneof: 0)
end

defmodule ExSolana.Geyser.SubscribeUpdateAccount do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:account, 1, type: ExSolana.Geyser.SubscribeUpdateAccountInfo)
  field(:slot, 2, type: :uint64)
  field(:is_startup, 3, type: :bool, json_name: "isStartup")
end

defmodule ExSolana.Geyser.SubscribeUpdateAccountInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:pubkey, 1, type: :bytes)
  field(:lamports, 2, type: :uint64)
  field(:owner, 3, type: :bytes)
  field(:executable, 4, type: :bool)
  field(:rent_epoch, 5, type: :uint64, json_name: "rentEpoch")
  field(:data, 6, type: :bytes)
  field(:write_version, 7, type: :uint64, json_name: "writeVersion")
  field(:txn_signature, 8, proto3_optional: true, type: :bytes, json_name: "txnSignature")
end

defmodule ExSolana.Geyser.SubscribeUpdateSlot do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:parent, 2, proto3_optional: true, type: :uint64)
  field(:status, 3, type: ExSolana.Geyser.CommitmentLevel, enum: true)
end

defmodule ExSolana.Geyser.SubscribeUpdateTransaction do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:transaction, 1, type: ExSolana.Geyser.SubscribeUpdateTransactionInfo)
  field(:slot, 2, type: :uint64)
end

defmodule ExSolana.Geyser.SubscribeUpdateTransactionInfo do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:signature, 1, type: :bytes)
  field(:is_vote, 2, type: :bool, json_name: "isVote")
  field(:transaction, 3, type: ExSolana.Solana.Storage.ConfirmedBlock.Transaction)
  field(:meta, 4, type: ExSolana.Solana.Storage.ConfirmedBlock.TransactionStatusMeta)
  field(:index, 5, type: :uint64)
end

defmodule ExSolana.Geyser.SubscribeUpdateTransactionStatus do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:signature, 2, type: :bytes)
  field(:is_vote, 3, type: :bool, json_name: "isVote")
  field(:index, 4, type: :uint64)
  field(:err, 5, type: ExSolana.Solana.Storage.ConfirmedBlock.TransactionError)
end

defmodule ExSolana.Geyser.SubscribeUpdateBlock do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:blockhash, 2, type: :string)
  field(:rewards, 3, type: ExSolana.Solana.Storage.ConfirmedBlock.Rewards)

  field(:block_time, 4,
    type: ExSolana.Solana.Storage.ConfirmedBlock.UnixTimestamp,
    json_name: "blockTime"
  )

  field(:block_height, 5,
    type: ExSolana.Solana.Storage.ConfirmedBlock.BlockHeight,
    json_name: "blockHeight"
  )

  field(:parent_slot, 7, type: :uint64, json_name: "parentSlot")
  field(:parent_blockhash, 8, type: :string, json_name: "parentBlockhash")
  field(:executed_transaction_count, 9, type: :uint64, json_name: "executedTransactionCount")
  field(:transactions, 6, repeated: true, type: ExSolana.Geyser.SubscribeUpdateTransactionInfo)
  field(:updated_account_count, 10, type: :uint64, json_name: "updatedAccountCount")
  field(:accounts, 11, repeated: true, type: ExSolana.Geyser.SubscribeUpdateAccountInfo)
  field(:entries_count, 12, type: :uint64, json_name: "entriesCount")
  field(:entries, 13, repeated: true, type: ExSolana.Geyser.SubscribeUpdateEntry)
end

defmodule ExSolana.Geyser.SubscribeUpdateBlockMeta do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:blockhash, 2, type: :string)
  field(:rewards, 3, type: ExSolana.Solana.Storage.ConfirmedBlock.Rewards)

  field(:block_time, 4,
    type: ExSolana.Solana.Storage.ConfirmedBlock.UnixTimestamp,
    json_name: "blockTime"
  )

  field(:block_height, 5,
    type: ExSolana.Solana.Storage.ConfirmedBlock.BlockHeight,
    json_name: "blockHeight"
  )

  field(:parent_slot, 6, type: :uint64, json_name: "parentSlot")
  field(:parent_blockhash, 7, type: :string, json_name: "parentBlockhash")
  field(:executed_transaction_count, 8, type: :uint64, json_name: "executedTransactionCount")
  field(:entries_count, 9, type: :uint64, json_name: "entriesCount")
end

defmodule ExSolana.Geyser.SubscribeUpdateEntry do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:index, 2, type: :uint64)
  field(:num_hashes, 3, type: :uint64, json_name: "numHashes")
  field(:hash, 4, type: :bytes)
  field(:executed_transaction_count, 5, type: :uint64, json_name: "executedTransactionCount")
  field(:starting_transaction_index, 6, type: :uint64, json_name: "startingTransactionIndex")
end

defmodule ExSolana.Geyser.SubscribeUpdatePing do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Geyser.SubscribeUpdatePong do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:id, 1, type: :int32)
end

defmodule ExSolana.Geyser.PingRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:count, 1, type: :int32)
end

defmodule ExSolana.Geyser.PongResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:count, 1, type: :int32)
end

defmodule ExSolana.Geyser.GetLatestBlockhashRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:commitment, 1, proto3_optional: true, type: ExSolana.Geyser.CommitmentLevel, enum: true)
end

defmodule ExSolana.Geyser.GetLatestBlockhashResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:blockhash, 2, type: :string)
  field(:last_valid_block_height, 3, type: :uint64, json_name: "lastValidBlockHeight")
end

defmodule ExSolana.Geyser.GetBlockHeightRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:commitment, 1, proto3_optional: true, type: ExSolana.Geyser.CommitmentLevel, enum: true)
end

defmodule ExSolana.Geyser.GetBlockHeightResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:block_height, 1, type: :uint64, json_name: "blockHeight")
end

defmodule ExSolana.Geyser.GetSlotRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:commitment, 1, proto3_optional: true, type: ExSolana.Geyser.CommitmentLevel, enum: true)
end

defmodule ExSolana.Geyser.GetSlotResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
end

defmodule ExSolana.Geyser.GetVersionRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Geyser.GetVersionResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:version, 1, type: :string)
end

defmodule ExSolana.Geyser.IsBlockhashValidRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:blockhash, 1, type: :string)
  field(:commitment, 2, proto3_optional: true, type: ExSolana.Geyser.CommitmentLevel, enum: true)
end

defmodule ExSolana.Geyser.IsBlockhashValidResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:valid, 2, type: :bool)
end

defmodule ExSolana.Geyser.Geyser.Service do
  @moduledoc false

  use GRPC.Service, name: "geyser.Geyser", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :Subscribe,
    stream(ExSolana.Geyser.SubscribeRequest),
    stream(ExSolana.Geyser.SubscribeUpdate),
    %{}
  )

  rpc(:Ping, ExSolana.Geyser.PingRequest, ExSolana.Geyser.PongResponse, %{})

  rpc(
    :GetLatestBlockhash,
    ExSolana.Geyser.GetLatestBlockhashRequest,
    ExSolana.Geyser.GetLatestBlockhashResponse,
    %{}
  )

  rpc(
    :GetBlockHeight,
    ExSolana.Geyser.GetBlockHeightRequest,
    ExSolana.Geyser.GetBlockHeightResponse,
    %{}
  )

  rpc(:GetSlot, ExSolana.Geyser.GetSlotRequest, ExSolana.Geyser.GetSlotResponse, %{})

  rpc(
    :IsBlockhashValid,
    ExSolana.Geyser.IsBlockhashValidRequest,
    ExSolana.Geyser.IsBlockhashValidResponse,
    %{}
  )

  rpc(:GetVersion, ExSolana.Geyser.GetVersionRequest, ExSolana.Geyser.GetVersionResponse, %{})
end

defmodule ExSolana.Geyser.Geyser.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Geyser.Geyser.Service
end
