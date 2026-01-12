# defmodule ExSolana.IDL.Account do
#   @moduledoc """
#   Represents an account in the Solana IDL.
#   """
#   @doc """
#   When used, defines common behavior for IDL accounts.

#   This macro defines the following:
#   - A `new/1` function to create a new account struct
#   - An `encode/1` function to encode the account struct to binary
#   - A `decode/1` function to decode binary data into an account struct
#   """
#   defmacro __using__(_opts) do
#     quote do
#       @behaviour ExSolana.IDL.Account

#       @doc """
#       Creates a new account struct with the given attributes.
#       """
#       @impl ExSolana.IDL.Account
#       def new(attrs \\ []) do
#         struct!(__MODULE__, attrs)
#       end

#       @doc """
#       Encodes the account struct to binary format.
#       """
#       @impl ExSolana.IDL.Account
#       def encode(account) do
#         ExSolana.IDL.Codec.encode(account)
#       end

#       @doc """
#       Decodes binary data into an account struct.
#       """
#       @impl ExSolana.IDL.Account
#       def decode(data) do
#         ExSolana.IDL.Codec.decode(data)
#       end

#       defoverridable new: 1, encode: 1, decode: 1
#     end
#   end

#   @doc """
#   Callback to create a new account struct.
#   """
#   @callback new(attrs :: keyword()) :: struct()

#   @doc """
#   Callback to encode an account struct to binary.
#   """
#   @callback encode(account :: struct()) :: binary()

#   @doc """
#   Callback to decode binary data into an account struct.
#   """
#   @callback decode(data :: binary()) :: {:ok, struct()} | {:error, term()}
# end
