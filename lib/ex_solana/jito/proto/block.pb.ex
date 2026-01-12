defmodule ExSolana.Jito.Block.CondensedBlock do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Shared.Header

  field(:header, 1, type: Header)
  field(:previous_blockhash, 2, type: :string, json_name: "previousBlockhash")
  field(:blockhash, 3, type: :string)
  field(:parent_slot, 4, type: :uint64, json_name: "parentSlot")

  field(:versioned_transactions, 5,
    repeated: true,
    type: :bytes,
    json_name: "versionedTransactions"
  )

  field(:slot, 6, type: :uint64)
  field(:commitment, 7, type: :string)
end
