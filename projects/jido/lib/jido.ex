defmodule Jido do
  @moduledoc """
  自動 (Jido) - A foundational framework for building autonomous, distributed agent systems in Elixir.

  ## Core Concepts

  Jido is built around a purely functional Agent design:

  - **Agent** - An immutable data structure that holds state and can be updated via commands
  - **Actions** - Pure functions that transform agent state
  - **Directives** - Descriptions of external effects (emit signals, spawn processes, etc.)
  - **Strategies** - Pluggable execution patterns for actions

  ## Agent API

  The core operation is `cmd/2`:

      {agent, directives} = MyAgent.cmd(agent, MyAction)
      {agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})
      {agent, directives} = MyAgent.cmd(agent, [Action1, Action2])

  Key invariants:
  - The returned `agent` is always complete — no "apply directives" step needed
  - `directives` are external effects only — they never modify agent state
  - `cmd/2` is a pure function — given same inputs, always same outputs

  ## Defining Agents

      defmodule MyAgent do
        use Jido.Agent,
          name: "my_agent",
          description: "My custom agent",
          schema: [
            status: [type: :atom, default: :idle],
            counter: [type: :integer, default: 0]
          ]
      end

  ## Working with Agents

      # Create a new agent
      agent = MyAgent.new()
      agent = MyAgent.new(id: "custom-id", state: %{counter: 10})

      # Execute actions
      {agent, directives} = MyAgent.cmd(agent, MyAction)

      # Update state directly
      {:ok, agent} = MyAgent.set(agent, %{status: :running})

  ## Utility Functions

  - `Jido.Util.generate_id/0` - Generate unique identifiers
  - `Jido.Error` - Structured error handling
  """

  @type agent_id :: String.t() | atom()

  @doc """
  Generate a unique identifier.

  Delegates to `Jido.Util.generate_id/0`.
  """
  defdelegate generate_id(), to: Jido.Util
end
