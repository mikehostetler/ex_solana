defmodule ExSolana.Decoder.SolBalanceChange do
  @moduledoc false
  use TypedStruct

  typedstruct do
    field(:address, binary())
    field(:name, String.t())
    field(:writable?, boolean())
    field(:signer?, boolean())
    field(:fee_payer?, boolean())
    field(:before, non_neg_integer())
    field(:after, non_neg_integer())
    field(:change, integer())
  end
end

defmodule ExSolana.Decoder.TokenBalanceChange do
  @moduledoc false
  use TypedStruct

  alias ExSolana.Transaction.Core.UiTokenAmount

  typedstruct do
    field(:owner, String.t())
    field(:address, binary())
    field(:before, String.t())
    field(:after, String.t())
    field(:change, String.t())
    field(:token_mint_address, String.t())
    field(:ui_amount_before, UiTokenAmount.t())
    field(:ui_amount_after, UiTokenAmount.t())
  end
end
