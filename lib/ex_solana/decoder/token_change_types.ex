defmodule ExSolana.Decoder.SolBalanceChange do
  @moduledoc false
  @type t :: %__MODULE__{
          address: binary(),
          name: String.t(),
          writable?: boolean(),
          signer?: boolean(),
          fee_payer?: boolean(),
          before: non_neg_integer(),
          after: non_neg_integer(),
          change: integer()
        }

  defstruct [
    :address,
    :name,
    :writable?,
    :signer?,
    :fee_payer?,
    :before,
    :after,
    :change
  ]
end

defmodule ExSolana.Decoder.TokenBalanceChange do
  @moduledoc false
  alias ExSolana.Transaction.Core.UiTokenAmount

  @type t :: %__MODULE__{
          owner: String.t(),
          address: binary(),
          before: String.t(),
          after: String.t(),
          change: String.t(),
          token_mint_address: String.t(),
          ui_amount_before: UiTokenAmount.t() | nil,
          ui_amount_after: UiTokenAmount.t() | nil
        }

  defstruct [
    :owner,
    :address,
    :before,
    :after,
    :change,
    :token_mint_address,
    :ui_amount_before,
    :ui_amount_after
  ]
end
