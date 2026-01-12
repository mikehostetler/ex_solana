defmodule ExSolana.SolBalanceChange do
  @moduledoc """
  Represents SOL balance changes for an account in a transaction.

  Used by the decoder to track how SOL balances changed before and after
  a transaction.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              address: Zoi.string(description: "Account address (32 bytes)"),
              name:
                Zoi.string(description: "Account name (optional)")
                |> Zoi.optional(),
              writable: Zoi.boolean(description: "Whether account is writable"),
              signer: Zoi.boolean(description: "Whether account is a signer"),
              fee_payer: Zoi.boolean(description: "Whether account paid the transaction fee"),
              before: Zoi.integer(description: "Balance before transaction (in lamports)"),
              after: Zoi.integer(description: "Balance after transaction (in lamports)"),
              change: Zoi.integer(description: "Balance change (can be negative)")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end

defmodule ExSolana.TokenBalanceChange do
  @moduledoc """
  Represents token balance changes for an account in a transaction.

  Used by the decoder to track how SPL token balances changed before and
  after a transaction.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              owner: Zoi.string(description: "Token account owner"),
              address: Zoi.string(description: "Token account address (32 bytes)"),
              before: Zoi.string(description: "Token balance before (as string)"),
              after: Zoi.string(description: "Token balance after (as string)"),
              change: Zoi.string(description: "Balance change (as string)"),
              token_mint_address: Zoi.string(description: "Token mint address"),
              ui_amount_before:
                Zoi.map(description: "UI amount before (decoded from UiTokenAmount)")
                |> Zoi.optional(),
              ui_amount_after:
                Zoi.map(description: "UI amount after (decoded from UiTokenAmount)")
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end
