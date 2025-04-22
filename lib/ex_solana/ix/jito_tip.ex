defmodule ExSolana.Ix.JitoTip do
  @moduledoc """
  Functions for creating a Jito Tip instruction.
  """

  alias ExSolana.Jito.TipServer
  alias ExSolana.Native.SystemProgram
  alias ExSolana.Transaction.Builder

  require Logger

  @jito_tip_wallets [
    "96gYZGLnJYVFmbjzopPSU6QiEV5fGqZNyN9nmNhvrZU5",
    "HFqU5x63VTqvQss8hp11i4wVV8bD44PvwucfZ2bU7gRe",
    "Cw8CFyM9FkoMi7K7Crf6HNQqf4uEMzpKw6QNghXLvLkY",
    "ADaUMid9yfUytqMBgopwjb2DTLSokTSzL1zt6iGPaS49",
    "DfXygSm4jCyNCybVYYK6DwvWqjKee8pbDmJGcLWNDXjh",
    "ADuUkR4vqLUMWXxW9gh6D6L8pMSawimctcNZ5pGwDcEt",
    "DttWaMuVvTiduZRnguLF7jNxTgiMBZ1hyAumKUiL2KRL",
    "3AVi9Tg9Uo68tJfuvoKvqKNWKkC5wPdSSdeBnizKZ6jT"
  ]

  @jito_tip_options [
    percentile: [
      type: {:in, [25, 50, 75, 95, 99]},
      default: 75,
      doc: "The percentile of the tip amount to use (25, 50, 75, 95, or 99)"
    ],
    custom_amount: [
      type: :non_neg_integer,
      doc: "A custom tip amount in lamports. If provided, overrides the percentile option."
    ]
  ]

  @doc """
  Adds a Jito Tip instruction to the transaction builder.

  ## Options

  #{NimbleOptions.docs(@jito_tip_options)}

  ## Examples

      iex> ExSolana.Transaction.Builder.new()
      ...> |> ExSolana.Ix.JitoTip.jito_tip(percentile: 75)

      iex> ExSolana.Transaction.Builder.new()
      ...> |> ExSolana.Ix.JitoTip.jito_tip(custom_amount: 1_000_000)

  """
  @spec jito_tip(Builder.t(), Keyword.t()) :: Builder.t()
  def jito_tip(builder \\ Builder.new(), opts) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @jito_tip_options),
         {:ok, tip_amount} <- get_tip_amount(validated_opts),
         {:ok, tip_account} <- random_tip_account() do
      instruction =
        SystemProgram.transfer(
          lamports: tip_amount,
          from: builder.payer,
          to: ExSolana.pubkey!(tip_account)
        )

      Logger.debug("Adding Jito Tip to #{tip_account} for #{tip_amount} lamports")
      Builder.add_instruction(builder, instruction)
    else
      {:error, reason} ->
        raise ArgumentError, message: "Invalid Jito Tip options: #{inspect(reason)}"
    end
  end

  @spec get_tip_amount(map()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  defp get_tip_amount(%{custom_amount: amount}) when is_integer(amount) and amount >= 0 do
    {:ok, amount}
  end

  defp get_tip_amount(opts) do
    percentile = Keyword.fetch!(opts, :percentile)

    case TipServer.get_latest_tips() do
      {:ok, tips} ->
        tip_key = :"landed_tips_#{percentile}th_percentile"
        tip_amount = Map.get(tips, tip_key)
        {:ok, tip_amount}

      {:error, reason} ->
        {:error, "Failed to get latest Jito tips: #{inspect(reason)}"}
    end
  end

  @spec random_tip_account() :: {:ok, String.t()}
  def random_tip_account do
    {:ok, Enum.random(@jito_tip_wallets)}
  end
end
