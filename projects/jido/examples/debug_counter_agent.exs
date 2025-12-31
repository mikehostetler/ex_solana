#!/usr/bin/env elixir

# Run with: mix run examples/debug_counter_agent.exs
#
# Simple FSM Agent Example for Debugging
#
# Demonstrates:
# - AgentServer.status/1 for polling agent status
# - AgentServer.stream_status/2 for monitoring execution
# - Debug events emitted at state transitions
# - Telemetry handler to observe debug events

# Configure debug events for this session
Application.put_env(:jido, :observability,
  log_level: :debug,
  debug_events: :all,
  redact_sensitive: false
)

defmodule DebugCounterAgent do
  @moduledoc """
  A simple counter agent demonstrating debug events and status polling.

  Signals:
  - "counter.increment" - Increment counter and emit debug event
  - "counter.decrement" - Decrement counter and emit debug event
  - "counter.finish" - Mark as completed
  """

  use Jido.Agent,
    name: "debug_counter",
    schema: [
      counter: [type: :integer, default: 0],
      target: [type: :integer, default: 10],
      completed: [type: :boolean, default: false]
    ]

  alias Jido.Signal

  @impl true
  def handle_signal(agent, %Signal{type: "counter.increment"}) do
    old_counter = agent.state[:counter]
    {:ok, agent} = set(agent, counter: old_counter + 1)
    new_counter = agent.state[:counter]

    # Emit debug event for state change
    Jido.Observe.emit_debug_event(
      [:jido, :agent, :status, :changed],
      %{},
      %{
        agent_id: agent.id,
        old_counter: old_counter,
        new_counter: new_counter,
        action: :increment
      }
    )

    # Check if we hit target
    if new_counter >= agent.state[:target] do
      {:ok, agent} = set(agent, completed: true)

      Jido.Observe.emit_debug_event(
        [:jido, :agent, :iteration, :stop],
        %{},
        %{agent_id: agent.id, final_count: new_counter, status: :success}
      )

      {agent, []}
    else
      {agent, []}
    end
  end

  def handle_signal(agent, %Signal{type: "counter.decrement"}) do
    old_counter = agent.state[:counter]
    {:ok, agent} = set(agent, counter: old_counter - 1)
    new_counter = agent.state[:counter]

    Jido.Observe.emit_debug_event(
      [:jido, :agent, :status, :changed],
      %{},
      %{
        agent_id: agent.id,
        old_counter: old_counter,
        new_counter: new_counter,
        action: :decrement
      }
    )

    {agent, []}
  end

  def handle_signal(agent, %Signal{type: "counter.finish"}) do
    {:ok, agent} = set(agent, completed: true)

    Jido.Observe.emit_debug_event(
      [:jido, :agent, :iteration, :stop],
      %{},
      %{agent_id: agent.id, final_count: agent.state[:counter], status: :completed}
    )

    {agent, []}
  end

  def handle_signal(agent, _signal), do: {agent, []}
end

# Attach telemetry handler to observe debug events
:telemetry.attach_many(
  "debug-counter-handler",
  [
    [:jido, :agent, :status, :changed],
    [:jido, :agent, :iteration, :stop]
  ],
  fn event, measurements, metadata, _config ->
    IO.puts("\n[DEBUG EVENT] #{inspect(event)}")
    IO.puts("  Measurements: #{inspect(measurements)}")
    IO.puts("  Metadata: #{inspect(metadata)}")
  end,
  nil
)

IO.puts("\n=== Debug Counter Agent Demo ===\n")

# Start a Jido instance for the example
{:ok, _} = Jido.start_link(name: DebugCounterExample.Jido)

# Start the agent under the Jido instance
{:ok, pid} = Jido.start_agent(DebugCounterExample.Jido, DebugCounterAgent, initial_state: %{target: 5})

# Get initial status
{:ok, status} = Jido.status(DebugCounterExample.Jido, pid)
IO.puts("Initial status: #{inspect(Jido.AgentServer.Status.status(status))}")
IO.puts("Initial counter: #{inspect(status.raw_state[:counter])}")

# Send increment signals
IO.puts("\n--- Sending 3 increment signals ---")

for i <- 1..3 do
  signal = Jido.Signal.new!("counter.increment", %{}, source: "user")
  Jido.cast(DebugCounterExample.Jido, pid, signal)
  Process.sleep(50)

  {:ok, status} = Jido.status(DebugCounterExample.Jido, pid)
  IO.puts("After increment #{i}: counter = #{status.raw_state[:counter]}")
end

# Send decrement signal
IO.puts("\n--- Sending 1 decrement signal ---")
signal = Jido.Signal.new!("counter.decrement", %{}, source: "user")
Jido.cast(DebugCounterExample.Jido, pid, signal)
Process.sleep(50)

{:ok, status} = Jido.status(DebugCounterExample.Jido, pid)
IO.puts("After decrement: counter = #{status.raw_state[:counter]}")

# Send more increments to reach target
IO.puts("\n--- Sending increments to reach target (5) ---")

Enum.reduce_while(1..3, nil, fn i, _acc ->
  signal = Jido.Signal.new!("counter.increment", %{}, source: "user")
  Jido.cast(DebugCounterExample.Jido, pid, signal)
  Process.sleep(50)

  {:ok, status} = Jido.status(DebugCounterExample.Jido, pid)

  IO.puts(
    "Increment #{i}: counter = #{status.raw_state[:counter]}, completed? = #{status.raw_state[:completed]}"
  )

  if status.raw_state[:completed] do
    IO.puts("\n✓ Agent completed!")
    {:halt, nil}
  else
    {:cont, nil}
  end
end)

# Demonstrate stream_status for monitoring
IO.puts("\n--- Stream Status Demo (monitoring final state) ---")

Jido.stream_status(DebugCounterExample.Jido, pid, interval_ms: 100)
|> Enum.take(3)
|> Enum.each(fn status ->
  IO.puts(
    "Stream: counter=#{status.raw_state[:counter]}, status=#{Jido.AgentServer.Status.status(status)}"
  )
end)

# Cleanup
:telemetry.detach("debug-counter-handler")

IO.puts("\n=== Demo Complete ===\n")
