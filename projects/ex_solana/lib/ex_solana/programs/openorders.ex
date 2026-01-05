defmodule ExSolana.Program.OpenOrders.V1 do
  @moduledoc """
  Represents and decodes an Open Orders V1 account.
  """

  use ExSolana.Borsh,
    schema: [
      blob: ["u8", 5],
      account_flags: "u64",
      market: "pubkey",
      owner: "pubkey",
      base_token_free: "u64",
      base_token_total: "u64",
      quote_token_free: "u64",
      quote_token_total: "u64",
      free_slot_bits: "u128",
      is_bid_bits: "u128",
      orders: ["u128", 128],
      client_ids: ["u64", 128],
      padding: ["u8", 7]
    ]
end

defmodule ExSolana.Program.OpenOrders.V2 do
  @moduledoc """
  Represents and decodes an Open Orders V2 account.
  """

  use ExSolana.Borsh,
    schema: [
      blob: ["u8", 5],
      account_flags: "u64",
      market: "pubkey",
      owner: "pubkey",
      base_token_free: "u64",
      base_token_total: "u64",
      quote_token_free: "u64",
      quote_token_total: "u64",
      free_slot_bits: "u128",
      is_bid_bits: "u128",
      orders: ["u128", 128],
      client_ids: ["u64", 128],
      referrer_rebates_accrued: "u64",
      padding: ["u8", 7]
    ]
end

defmodule ExSolana.Program.OpenOrders do
  @moduledoc """
  Defines account structures and decoders for Open Orders accounts.
  """

  alias ExSolana.Program.OpenOrders.V1
  alias ExSolana.Program.OpenOrders.V2

  @doc """
  Attempts to decode the given binary data as an Open Orders account.
  It tries V2 first, and if that fails, it falls back to V1.
  """
  @spec decode(binary()) :: {:ok, V2.t() | V1.t()} | {:error, String.t()}
  def decode(data) do
    case V2.decode(data) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, _} ->
        case V1.decode(data) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Failed to decode as either Open Orders V1 or V2"}
        end
    end
  end
end
