defmodule ExSolana.Jito.Relayer.GetTpuConfigsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Relayer.GetTpuConfigsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:tpu, 1, type: Shared.Socket)
  field(:tpu_forward, 2, type: Shared.Socket, json_name: "tpuForward")
end

defmodule ExSolana.Jito.Relayer.SubscribePacketsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Relayer.SubscribePacketsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  oneof(:msg, 0)

  field(:header, 1, type: Shared.Header)
  field(:heartbeat, 2, type: Shared.Heartbeat, oneof: 0)
  field(:batch, 3, type: Packet.PacketBatch, oneof: 0)
end

defmodule ExSolana.Jito.Relayer.Relayer.Service do
  @moduledoc false

  use GRPC.Service, name: "relayer.Relayer", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :GetTpuConfigs,
    ExSolana.Jito.Relayer.GetTpuConfigsRequest,
    ExSolana.Jito.Relayer.GetTpuConfigsResponse,
    %{}
  )

  rpc(
    :SubscribePackets,
    ExSolana.Jito.Relayer.SubscribePacketsRequest,
    stream(ExSolana.Jito.Relayer.SubscribePacketsResponse),
    %{}
  )
end

defmodule ExSolana.Jito.Relayer.Relayer.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.Relayer.Relayer.Service
end
