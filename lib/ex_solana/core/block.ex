defmodule ExSolana.Block do
  @moduledoc false
  use TypedStruct

  typedstruct module: ConfirmedBlock do
    field(:previous_blockhash, String.t())
    field(:blockhash, String.t())
    field(:parent_slot, non_neg_integer())
    field(:transactions, list(ConfirmedTransaction.t()))
    field(:rewards, list(Reward.t()))
    field(:block_time, UnixTimestamp.t())
    field(:block_height, BlockHeight.t())
    field(:num_partitions, NumPartitions.t())
  end
end
