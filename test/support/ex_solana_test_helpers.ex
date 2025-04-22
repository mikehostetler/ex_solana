defmodule ExSolana.TestHelpers do
  @moduledoc """
  Some helper functions for testing Solana programs.
  """
  alias ExSolana.RPC

  @doc """
  Creates an account and airdrops some SOL to it. This is useful when creating
  other accounts and you need an account to pay the rent fees.
  """
  @spec create_payer(tracker :: pid, ExSolana.RPC.client(), keyword) ::
          {:ok, ExSolana.keypair()} | {:error, :timeout}
  def create_payer(tracker, client, opts \\ []) do
    payer = ExSolana.keypair()

    lamports = Keyword.get(opts, :amount, 5) * ExSolana.lamports_per_sol()
    timeout = Keyword.get(opts, :timeout, 5_000)
    request_opts = Keyword.take(opts, [:commitment])

    {:ok, tx} =
      ExSolana.send(RPC.Request.request_airdrop(ExSolana.pubkey!(payer), lamports, request_opts))

    :ok = ExSolana.RPC.Tracker.start_tracking(tracker, tx, request_opts)

    receive do
      {:ok, [^tx]} -> {:ok, payer}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  Generates a list of `n` keypairs.
  """
  @spec keypairs(n :: pos_integer) :: [ExSolana.keypair()]
  def keypairs(n) do
    Enum.map(1..n, fn _ -> ExSolana.keypair() end)
  end

  @doc """
  Loads a sample transaction from a JSON file.
  """
  def load_sample_transactions do
    path = Path.join(["test", "fixtures", "binary_tx_samples"])

    path
    |> Path.join("*.binary")
    |> Path.wildcard()
    |> Enum.map(fn file ->
      {:ok, binary} = File.read(file)

      %ExSolana.Geyser.SubscribeUpdate{
        update_oneof: {:transaction, %ExSolana.Geyser.SubscribeUpdateTransaction{} = transaction}
      } = :erlang.binary_to_term(binary)

      transaction
    end)
  end

  def get_in_struct(struct, keys) do
    Enum.reduce(keys, struct, fn
      _key, nil -> nil
      key, acc when is_struct(acc) -> Map.get(acc, key)
      key, acc when is_map(acc) -> Map.get(acc, key)
      _key, _acc -> nil
    end)
  end
end
