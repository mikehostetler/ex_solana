defmodule Jido.Examples.ReactAgent do
  @moduledoc """
  A ReAct-style agent demonstrating the LLM tool-use pattern.

  ReAct (Reasoning + Acting) is a pattern where an LLM:
  1. **Thinks** about what to do given the current context
  2. **Acts** by selecting and invoking a tool
  3. **Observes** the result and repeats until done

  ## The Core Principle

  > **Agents think. Servers act.**

  This means `handle_signal/2` is **pure** - it never calls an LLM directly.
  Instead, LLM calls are modeled as `Effect.Run` just like any other I/O:

  ```
  react.query
    → Effect.Run(LLMThink)           # Request LLM reasoning
    → react.llm_result               # LLM decided to use a tool
    → Effect.Run(Tool)               # Execute the tool
    → react.tool_result              # Tool returned data
    → Effect.Run(LLMThink)           # Request more LLM reasoning
    → react.llm_result               # LLM has final answer
    → Effect.Reply(answer)           # Done
  ```

  ## Running

      mix run -e "Jido.Examples.ReactAgent.demo()"

  ## Key Design Points

  - LLM calls are `Effect.Run{action: LLMThink}` - never inline
  - Tool calls are `Effect.Run{action: ToolModule}` - same pattern
  - All I/O happens via Effects executed by AgentServer
  - `handle_signal/2` only updates state and emits Effects
  """
  use Jido.Agent,
    name: "react",
    schema: %{
      query: Zoi.string() |> Zoi.optional(),
      thoughts: Zoi.array(Zoi.map()) |> Zoi.default([]),
      tool_results: Zoi.array(Zoi.map()) |> Zoi.default([]),
      status: Zoi.atom() |> Zoi.default(:idle),
      iteration: Zoi.integer() |> Zoi.default(0),
      max_iterations: Zoi.integer() |> Zoi.default(5)
    }

  alias Jido.Agent.Effect
  alias Jido.Agent.Runner.Simple
  alias Jido.Signal

  # ---------------------------------------------------------------------------
  # Signal Handlers - Pure, no I/O
  # ---------------------------------------------------------------------------

  @impl true
  def handle_signal(state, %Signal{type: "react.query", data: %{"query" => query}}) do
    new_state = %{
      state
      | query: query,
        status: :thinking,
        iteration: 0,
        thoughts: [],
        tool_results: []
    }

    # Request LLM reasoning via Effect - NOT a direct call
    effects = [
      %Effect.Run{
        action: Jido.Examples.Actions.LLMThink,
        params: %{
          agent_id: state.id,
          query: query,
          tool_results: []
        }
      }
    ]

    {:ok, new_state, effects}
  end

  def handle_signal(state, %Signal{type: "react.llm_result", data: data}) do
    thought = data["thought"]
    action = deserialize_action(data["action"])

    thought_record = %{
      iteration: state.iteration + 1,
      thought: thought,
      action: action,
      at: DateTime.utc_now()
    }

    new_state = %{
      state
      | thoughts: [thought_record | state.thoughts],
        iteration: state.iteration + 1
    }

    {final_state, effects} =
      case action do
        {:tool, tool_name, params} ->
          effects = [
            %Effect.Run{
              action: tool_module(tool_name),
              params: Map.put(params, :agent_id, state.id)
            }
          ]

          {%{new_state | status: :acting}, effects}

        {:answer, answer} ->
          effects = [
            %Effect.Reply{
              signal:
                Signal.new!(
                  "react.answer",
                  %{
                    query: state.query,
                    answer: answer,
                    iterations: new_state.iteration,
                    tools_used: Enum.map(state.tool_results, & &1.tool)
                  },
                  source: "/react"
                )
            }
          ]

          {%{new_state | status: :complete}, effects}
      end

    {:ok, final_state, effects}
  end

  def handle_signal(state, %Signal{type: "react.tool_result", data: data}) do
    tool_name = data["tool"]
    result = data["result"]

    tool_record = %{
      tool: tool_name,
      result: result,
      iteration: state.iteration,
      at: DateTime.utc_now()
    }

    new_state = %{state | tool_results: [tool_record | state.tool_results]}

    # Check iteration limit
    if state.iteration >= state.max_iterations do
      final_state = %{new_state | status: :max_iterations_reached}

      effects = [
        %Effect.Reply{
          signal:
            Signal.new!(
              "react.error",
              %{reason: "max_iterations_reached", iterations: state.iteration},
              source: "/react"
            )
        }
      ]

      {:ok, final_state, effects}
    else
      # Request more LLM reasoning via Effect - NOT a direct call
      effects = [
        %Effect.Run{
          action: Jido.Examples.Actions.LLMThink,
          params: %{
            agent_id: state.id,
            query: state.query,
            tool_results: new_state.tool_results
          }
        }
      ]

      {:ok, %{new_state | status: :thinking}, effects}
    end
  end

  def handle_signal(state, %Signal{type: "react.cancel"}) do
    new_state = %{state | status: :cancelled}

    effects = [
      %Effect.Reply{
        signal:
          Signal.new!(
            "react.cancelled",
            %{query: state.query, iterations: state.iteration},
            source: "/react"
          )
      }
    ]

    {:ok, new_state, effects}
  end

  def handle_signal(state, _signal), do: {:ok, state, []}

  # ---------------------------------------------------------------------------
  # Action/Signal Serialization
  # ---------------------------------------------------------------------------

  @doc "Serialize an action tuple for transport in signals."
  def serialize_action({:tool, name, params}) do
    %{"type" => "tool", "name" => name, "params" => params}
  end

  def serialize_action({:answer, answer}) do
    %{"type" => "answer", "answer" => answer}
  end

  @doc "Deserialize an action from signal data."
  def deserialize_action(%{"type" => "tool", "name" => name, "params" => params}) do
    {:tool, name, params}
  end

  def deserialize_action(%{"type" => "answer", "answer" => answer}) do
    {:answer, answer}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tool_module("search"), do: Jido.Examples.Actions.Search
  defp tool_module("calculator"), do: Jido.Examples.Actions.Calculator
  defp tool_module("weather"), do: Jido.Examples.Actions.Weather
  defp tool_module(name), do: raise("Unknown tool: #{name}")

  # ---------------------------------------------------------------------------
  # Demo
  # ---------------------------------------------------------------------------

  @doc """
  Demo the ReAct agent pattern with proper Effect-based LLM calls.

  Run with: mix run -e "Jido.Examples.ReactAgent.demo()"
  """
  def demo do
    IO.puts("=== Jido v2 ReAct Agent Demo ===")
    IO.puts("Demonstrating pure handle_signal with LLM as Effect.Run\n")

    # Create agent
    {:ok, agent} = new(%{id: "react-demo"})
    IO.puts("Created agent: #{agent.id}")
    IO.puts("Status: #{agent.status}\n")

    # Step 1: Send query - agent requests LLM thinking via Effect
    query = "What's the weather in Tokyo?"
    IO.puts("═══ Step 1: User Query ═══")
    IO.puts("Query: #{query}\n")

    query_signal = Signal.new!("react.query", %{"query" => query}, source: "/user")
    {:ok, agent, effects} = Simple.handle(__MODULE__, agent, query_signal)

    IO.puts("Agent status: #{agent.status}")
    print_effects(effects)

    # Step 2: Simulate AgentServer executing LLMThink action and returning result
    IO.puts("\n═══ Step 2: LLM Result (simulated Action execution) ═══")
    IO.puts("AgentServer executed LLMThink action...")

    llm_result =
      Signal.new!(
        "react.llm_result",
        %{
          "thought" => "I need to check the weather. Let me use the weather tool.",
          "action" => serialize_action({:tool, "weather", %{location: "Tokyo"}})
        },
        source: "/llm"
      )

    {:ok, agent, effects} = Simple.handle(__MODULE__, agent, llm_result)

    IO.puts("Agent status: #{agent.status}")
    IO.puts("Iteration: #{agent.iteration}")
    print_thought(hd(agent.thoughts))
    print_effects(effects)

    # Step 3: Simulate tool result
    IO.puts("\n═══ Step 3: Tool Result ═══")
    IO.puts("AgentServer executed Weather action...")

    tool_result =
      Signal.new!(
        "react.tool_result",
        %{"tool" => "weather", "result" => %{temp: 22, condition: "Sunny", humidity: 45}},
        source: "/tools"
      )

    {:ok, agent, effects} = Simple.handle(__MODULE__, agent, tool_result)

    IO.puts("Agent status: #{agent.status}")
    IO.puts("Tool results: #{length(agent.tool_results)}")
    print_effects(effects)

    # Step 4: Final LLM result with answer
    IO.puts("\n═══ Step 4: Final LLM Result ═══")
    IO.puts("AgentServer executed LLMThink action again...")

    final_llm_result =
      Signal.new!(
        "react.llm_result",
        %{
          "thought" =>
            "I have the weather data. Tokyo is 22°C and Sunny with 45% humidity.",
          "action" =>
            serialize_action(
              {:answer,
               "The weather in Tokyo is currently 22°C (72°F), sunny with 45% humidity. Great weather for outdoor activities!"}
            )
        },
        source: "/llm"
      )

    {:ok, agent, effects} = Simple.handle(__MODULE__, agent, final_llm_result)

    IO.puts("Agent status: #{agent.status}")
    IO.puts("Iteration: #{agent.iteration}")
    print_thought(hd(agent.thoughts))
    print_effects(effects)

    IO.puts("\n═══ Final State ═══")
    IO.puts("Status: #{agent.status}")
    IO.puts("Total iterations: #{agent.iteration}")
    IO.puts("Tools used: #{Enum.map(agent.tool_results, & &1.tool) |> Enum.join(", ")}")
    IO.puts("\nDemo complete!")
    IO.puts("\nKey insight: handle_signal/2 never called an LLM directly.")
    IO.puts("All LLM calls were Effect.Run requests executed by AgentServer.")
  end

  defp print_thought(thought) do
    IO.puts("Thought: #{thought.thought}")

    case thought.action do
      {:tool, name, params} ->
        IO.puts("Action: Use tool '#{name}' with #{inspect(params)}")

      {:answer, answer} ->
        IO.puts("Action: Final answer")
        IO.puts("Answer: #{String.slice(answer, 0, 80)}...")
    end
  end

  defp print_effects(effects) do
    IO.puts("Effects emitted (#{length(effects)}):")

    Enum.each(effects, fn effect ->
      case effect do
        %Effect.Run{action: action, params: params} ->
          IO.puts("  → Effect.Run: #{inspect(action)}")
          IO.puts("    params: #{inspect(Map.drop(params, [:tool_results]))}")

        %Effect.Reply{signal: signal} ->
          IO.puts("  → Effect.Reply: #{signal.type}")

        other ->
          IO.puts("  → #{inspect(other)}")
      end
    end)
  end
