# defmodule ExSolana.IDL.Instruction do
#   @moduledoc """
#   Defines the behaviour and provides a macro for Solana IDL instructions.

#   This module offers a standardized way to define instruction structs
#   with encoding, decoding, and account information capabilities.
#   """

#   @doc """
#   When used, defines a standard structure for Solana IDL instructions.

#   It automatically implements the ExSolana.IDL.Instruction behaviour
#   and provides default implementations for new/1, encode/1, and decode/1.
#   """
#   defmacro __using__(_opts) do
#     quote do
#       @behaviour ExSolana.IDL.Instruction

#       @doc """
#       Creates a new instruction struct with the given attributes.
#       """
#       @impl ExSolana.IDL.Instruction
#       def new(attrs \\ []) do
#         struct!(__MODULE__, attrs)
#       end

#       @doc """
#       Encodes the instruction struct to binary format.
#       """
#       @impl ExSolana.IDL.Instruction
#       def encode(instruction) do
#         ExSolana.IDL.Codec.encode(instruction)
#       end

#       @doc """
#       Decodes binary data into an instruction struct.
#       """
#       @impl ExSolana.IDL.Instruction
#       def decode(data) do
#         ExSolana.IDL.Codec.decode(data)
#       end

#       @doc """
#       Returns a list of account metadata required for this instruction.
#       """
#       @impl ExSolana.IDL.Instruction
#       def accounts, do: []

#       defoverridable new: 1, encode: 1, decode: 1, accounts: 0
#     end
#   end

#   @doc """
#   Callback to create a new instruction struct.
#   """
#   @callback new(attrs :: keyword()) :: struct()

#   @doc """
#   Callback to encode an instruction struct to binary.
#   """
#   @callback encode(instruction :: struct()) :: binary()

#   @doc """
#   Callback to decode binary data into an instruction struct.
#   """
#   @callback decode(data :: binary()) :: {:ok, struct()} | {:error, term()}

#   @doc """
#   Callback to return a list of account metadata required for this instruction.
#   """
#   @callback accounts() :: list(map())
# end
