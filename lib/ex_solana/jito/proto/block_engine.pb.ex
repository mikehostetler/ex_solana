defmodule ExSolana.Jito.BlockEngine.SubscribePacketsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.BlockEngine.SubscribePacketsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Packet.PacketBatch
  alias ExSolana.Jito.Shared.Header

  field(:header, 1, type: Header)
  field(:batch, 2, type: PacketBatch)
end

defmodule ExSolana.Jito.BlockEngine.SubscribeBundlesRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.BlockEngine.SubscribeBundlesResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle.BundleUuid

  field(:bundles, 1, repeated: true, type: BundleUuid)
end

defmodule ExSolana.Jito.BlockEngine.BlockBuilderFeeInfoRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.BlockEngine.BlockBuilderFeeInfoResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:pubkey, 1, type: :string)
  field(:commission, 2, type: :uint64)
end

defmodule ExSolana.Jito.BlockEngine.AccountsOfInterest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:accounts, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.BlockEngine.AccountsOfInterestRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.BlockEngine.AccountsOfInterestUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:accounts, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.BlockEngine.ProgramsOfInterestRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.BlockEngine.ProgramsOfInterestUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:programs, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.BlockEngine.ExpiringPacketBatch do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Packet.PacketBatch
  alias ExSolana.Jito.Shared.Header

  field(:header, 1, type: Header)
  field(:batch, 2, type: PacketBatch)
  field(:expiry_ms, 3, type: :uint32, json_name: "expiryMs")
end

defmodule ExSolana.Jito.BlockEngine.PacketBatchUpdate do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Shared.Heartbeat

  oneof(:msg, 0)

  field(:batches, 1, type: ExSolana.Jito.BlockEngine.ExpiringPacketBatch, oneof: 0)
  field(:heartbeat, 2, type: Heartbeat, oneof: 0)
end

defmodule ExSolana.Jito.BlockEngine.StartExpiringPacketStreamResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Shared.Heartbeat

  field(:heartbeat, 1, type: Heartbeat)
end

defmodule ExSolana.Jito.BlockEngine.BlockEngineValidator.Service do
  @moduledoc false

  use GRPC.Service, name: "block_engine.BlockEngineValidator", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :SubscribePackets,
    ExSolana.Jito.BlockEngine.SubscribePacketsRequest,
    stream(ExSolana.Jito.BlockEngine.SubscribePacketsResponse),
    %{}
  )

  rpc(
    :SubscribeBundles,
    ExSolana.Jito.BlockEngine.SubscribeBundlesRequest,
    stream(ExSolana.Jito.BlockEngine.SubscribeBundlesResponse),
    %{}
  )

  rpc(
    :GetBlockBuilderFeeInfo,
    ExSolana.Jito.BlockEngine.BlockBuilderFeeInfoRequest,
    ExSolana.Jito.BlockEngine.BlockBuilderFeeInfoResponse,
    %{}
  )
end

defmodule ExSolana.Jito.BlockEngine.BlockEngineValidator.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.BlockEngine.BlockEngineValidator.Service
end

defmodule ExSolana.Jito.BlockEngine.BlockEngineRelayer.Service do
  @moduledoc false

  use GRPC.Service, name: "block_engine.BlockEngineRelayer", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :SubscribeAccountsOfInterest,
    ExSolana.Jito.BlockEngine.AccountsOfInterestRequest,
    stream(ExSolana.Jito.BlockEngine.AccountsOfInterestUpdate),
    %{}
  )

  rpc(
    :SubscribeProgramsOfInterest,
    ExSolana.Jito.BlockEngine.ProgramsOfInterestRequest,
    stream(ExSolana.Jito.BlockEngine.ProgramsOfInterestUpdate),
    %{}
  )

  rpc(
    :StartExpiringPacketStream,
    stream(ExSolana.Jito.BlockEngine.PacketBatchUpdate),
    stream(ExSolana.Jito.BlockEngine.StartExpiringPacketStreamResponse),
    %{}
  )
end

defmodule ExSolana.Jito.BlockEngine.BlockEngineRelayer.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.BlockEngine.BlockEngineRelayer.Service
end
