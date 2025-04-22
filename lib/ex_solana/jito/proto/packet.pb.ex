defmodule ExSolana.Jito.Packet.PacketBatch do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:packets, 1, repeated: true, type: ExSolana.Jito.Packet.Packet)
end

defmodule ExSolana.Jito.Packet.Packet do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:data, 1, type: :bytes)
  field(:meta, 2, type: ExSolana.Jito.Packet.Meta)
end

defmodule ExSolana.Jito.Packet.Meta do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:size, 1, type: :uint64)
  field(:addr, 2, type: :string)
  field(:port, 3, type: :uint32)
  field(:flags, 4, type: ExSolana.Jito.Packet.PacketFlags)
  field(:sender_stake, 5, type: :uint64, json_name: "senderStake")
end

defmodule ExSolana.Jito.Packet.PacketFlags do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:discard, 1, type: :bool)
  field(:forwarded, 2, type: :bool)
  field(:repair, 3, type: :bool)
  field(:simple_vote_tx, 4, type: :bool, json_name: "simpleVoteTx")
  field(:tracer_packet, 5, type: :bool, json_name: "tracerPacket")
  field(:from_staked_node, 6, type: :bool, json_name: "fromStakedNode")
end
