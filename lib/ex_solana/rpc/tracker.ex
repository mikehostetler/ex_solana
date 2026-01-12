defmodule ExSolana.RPC.Tracker do
  @moduledoc """
  A GenServer you can use to track the status of transaction signatures.

  ## Example

      iex> key = ExSolana.keypair() |> ExSolana.pubkey!()
      iex> {:ok, tracker} = ExSolana.RPC.Tracker.start_link(network: "localhost")
      iex> client = ExSolana.RPC.client(network: "localhost")
      iex> {:ok, tx} = ExSolana.RPC.send(client, ExSolana.RPC.Request.request_airdrop(key, 1))
      iex> ExSolana.Tracker.start_tracking(tracker, tx)
      iex> receive do
      ...>   {:ok, [^tx]} -> IO.puts("confirmed!")
      ...> end
      confirmed!

  """
  use GenServer
  use ExSolana.Util.DebugTools, debug_enabled: false

  alias ExSolana.RPC

  @doc """
  Returns a child specification for starting the RPC Tracker under a supervisor.

  ## Options

    * `:name` - The name to register the tracker process (default: ExSolana.RPC.Tracker)
    * `:client` - An existing RPC client to use (optional)
    * `:network` - The Solana network to connect to (used if :client is not provided)
    * `:retry_options` - Options for retrying RPC requests (used if :client is not provided)
    * `:adapter` - The Tesla adapter to use for RPC requests (used if :client is not provided)
    * `:t` - The interval in milliseconds between status checks (default: 500)

  ## Example

      children = [
        {ExSolana.RPC.Tracker, name: MyApp.GlobalTracker, network: "mainnet-beta"}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  """
  def child_spec(opts) do
    debug("Creating child spec with options: #{inspect(opts)}")

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts a `ExSolana.RPC.Tracker` process linked to the current process.

  ## Options

    * `:name` - The name to register the tracker process (optional)
    * `:client` - An existing RPC client to use (optional)
    * `:network` - The Solana network to connect to (used if :client is not provided)
    * `:retry_options` - Options for retrying RPC requests (used if :client is not provided)
    * `:adapter` - The Tesla adapter to use for RPC requests (used if :client is not provided)
    * `:t` - The interval in milliseconds between status checks (default: 500)

  """
  def start_link(opts) do
    debug("Starting RPC Tracker with options: #{inspect(opts)}")
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Starts tracking a transaction signature or list of transaction signatures.

  Sends messages back to the calling process as transactions from the list
  are confirmed. Stops tracking automatically once transactions have been
  confirmed.
  """
  def start_tracking(tracker \\ __MODULE__, signatures, opts) do
    debug("Starting to track signatures: #{inspect(signatures)} with options: #{inspect(opts)}")
    GenServer.cast(tracker, {:track, List.wrap(signatures), opts, self()})
  end

  @doc """
  Stops tracking a transaction signature or list of transaction signatures.
  """
  def stop_tracking(tracker \\ __MODULE__, signatures) do
    debug("Stopping tracking for signatures: #{inspect(signatures)}")
    GenServer.cast(tracker, {:stop_track, List.wrap(signatures)})
  end

  @doc false
  def init(opts) do
    debug("Initializing RPC Tracker with options: #{inspect(opts)}")

    client =
      Keyword.get(opts, :client) ||
        ExSolana.RPC.client(Keyword.take(opts, [:network, :retry_options, :adapter]))

    {:ok, %{client: client, t: Keyword.get(opts, :t, 500), tracking: %{}}}
  end

  @doc false
  def handle_cast({:track, signatures, opts, from}, state) do
    debug("Handling cast to track signatures: #{inspect(signatures)}")
    Process.send_after(self(), {:check, signatures, opts, from}, 0)

    new_tracking =
      Enum.reduce(signatures, state.tracking, fn sig, acc -> Map.put(acc, sig, from) end)

    {:noreply, %{state | tracking: new_tracking}}
  end

  @doc false
  def handle_cast({:stop_track, signatures}, state) do
    debug("Handling cast to stop tracking signatures: #{inspect(signatures)}")
    new_tracking = Map.drop(state.tracking, signatures)
    {:noreply, %{state | tracking: new_tracking}}
  end

  @doc false
  def handle_info({:check, signatures, opts, from}, state) do
    debug("Checking status for signatures: #{inspect(signatures)}")
    signatures_to_check = Enum.filter(signatures, &Map.has_key?(state.tracking, &1))

    if signatures_to_check == [] do
      debug("No signatures to check")
      {:noreply, state}
    else
      request = RPC.Request.get_signature_statuses(signatures)
      commitment = Keyword.get(opts, :commitment, "confirmed")

      debug("Sending RPC request for signature statuses")
      {:ok, results} = RPC.send(state.client, request)

      mapped_results = signatures |> Enum.zip(results) |> Map.new()

      {_failed, not_failed} =
        Enum.split_with(signatures, fn signature ->
          result = Map.get(mapped_results, signature)
          !is_nil(result) && !is_nil(result["err"])
        end)

      {done, to_retry} =
        Enum.split_with(not_failed, fn signature ->
          result = Map.get(mapped_results, signature)
          !is_nil(result) && commitment_done?(result, commitment)
        end)

      if done != [] do
        debug("Sending confirmation for done signatures: #{inspect(done)}")
        send(from, {:ok, done})
      end

      if to_retry != [] do
        debug("Scheduling retry for signatures: #{inspect(to_retry)}")
        Process.send_after(self(), {:check, to_retry, opts, from}, state.t)
      end

      new_tracking = Map.drop(state.tracking, done)
      {:noreply, %{state | tracking: new_tracking}}
    end
  end

  defp commitment_done?(%{"confirmationStatus" => status}, commitment) do
    debug("Checking commitment done for status: #{status}, commitment: #{commitment}")

    result =
      case {status, commitment} do
        {"finalized", _} -> true
        {"confirmed", "finalized"} -> false
        {"confirmed", _} -> true
        {"processed", "processed"} -> true
        {"processed", _} -> false
      end

    debug("Commitment done result: #{inspect(result)}")
    result
  end
end
