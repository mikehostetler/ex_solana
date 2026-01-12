defmodule ExSolana.Jito.Shared.Header do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:ts, 1, type: Google.Protobuf.Timestamp)
end

defmodule ExSolana.Jito.Shared.Heartbeat do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:count, 1, type: :uint64)
end

defmodule ExSolana.Jito.Shared.Socket do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:ip, 1, type: :string)
  field(:port, 2, type: :int64)
end
