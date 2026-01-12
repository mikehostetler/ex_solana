defmodule ExSolana.Native.SystemProgram do
  @moduledoc """
  Functions for interacting with Solana's [System
  Program](https://docs.solana.com/developing/runtime-facilities/programs#system-program)

  This module provides basic System Program functionality for use within ex_solana.
  For full System Program implementation with IDL support, use ExSolanaPrograms.Native.SystemProgram.
  """

  import ExSolana.Util.Helpers

  alias ExSolana.Account
  alias ExSolana.Instruction

  @doc """
  The System Program's program ID.
  """
  def id, do: ExSolana.pubkey!("11111111111111111111111111111111")

  @transfer_schema [
    lamports: [
      type: :pos_integer,
      required: true,
      doc: "Amount of lamports to transfer"
    ],
    from: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Account that will transfer lamports"
    ],
    to: [
      type: {:custom, ExSolana.Key, :check, []},
      required: true,
      doc: "Account that will receive the transferred lamports"
    ]
  ]

  @doc """
  Generates instructions to transfer lamports from one account to another.

  ## Options

  #{NimbleOptions.docs(@transfer_schema)}
  """
  def transfer(opts) do
    case NimbleOptions.validate(opts, @transfer_schema) do
      {:ok, params} ->
        transfer_ix(params)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp transfer_ix(params) do
    %Instruction{
      program: id(),
      accounts: [
        %Account{key: params.from, signer?: true, writable?: true},
        %Account{key: params.to, writable?: true}
      ],
      data: Instruction.encode_data([{2, 32}, {params.lamports, 64}])
    }
  end
end
