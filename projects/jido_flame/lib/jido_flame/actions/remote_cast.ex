defmodule JidoFlame.Actions.RemoteCast do
  @moduledoc """
  Action to execute a fire-and-forget function on a remote FLAME runner.

  ## Examples

      params = %{
        pool: MyApp.FlamePool,
        fun: fn -> send_metrics_async() end
      }
  """

  use Jido.Action,
    name: "jido_flame_remote_cast",
    description: "Execute a fire-and-forget function on a remote FLAME runner",
    category: "flame",
    tags: ["flame", "remote", "async"],
    vsn: "1.0.0",
    schema: [
      pool: [type: :atom, required: true, doc: "FLAME pool name"],
      fun: [type: :any, required: true, doc: "0-arity function to execute"],
      opts: [type: :keyword_list, default: [], doc: "Options for FLAME.cast/3"],
      tag: [type: :any, doc: "Correlation tag (optional)"]
    ]

  alias JidoFlame.Directive.RemoteCast

  @impl true
  def run(params, _context) do
    directive_attrs = %{
      pool: params.pool,
      fun: params.fun,
      opts: params[:opts] || [],
      tag: params[:tag]
    }

    case RemoteCast.new(directive_attrs) do
      {:ok, directive} ->
        {:ok, %{directive_type: :remote_cast, pool: params.pool}, [directive]}

      {:error, error} ->
        {:error, error}
    end
  end
end
