defmodule ExSolana.Ix do
  @moduledoc """
  High-level functions for creating and combining Solana instructions.
  """

  alias ExSolana.Ix.JitoTip
  alias ExSolana.Ix.Transfer
  alias ExSolana.Transaction

  @type builder :: Transaction.t()

  @spec transfer(builder(), keyword()) :: {:ok, builder()} | {:error, String.t()}
  defdelegate transfer(builder, opts), to: Transfer

  @spec jito_tip(builder(), keyword()) :: {:ok, builder()} | {:error, String.t()}
  defdelegate jito_tip(builder, opts), to: JitoTip
end
