defmodule JidoFlame.AgentStarter do
  @moduledoc """
  Helper module for starting agents from structs on remote FLAME nodes.
  """

  def child_spec({agent_struct, opts}) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [{agent_struct, opts}]},
      type: :worker,
      restart: :temporary
    }
  end

  def start_link({agent_struct, opts}) do
    module = agent_struct.__struct__
    module.start_link(agent_struct, opts)
  end
end
