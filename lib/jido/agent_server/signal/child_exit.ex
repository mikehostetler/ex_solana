defmodule Jido.AgentServer.Signal.ChildExit do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.child.exit",
    schema: [
      tag: [type: :any, required: true, doc: "Tag assigned to the child when spawned"],
      pid: [type: :any, required: true, doc: "PID of the child process that exited"],
      reason: [type: :any, required: true, doc: "Exit reason from the child process"]
    ]
end
