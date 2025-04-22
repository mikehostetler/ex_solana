defmodule ExSolana.Jito.Searcher.SlotList do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:slots, 1, repeated: true, type: :uint64)
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersResponse.ConnectedValidatorsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Jito.Searcher.SlotList)
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:connected_validators, 1,
    repeated: true,
    type: ExSolana.Jito.Searcher.ConnectedLeadersResponse.ConnectedValidatorsEntry,
    json_name: "connectedValidators",
    map: true
  )
end

defmodule ExSolana.Jito.Searcher.SendBundleRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:bundle, 1, type: ExSolana.Jito.Bundle.Bundle)
end

defmodule ExSolana.Jito.Searcher.SendBundleResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:uuid, 1, type: :string)
end

defmodule ExSolana.Jito.Searcher.NextScheduledLeaderRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:regions, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.Searcher.NextScheduledLeaderResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:current_slot, 1, type: :uint64, json_name: "currentSlot")
  field(:next_leader_slot, 2, type: :uint64, json_name: "nextLeaderSlot")
  field(:next_leader_identity, 3, type: :string, json_name: "nextLeaderIdentity")
  field(:next_leader_region, 4, type: :string, json_name: "nextLeaderRegion")
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersRegionedRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:regions, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersRegionedResponse.ConnectedValidatorsEntry do
  @moduledoc false
  use Protobuf, map: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:key, 1, type: :string)
  field(:value, 2, type: ExSolana.Jito.Searcher.ConnectedLeadersResponse)
end

defmodule ExSolana.Jito.Searcher.ConnectedLeadersRegionedResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:connected_validators, 1,
    repeated: true,
    type: ExSolana.Jito.Searcher.ConnectedLeadersRegionedResponse.ConnectedValidatorsEntry,
    json_name: "connectedValidators",
    map: true
  )
end

defmodule ExSolana.Jito.Searcher.GetTipAccountsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Searcher.GetTipAccountsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:accounts, 1, repeated: true, type: :string)
end

defmodule ExSolana.Jito.Searcher.SubscribeBundleResultsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Searcher.GetRegionsRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"
end

defmodule ExSolana.Jito.Searcher.GetRegionsResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:current_region, 1, type: :string, json_name: "currentRegion")
  field(:available_regions, 2, repeated: true, type: :string, json_name: "availableRegions")
end

defmodule ExSolana.Jito.Searcher.SearcherService.Service do
  @moduledoc false

  use GRPC.Service, name: "searcher.SearcherService", protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Bundle

  rpc(
    :SubscribeBundleResults,
    ExSolana.Jito.Searcher.SubscribeBundleResultsRequest,
    stream(Bundle.BundleResult),
    %{}
  )

  rpc(
    :SendBundle,
    ExSolana.Jito.Searcher.SendBundleRequest,
    ExSolana.Jito.Searcher.SendBundleResponse,
    %{}
  )

  rpc(
    :GetNextScheduledLeader,
    ExSolana.Jito.Searcher.NextScheduledLeaderRequest,
    ExSolana.Jito.Searcher.NextScheduledLeaderResponse,
    %{}
  )

  rpc(
    :GetConnectedLeaders,
    ExSolana.Jito.Searcher.ConnectedLeadersRequest,
    ExSolana.Jito.Searcher.ConnectedLeadersResponse,
    %{}
  )

  rpc(
    :GetConnectedLeadersRegioned,
    ExSolana.Jito.Searcher.ConnectedLeadersRegionedRequest,
    ExSolana.Jito.Searcher.ConnectedLeadersRegionedResponse,
    %{}
  )

  rpc(
    :GetTipAccounts,
    ExSolana.Jito.Searcher.GetTipAccountsRequest,
    ExSolana.Jito.Searcher.GetTipAccountsResponse,
    %{}
  )

  rpc(
    :GetRegions,
    ExSolana.Jito.Searcher.GetRegionsRequest,
    ExSolana.Jito.Searcher.GetRegionsResponse,
    %{}
  )
end

defmodule ExSolana.Jito.Searcher.SearcherService.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.Searcher.SearcherService.Service
end
