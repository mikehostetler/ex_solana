defmodule ExSolana.Jito.Bundle.DroppedReason do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:BlockhashExpired, 0)
  field(:PartiallyProcessed, 1)
  field(:NotFinalized, 2)
end

defmodule ExSolana.Jito.Bundle.Bundle do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Packet.Packet
  alias ExSolana.Jito.Shared.Header

  field(:header, 2, type: Header)
  field(:packets, 3, repeated: true, type: Packet)
end

defmodule ExSolana.Jito.Bundle.BundleUuid do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle.Bundle

  field(:bundle, 1, type: Bundle)
  field(:uuid, 2, type: :string)
end

defmodule ExSolana.Jito.Bundle.Accepted do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slot, 1, type: :uint64)
  field(:validator_identity, 2, type: :string, json_name: "validatorIdentity")
end

defmodule ExSolana.Jito.Bundle.Rejected do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle.DroppedBundle
  alias ExSolana.Jito.Bundle.InternalError
  alias ExSolana.Jito.Bundle.SimulationFailure
  alias ExSolana.Jito.Bundle.StateAuctionBidRejected
  alias ExSolana.Jito.Bundle.WinningBatchBidRejected

  oneof(:reason, 0)

  field(:state_auction_bid_rejected, 1,
    type: StateAuctionBidRejected,
    json_name: "stateAuctionBidRejected",
    oneof: 0
  )

  field(:winning_batch_bid_rejected, 2,
    type: WinningBatchBidRejected,
    json_name: "winningBatchBidRejected",
    oneof: 0
  )

  field(:simulation_failure, 3,
    type: SimulationFailure,
    json_name: "simulationFailure",
    oneof: 0
  )

  field(:internal_error, 4,
    type: InternalError,
    json_name: "internalError",
    oneof: 0
  )

  field(:dropped_bundle, 5,
    type: DroppedBundle,
    json_name: "droppedBundle",
    oneof: 0
  )
end

defmodule ExSolana.Jito.Bundle.WinningBatchBidRejected do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:auction_id, 1, type: :string, json_name: "auctionId")
  field(:simulated_bid_lamports, 2, type: :uint64, json_name: "simulatedBidLamports")
  field(:msg, 3, proto3_optional: true, type: :string)
end

defmodule ExSolana.Jito.Bundle.StateAuctionBidRejected do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:auction_id, 1, type: :string, json_name: "auctionId")
  field(:simulated_bid_lamports, 2, type: :uint64, json_name: "simulatedBidLamports")
  field(:msg, 3, proto3_optional: true, type: :string)
end

defmodule ExSolana.Jito.Bundle.SimulationFailure do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:tx_signature, 1, type: :string, json_name: "txSignature")
  field(:msg, 2, proto3_optional: true, type: :string)
end

defmodule ExSolana.Jito.Bundle.InternalError do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:msg, 1, type: :string)
end

defmodule ExSolana.Jito.Bundle.DroppedBundle do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:msg, 1, type: :string)
end

defmodule ExSolana.Jito.Bundle.Finalized do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Bundle.Processed do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:validator_identity, 1, type: :string, json_name: "validatorIdentity")
  field(:slot, 2, type: :uint64)
  field(:bundle_index, 3, type: :uint64, json_name: "bundleIndex")
end

defmodule ExSolana.Jito.Bundle.Dropped do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle.DroppedReason

  field(:reason, 1, type: DroppedReason, enum: true)
end

defmodule ExSolana.Jito.Bundle.BundleResult do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle

  oneof(:result, 0)

  field(:bundle_id, 1, type: :string, json_name: "bundleId")
  field(:accepted, 2, type: Bundle.Accepted, oneof: 0)
  field(:rejected, 3, type: Bundle.Rejected, oneof: 0)
  field(:finalized, 4, type: Bundle.Finalized, oneof: 0)
  field(:processed, 5, type: Bundle.Processed, oneof: 0)
  field(:dropped, 6, type: Bundle.Dropped, oneof: 0)
end
