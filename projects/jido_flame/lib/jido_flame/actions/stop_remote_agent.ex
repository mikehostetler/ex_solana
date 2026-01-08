defmodule JidoFlame.Actions.StopRemoteAgent do
  @moduledoc """
  Action to stop a remote child agent.

  ## Examples

      params = %{
        tag: :worker_1,
        reason: :normal
      }
  """

  use Jido.Action,
    name: "jido_flame_stop_remote_agent",
    description: "Stop a remote child agent",
    category: "flame",
    tags: ["flame", "remote", "agent", "stop"],
    vsn: "1.0.0",
    schema: [
      tag: [type: :any, required: true, doc: "Child tag in parent's children map"],
      reason: [type: :any, default: :normal, doc: "Shutdown reason"]
    ]

  alias JidoFlame.Directive.StopRemoteAgent

  @impl true
  def run(params, _context) do
    directive_attrs = %{
      tag: params.tag,
      reason: params[:reason] || :normal
    }

    case StopRemoteAgent.new(directive_attrs) do
      {:ok, directive} ->
        {:ok, %{directive_type: :stop_remote_agent, tag: params.tag}, [directive]}

      {:error, error} ->
        {:error, error}
    end
  end
end
