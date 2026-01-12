defmodule ExSolana.Geyser do
  @moduledoc """
  The main module for interacting with Yellowstone Geyser gRPC service.
  """

  @doc """
  Creates a new Geyser client connection.

  ## Parameters

  - url: The URL of the Yellowstone Geyser service
  - opts: Additional options for the gRPC connection

  ## Options

  - :cred - a GRPC.Credential used for secure connections
  - :adapter - custom client adapter
  - :interceptors - client interceptors
  - :codec - codec for encoding and decoding binary messages
  - :compressor - compressor for requests and responses
  - :accepted_compressors - list of accepted compressors
  - :headers - headers to attach to each request
  - :token - the authentication token to be sent as "x-token" header

  ## Returns

  A tuple containing :ok and the client connection, or :error and the reason.
  """
  @spec new(String.t(), keyword()) :: {:ok, GRPC.Channel.t()} | {:error, any()}
  def new(url, opts \\ []) do
    ExSolana.GRPCClientBase.new(url, opts, "Yellowstone Geyser service")
  end
end
