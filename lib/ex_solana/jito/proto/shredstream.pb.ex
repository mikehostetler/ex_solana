defmodule ExSolana.Jito.Shredstream.Heartbeat do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:socket, 1, type: Shared.Socket)
  field(:regions, 2, repeated: true, type: :string)
end

defmodule ExSolana.Jito.Shredstream.HeartbeatResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:ttl_ms, 1, type: :uint32, json_name: "ttlMs")
end

defmodule ExSolana.Jito.Shredstream.Shredstream.Service do
  @moduledoc false

  use GRPC.Service, name: "shredstream.Shredstream", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :SendHeartbeat,
    ExSolana.Jito.Shredstream.Heartbeat,
    ExSolana.Jito.Shredstream.HeartbeatResponse,
    %{}
  )
end

defmodule ExSolana.Jito.Shredstream.Shredstream.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.Shredstream.Shredstream.Service
end
