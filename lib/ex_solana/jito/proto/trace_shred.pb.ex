defmodule ExSolana.Jito.TraceShred.TraceShred do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field :region, 1, type: :string
  field :created_at, 2, type: Google.Protobuf.Timestamp, json_name: "createdAt"
  field :seq_num, 3, type: :uint32, json_name: "seqNum"
end
