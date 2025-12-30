defmodule Jido.AgentServer.Signal.Orphaned do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.orphaned",
    schema: [
      parent_id: [type: :string, required: true, doc: "ID of the parent agent that died"],
      reason: [type: :any, required: true, doc: "Exit reason from the parent process"]
    ]
end
