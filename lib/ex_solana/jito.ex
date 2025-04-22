defmodule ExSolana.Jito do
  @moduledoc """
  Supervisor for the Jito system, managing clients for multiple regions and handling transaction distribution.
  """

  use Supervisor

  alias ExSolana.Jito.Bundle
  alias ExSolana.Jito.SearcherClient

  require Logger

  @jito_regions %{
    ny: %{
      block_engine_url: "https://ny.mainnet.block-engine.jito.wtf",
      priority: 1,
      shred_receiver_addr: "141.98.216.96:1002",
      relayer_url: "http://ny.mainnet.relayer.jito.wtf:8100",
      ntp: "ntp.dallas.jito.wtf"
    },
    slc: %{block_engine_url: "https://slc.mainnet.block-engine.jito.wtf", priority: 2},
    ams: %{block_engine_url: "https://amsterdam.mainnet.block-engine.jito.wtf", priority: 3},
    fra: %{block_engine_url: "https://frankfurt.mainnet.block-engine.jito.wtf", priority: 4},
    tok: %{block_engine_url: "https://tokyo.mainnet.block-engine.jito.wtf", priority: 5}
  }

  @rate_limit_interval 1_000
  @rate_limit_requests 5
  @max_retries 3
  @retry_delay 1_000

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        ExRated,
        {ExSolana.Jito.TipServer, reconnect_interval: 10_000}
      ] ++
        Enum.map(@jito_regions, fn {region, config} ->
          Supervisor.child_spec(
            {ExSolana.Jito.SearcherClient, [name: client_name(region), url: config.block_engine_url]},
            id: :"searcher_client_#{region}"
          )
        end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  @spec new(String.t(), keyword()) :: {:ok, GRPC.Channel.t()} | {:error, any()}
  def new(url, opts \\ []) do
    ExSolana.GRPCClientBase.new(url, opts, "Jito service")
  end

  @doc """
  Submits a bundle to the Jito network.

  ## Parameters
    - bundle: An ExSolana.Jito.Bundle struct
    - opts: Optional keyword list of options
      - :max_retries - Maximum number of retry attempts (default: #{@max_retries})
      - :retry_delay - Delay in milliseconds between retries (default: #{@retry_delay})

  ## Returns
    - {:ok, result} on success
    - {:error, reason} on failure

  ## Examples
      iex> ExSolana.Jito.submit_bundle(bundle)
      {:ok, result}

      iex> ExSolana.Jito.submit_bundle(bundle, max_retries: 5, retry_delay: 2000)
      {:ok, result}
  """
  @spec submit_bundle(Bundle.t(), keyword()) :: {:ok, any()} | {:error, atom()}
  def submit_bundle(bundle, opts \\ [])

  def submit_bundle(%Bundle{} = bundle, opts) do
    max_retries = Keyword.get(opts, :max_retries, @max_retries)
    retry_delay = Keyword.get(opts, :retry_delay, @retry_delay)

    do_submit_bundle(bundle, max_retries, retry_delay)
  end

  def submit_bundle(_bundle, _opts), do: {:error, :invalid_bundle}

  defp do_submit_bundle(_bundle, 0, _retry_delay) do
    {:error, :max_retries_reached}
  end

  defp do_submit_bundle(bundle, retries_left, retry_delay) do
    case send_bundle_to_regions(bundle) do
      {:ok, result} ->
        {:ok, result}

      {:error, :rate_limited} ->
        Process.sleep(retry_delay)
        do_submit_bundle(bundle, retries_left - 1, retry_delay)

      {:error, reason} ->
        Logger.warning("Failed to submit bundle: #{inspect(reason)}")
        Process.sleep(retry_delay)
        do_submit_bundle(bundle, retries_left - 1, retry_delay)
    end
  end

  defp send_bundle_to_regions(bundle) do
    sorted_regions = Enum.sort_by(@jito_regions, fn {_, config} -> config.priority end)

    Enum.reduce_while(sorted_regions, {:error, :all_regions_unavailable}, fn {region, _config}, acc ->
      case check_rate_limit(region) do
        :ok ->
          case SearcherClient.send_bundle(client_name(region), bundle) do
            {:ok, result} ->
              Logger.info("Bundle sent successfully to #{region}: #{inspect(result)}")
              {:halt, {:ok, result}}

            error ->
              Logger.warning("Failed to send bundle to #{region}: #{inspect(error)}")
              {:cont, error}
          end

        :error ->
          Logger.info("Rate limit reached for #{region}, trying next region")
          {:cont, acc}
      end
    end)
  end

  defp check_rate_limit(region) do
    case ExRated.check_rate(to_string(region), @rate_limit_interval, @rate_limit_requests) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  def await_bundle_result(bundle_id, timeout \\ 30_000) do
    receive do
      {:bundle_result, ^bundle_id, result} -> {:ok, result}
    after
      timeout -> {:error, :timeout}
    end
  end

  def subscribe_bundle_results do
    Enum.map(@jito_regions, fn {region, _} ->
      SearcherClient.subscribe_bundle_results(client_name(region))
    end)
  end

  defp client_name(region), do: :"jito_client_#{region}"
end
