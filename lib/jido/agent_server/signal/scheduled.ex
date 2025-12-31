defmodule Jido.AgentServer.Signal.Scheduled do
  @moduledoc false

  use Jido.Signal,
    type: "jido.scheduled",
    schema: [
      message: [type: :any, required: true, doc: "The scheduled message payload"]
    ]
end
