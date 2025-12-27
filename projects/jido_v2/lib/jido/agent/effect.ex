defmodule Jido.Agent.Effect do
  @moduledoc """
  Sum type for agent effects – pure descriptions of what should happen.

  Effects are data only. AgentServer will later interpret them and perform I/O.

  ## Effect Types

  - `Effect.Run` - Execute an Action module with params
  - `Effect.Reply` - Send a response signal to a caller
  - `Effect.Timer` - Schedule a future signal

  ## Usage

      effects = [
        %Effect.Run{action: MyAction, params: %{key: "value"}},
        %Effect.Timer{in: 5000, signal: reminder_signal}
      ]

      {:ok, new_state, effects}
  """

  alias __MODULE__.{Run, Reply, Timer}

  @type t :: Run.t() | Reply.t() | Timer.t()
end
