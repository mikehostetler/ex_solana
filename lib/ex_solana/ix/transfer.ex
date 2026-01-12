defmodule ExSolana.Ix.Transfer do
  @moduledoc """
  Functions for creating a Transfer instruction.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.Native.SystemProgram
  alias ExSolana.Transaction.Builder

  require Logger

  @transfer_options [
    from: [
      type: :string,
      required: true,
      doc: "The source account (public key) of the transfer"
    ],
    to: [
      type: :string,
      required: true,
      doc: "The destination account (public key) of the transfer"
    ],
    lamports: [
      type: :non_neg_integer,
      required: true,
      doc: "The amount of lamports to transfer"
    ]
  ]

  @doc """
  Creates a Transfer instruction and adds it to the transaction builder.

  ## Options

  #{NimbleOptions.docs(@transfer_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/programming-model/calling-between-programs#system-instruction-transfer).
  """
  @spec transfer(Builder.t(), keyword()) :: Builder.t()
  def transfer(builder \\ Builder.new(), opts) do
    case validate(opts, @transfer_options) do
      {:ok, validated_opts} ->
        with {:ok, from} <- decode_if_base58(validated_opts[:from]),
             {:ok, to} <- decode_if_base58(validated_opts[:to]) do
          instruction =
            SystemProgram.transfer(
              lamports: validated_opts[:lamports],
              from: from,
              to: to
            )

          Builder.add_instruction(builder, instruction)
        else
          {:error, reason} ->
            Logger.warning("Transfer failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.warning("Validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
