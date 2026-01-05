defmodule ExSolana.Jito.Auth.Role do
  @moduledoc false
  use Protobuf, enum: true, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:RELAYER, 0)
  field(:SEARCHER, 1)
  field(:VALIDATOR, 2)
  field(:SHREDSTREAM_SUBSCRIBER, 3)
end

defmodule ExSolana.Jito.Auth.GenerateAuthChallengeRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:role, 1, type: ExSolana.Jito.Auth.Role, enum: true)
  field(:pubkey, 2, type: :bytes)
end

defmodule ExSolana.Jito.Auth.GenerateAuthChallengeResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:challenge, 1, type: :string)
end

defmodule ExSolana.Jito.Auth.GenerateAuthTokensRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:challenge, 1, type: :string)
  field(:client_pubkey, 2, type: :bytes, json_name: "clientPubkey")
  field(:signed_challenge, 3, type: :bytes, json_name: "signedChallenge")
end

defmodule ExSolana.Jito.Auth.Token do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:value, 1, type: :string)
  field(:expires_at_utc, 2, type: Google.Protobuf.Timestamp, json_name: "expiresAtUtc")
end

defmodule ExSolana.Jito.Auth.GenerateAuthTokensResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  alias ExSolana.Jito.Auth.Token

  field(:access_token, 1, type: Token, json_name: "accessToken")
  field(:refresh_token, 2, type: Token, json_name: "refreshToken")
end

defmodule ExSolana.Jito.Auth.RefreshAccessTokenRequest do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:refresh_token, 1, type: :string, json_name: "refreshToken")
end

defmodule ExSolana.Jito.Auth.RefreshAccessTokenResponse do
  @moduledoc false
  use Protobuf, syntax: :proto3, protoc_gen_elixir_version: "0.12.0"

  field(:access_token, 1, type: ExSolana.Jito.Auth.Token, json_name: "accessToken")
end

defmodule ExSolana.Jito.Auth.AuthService.Service do
  @moduledoc false

  use GRPC.Service, name: "auth.AuthService", protoc_gen_elixir_version: "0.12.0"

  rpc(
    :GenerateAuthChallenge,
    ExSolana.Jito.Auth.GenerateAuthChallengeRequest,
    ExSolana.Jito.Auth.GenerateAuthChallengeResponse,
    %{}
  )

  rpc(
    :GenerateAuthTokens,
    ExSolana.Jito.Auth.GenerateAuthTokensRequest,
    ExSolana.Jito.Auth.GenerateAuthTokensResponse,
    %{}
  )

  rpc(
    :RefreshAccessToken,
    ExSolana.Jito.Auth.RefreshAccessTokenRequest,
    ExSolana.Jito.Auth.RefreshAccessTokenResponse,
    %{}
  )
end

defmodule ExSolana.Jito.Auth.AuthService.Stub do
  @moduledoc false

  use GRPC.Stub, service: ExSolana.Jito.Auth.AuthService.Service
end
