defmodule ExSolana.TxnAction do
  @moduledoc false
  use TypedStruct

  typedstruct do
    field(:type, atom(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:details, map(), default: %{})
  end
end