end

# ---------------------------------------------------------------------------
# Stub Action Modules
# ---------------------------------------------------------------------------
# In production, these would be real Action modules that perform I/O.
# The LLMThink action would call OpenAI/Anthropic/etc.

defmodule Jido.Examples.Actions.LLMThink do
  @moduledoc """
  Stub LLM thinking action.

  In production, this would:
  1. Call an LLM API (OpenAI, Anthropic, etc.)
  2. Send prompt with query, available tools, and tool results
  3. Parse the LLM response into thought + action
  4. Deliver a `react.llm_result` signal back to the agent

  For the demo, we use deterministic stub responses.
  """

  @doc """
  Stub implementation that returns a predetermined response.

  In production: `run(params) -> {:ok, result} | {:error, reason}`
  """
  def stub_run(%{query: query, tool_results: tool_results}) do
    {thought, action} = decide(query, tool_results)

    %{
      thought: thought,
      action: Jido.Examples.ReactAgent.serialize_action(action)
    }
  end

  defp decide(query, tool_results) do
    cond do
      tool_results == [] ->
        cond do
          String.contains?(query, "weather") ->
            location = extract_location(query)

            {"I need to check the weather. Let me use the weather tool.",
             {:tool, "weather", %{location: location}}}

          String.contains?(query, "calculate") or String.contains?(query, "math") ->
            {"This is a math question. I'll use the calculator.",
             {:tool, "calculator", %{expression: "42 * 2"}}}

          true ->
            {"I need more information. Let me search for this.",
             {:tool, "search", %{query: query}}}
        end

      length(tool_results) >= 1 ->
        last_result = hd(tool_results)

        {"I have the information I need from #{last_result.tool}.",
         {:answer, "Based on #{last_result.tool}: #{inspect(last_result.result)}"}}
    end
  end

  defp extract_location(query) do
    cond do
      String.contains?(query, "Tokyo") -> "Tokyo"
      String.contains?(query, "London") -> "London"
      String.contains?(query, "New York") -> "New York"
      true -> "San Francisco"
    end
  end
end

defmodule Jido.Examples.Actions.Search do
  @moduledoc "Stub search action - would call a search API in production."
end

defmodule Jido.Examples.Actions.Calculator do
  @moduledoc "Stub calculator action - would evaluate expressions in production."
end

defmodule Jido.Examples.Actions.Weather do
  @moduledoc "Stub weather action - would call a weather API in production."
end
