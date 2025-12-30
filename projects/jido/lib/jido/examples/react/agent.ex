defmodule Jido.Examples.ReAct.Agent do
  @moduledoc """
  ReAct demo agent using Jido + ReqLLM streaming.

  Demonstrates:
  - Generic ReAct strategy from `Jido.AI.Strategy.ReAct`
  - Streaming LLM integration via directives
  - Jido.Action-based tool execution
  - Signal-based completion notification

  ## Usage

      # Start the agent server
      {:ok, pid} = Jido.AgentServer.start(agent: Jido.Examples.ReAct.Agent)

      # Send a query
      Jido.Examples.ReAct.Agent.ask(pid, "What is 15 * 7?")

      # Check status
      agent = Jido.AgentServer.get(pid)
      agent.state.completed  # => true when done
      agent.state.last_answer  # => final answer
  """

  use Jido.Agent,
    name: "react_agent",
    description: "LLM ReAct demo agent using Jido + ReqLLM streaming",
    strategy: {
      Jido.AI.Strategy.ReAct,
      tools: [
        Jido.Tools.Arithmetic.Add,
        Jido.Tools.Arithmetic.Subtract,
        Jido.Tools.Arithmetic.Multiply,
        Jido.Tools.Arithmetic.Divide,
        Jido.Tools.Weather
      ],
      max_iterations: 10
    },
    schema:
      Zoi.object(%{
        __strategy__: Zoi.map() |> Zoi.default(%{}),
        model: Zoi.string() |> Zoi.default("anthropic:claude-haiku-4-5"),
        last_query: Zoi.string() |> Zoi.default(""),
        last_answer: Zoi.string() |> Zoi.default(""),
        completed: Zoi.boolean() |> Zoi.default(false)
      })

  @doc """
  Convenience function to ask a question.
  Returns :ok, the result arrives asynchronously via the ReAct loop.
  """
  def ask(pid, query) when is_binary(query) do
    signal = Jido.Signal.new!("react.user_query", %{query: query}, source: "/react/agent")
    Jido.AgentServer.cast(pid, signal)
  end

  @impl true
  def handle_signal(agent, %Jido.Signal{type: "react.user_query", data: data} = signal) do
    query = data[:query] || data["query"]
    agent = %{agent | state: Map.put(agent.state, :last_query, query)}
    super(agent, signal)
  end

  def handle_signal(agent, signal) do
    super(agent, signal)
  end

  @impl true
  def on_after_cmd(agent, _action, directives) do
    snap = strategy_snapshot(agent)

    agent =
      if snap.done? do
        %{
          agent
          | state:
              Map.merge(agent.state, %{
                last_answer: snap.result || "",
                completed: true
              })
        }
      else
        agent
      end

    {:ok, agent, directives}
  end
end
