defmodule ExSolana.Geyser.SubscribeUpdateTransaction do
  @moduledoc """
  Placeholder for Geyser SubscribeUpdateTransaction.

  This module is a placeholder until the Geyser package is fully migrated.
  The full Geyser functionality will be in the ex_solana_geyser package.
  """

  @type t :: %__MODULE__{
          slot: non_neg_integer(),
          transaction: map()
        }

  defstruct [:slot, :transaction]
end

defmodule ExSolana.Geyser.SubscribeUpdateTransactionInfo do
  @moduledoc false

  @type t :: %__MODULE__{
          transaction: map()
        }

  defstruct [:transaction]
end
