defmodule ExSolana.RPC.Request.GetRecentPerformanceSamples do
  @moduledoc """
  Functions for creating a getRecentPerformanceSamples request.
  """

  import ExSolana.RPC.Request.Helpers

  alias ExSolana.RPC.Request

  @get_recent_performance_samples_options [
    limit: [
      type: :non_neg_integer,
      doc: "Limit the number of samples to return (maximum 720)",
      default: 720
    ]
  ]

  @doc """
  Returns a list of recent performance samples, in reverse slot order.

  ## Options

  #{NimbleOptions.docs(@get_recent_performance_samples_options)}

  For more information, see [the Solana docs](https://docs.solana.com/developing/clients/jsonrpc-api#getrecentperformancesamples).
  """
  @spec get_recent_performance_samples(keyword()) :: Request.t() | {:error, String.t()}
  def get_recent_performance_samples(opts \\ []) do
    with {:ok, validated_opts} <- validate(opts, @get_recent_performance_samples_options) do
      {"getRecentPerformanceSamples", [validated_opts[:limit]]}
    end
  end
end
