defmodule ExSolana do
  @moduledoc """
  A library for interacting with the Solana blockchain.
  """
  alias ExSolana.RPC
  alias ExSolana.RPC.Tracker

  defmacro __using__(_opts) do
    quote do
      use Supervisor

      def start_link(init_arg) do
        Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      @impl true
      def init(_init_arg) do
        client = ExSolana.rpc_client()

        children = [
          ExSolana.Jito,
          {ExSolana.RPC.BlockhashServer, client: client},
          {Tracker, client: client}
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      def child_spec(init_arg) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [init_arg]},
          type: :supervisor
        }
      end
    end
  end

  @doc """
  List of program IDs and their corresponding modules. They must implement
  the `ExSolana.ProgramBehaviour` behaviour.
  """
  @program_lookup %{
    "ComputeBudget111111111111111111111111111111" => ExSolana.Native.ComputeBudget,
    "11111111111111111111111111111111" => ExSolana.Native.SystemProgram,
    "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" => ExSolana.SPL.Token,
    # "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" => ExSolana.Program.SPL.Token,
    # "SwaPpA9LAaLfeLi3a68M4DjnLqgtticKg6CnyNwgAC8" => ExSolana.SPL.TokenSwap,
    # "GovER5Lthms3bLBqWub97yVrMmEogzX7xNjdXpPPCVZw" => ExSolana.SPL.Governance,
    "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4" => ExSolana.Program.JupiterSwap,
    "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" => ExSolana.SPL.AssociatedToken,
    "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" => ExSolana.Program.Raydium.PoolV4,
    "CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK" => ExSolana.Raydium.CAMM,
    "CPMMoo8L3F4NbTegBCKVNunggL7H1ZpdTHKxQB5qKP1C" => ExSolana.Raydium.CPMM
  }

  @typedoc "See `t:ExSolana.Key.t/0`"
  @type key :: ExSolana.Key.t()

  @typedoc "See `t:ExSolana.Key.pair/0`"
  @type keypair :: ExSolana.Key.pair()

  @typedoc "See `t:ExSolana.Signature.t/0"
  @type signature :: ExSolana.Signature.t()

  def program_lookup, do: @program_lookup
  def program_lookup(program_id), do: @program_lookup[program_id]

  @doc """
  See `ExSolana.Key.pair/0`
  """
  defdelegate keypair(), to: ExSolana.Key, as: :pair

  @doc """
  Decodes or extracts a `t:Solana.Key.t/0` from a Base58-encoded string or a
  `t:Solana.Key.pair/0`.

  Returns `{:ok, key}` if the key is valid, or an error tuple if it's not.
  """
  def pubkey(pair_or_encoded)
  def pubkey({_sk, pk}), do: ExSolana.Key.check(pk)
  defdelegate pubkey(encoded), to: ExSolana.Key, as: :decode

  @doc """
  Decodes or extracts a `t:Solana.Key.t/0` from a Base58-encoded string or a
  `t:Solana.Key.pair/0`.

  Throws an `ArgumentError` if it fails to retrieve the public key.
  """
  def pubkey!(pair_or_encoded)

  def pubkey!({_sk, _pk} = pair) do
    case pubkey(pair) do
      {:ok, key} -> key
      _ -> raise ArgumentError, "invalid keypair: #{inspect(pair)}"
    end
  end

  defdelegate pubkey!(encoded), to: ExSolana.Key, as: :decode!

  def sol, do: pubkey!("So11111111111111111111111111111111111111112")

  @doc """
  The public key for the [Rent system
  variable](https://docs.solana.com/developing/runtime-facilities/sysvars#rent).
  """
  def rent, do: pubkey!("SysvarRent111111111111111111111111111111111")

  @doc """
  The public key for the [RecentBlockhashes system
  variable](https://docs.solana.com/developing/runtime-facilities/sysvars#recentblockhashes)
  """
  def recent_blockhashes, do: pubkey!("SysvarRecentB1ockHashes11111111111111111111")

  @doc """
  The public key for the [Clock system
  variable](https://docs.solana.com/developing/runtime-facilities/sysvars#clock)
  """
  def clock, do: pubkey!("SysvarC1ock11111111111111111111111111111111")

  @doc """
  The public key for the [BPF Loader
  program](https://docs.solana.com/developing/runtime-facilities/programs#bpf-loader)
  """
  def bpf_loader, do: pubkey!("BPFLoaderUpgradeab1e11111111111111111111111")

  @doc false
  def lamports_per_sol, do: 1_000_000_000

  @doc """
  Returns a configured RPC client.
  """
  def rpc_client(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, ExSolana.Config.get({:rpc, :base_url}))
    network = Keyword.get(opts, :network, ExSolana.Config.get({:rpc, :network}))
    api_key = Keyword.get(opts, :api_key, ExSolana.Config.get({:rpc, :api_key}))

    client_opts =
      if network do
        [network: network]
      else
        [base_url: base_url, api_key: api_key]
      end

    ExSolana.RPC.client(client_opts)
  end

  @doc """
  Returns a reference to the global tracker process.

  This function retrieves or starts the global ExSolana.RPC.Tracker process.
  It's useful for tracking transaction statuses across multiple operations.

  ## Options

    * `:start` - Whether to start the tracker if it doesn't exist (default: true)
    * `:name` - The name to register the tracker process (default: ExSolana.RPC.Tracker)
    * `:client` - An existing RPC client to use (optional)
    * `:network` - The Solana network to connect to (used if :client is not provided)
    * `:t` - The interval in milliseconds between status checks (default: 500)

  ## Examples

      iex> tracker = ExSolana.tracker()
      iex> is_pid(tracker)
      true

      iex> tracker = ExSolana.tracker(start: false)
      iex> is_pid(tracker)
      true

  """
  @spec tracker(keyword()) :: {:ok, pid()} | {:error, term()}
  def tracker(opts \\ []) do
    name = Keyword.get(opts, :name, Tracker)
    start = Keyword.get(opts, :start, true)

    if start do
      case start_tracker(name, opts) do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          pid

        error ->
          error
      end
    else
      case Process.whereis(name) do
        nil ->
          {:error, :not_started}

        pid ->
          pid
      end
    end
  end

  defp start_tracker(name, opts) do
    case Process.whereis(name) do
      nil ->
        Tracker.start_link(Keyword.put(opts, :name, name))

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  def send(requests, opts \\ []) do
    client = Keyword.get(opts, :client, rpc_client())
    RPC.send(client, requests)
  end

  def send_and_confirm(requests, opts \\ []) do
    client = Keyword.get(opts, :client, rpc_client())
    tracker = Keyword.get(opts, :tracker, tracker())
    RPC.send_and_confirm(client, tracker, requests, opts)
  end

  # @doc """
  # Sends a transaction with options to either send, send and confirm, or send with Jito.

  # ## Options

  #   * `:method` - The method to use for sending the transaction. Can be `:send`, `:send_and_confirm`, or `:send_with_jito`. Defaults to `:send`.
  #   * `:timeout` - The timeout for the operation in milliseconds. Defaults to 5000.
  #   * `:client` - The RPC client to use. If not provided, a default client will be created.
  #   * `:commitment` - The commitment level for the transaction. Defaults to "confirmed".

  # ## Examples

  #     iex> ExSolana.send(transaction, method: :send_and_confirm)
  #     {:ok, "transaction_signature"}

  #     iex> ExSolana.send(transaction, method: :send_with_jito, timeout: 10_000)
  #     {:ok, "jito_bundle_signature"}

  # """
  # @spec send(Transaction.t() | [Transaction.t()], keyword()) ::
  #         {:ok, String.t()} | {:error, term()}
  # def send(txs, opts \\ []) do
  #   method = Keyword.get(opts, :method, :send)
  #   max_retries = Keyword.get(opts, :max_retries, 3)
  #   client = Keyword.get(opts, :client, nil)
  #   tracker = Keyword.get(opts, :tracker, nil)
  #   commitment = Keyword.get(opts, :commitment, "confirmed")
  #   timeout = Keyword.get(opts, :timeout, 5_000)

  #   case method do
  #     :send ->
  #       requests =
  #         Enum.map(
  #           List.wrap(txs),
  #           &RPC.Request.send_transaction(&1, commitment: commitment, max_retries: max_retries)
  #         )

  #       RPC.send(client, requests)

  #     :send_confirm ->
  #       RPC.send_and_confirm(client, tracker, txs,
  #         commitment: commitment,
  #         timeout: timeout
  #       )

  #     # RPC.send_and_confirm(client, transaction, commitment: commitment, timeout: timeout)

  #     # :jito ->
  #     #   ExSolana.Jito.send_bundle(client, [transaction], timeout: timeout)

  #     _ ->
  #       {:error, "Invalid send method"}
  #   end
  # end
end
