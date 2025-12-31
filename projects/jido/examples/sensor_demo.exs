#!/usr/bin/env elixir
# Run with: mix run examples/sensor_demo.exs
#
# This example demonstrates Jido Sensors:
# - A custom sensor that emits periodic "random quote" signals
# - A stubbed "webhook" pattern showing direct signal injection
# - An agent that receives and processes sensor signals via Actions
#
# This is a preview of the Jido 2.0 Sensor architecture.

Logger.configure(level: :info)

# =============================================================================
# ACTIONS: Define actions that handle sensor signals
#
# In Jido 2.0, signals are routed to Actions via signal_routes/0.
# Actions process the signal data and can update agent state + emit directives.
# =============================================================================

defmodule HandleQuoteAction do
  @moduledoc "Action that handles quote signals from sensors"
  use Jido.Action,
    name: "handle_quote",
    schema: [
      quote: [type: :string, required: true],
      category: [type: :string, default: "general"],
      emit_count: [type: :integer, default: 0],
      sensor_id: [type: :string, default: "unknown"]
    ]

  def run(params, context) do
    IO.puts("\n  [Agent] Received quote from sensor #{params.sensor_id}:")
    IO.puts("    \"#{params.quote}\"")
    IO.puts("    (Category: #{params.category}, Count: #{params.emit_count})")

    current_quotes = Map.get(context.state, :quotes, [])
    quotes = [
      %{
        quote: params.quote,
        category: params.category,
        received_at: DateTime.utc_now()
      }
      | current_quotes
    ]

    {:ok, %{quotes: quotes}}
  end
end

defmodule HandleGitHubWebhookAction do
  @moduledoc "Action that handles GitHub webhook signals"
  use Jido.Action,
    name: "handle_github_webhook",
    schema: [
      event: [type: :string, required: true],
      payload: [type: :map, default: %{}],
      received_at: [type: :any, required: false]
    ]

  def run(params, context) do
    IO.puts("\n  [Agent] Received GitHub webhook:")
    IO.puts("    Event: #{params.event}")
    IO.puts("    Payload: #{inspect(params.payload)}")

    current_events = Map.get(context.state, :events, [])
    events = [
      %{
        source: :github,
        event: params.event,
        payload: params.payload,
        received_at: params[:received_at] || DateTime.utc_now()
      }
      | current_events
    ]

    {:ok, %{events: events}}
  end
end

defmodule HandleStripeWebhookAction do
  @moduledoc "Action that handles Stripe webhook signals"
  use Jido.Action,
    name: "handle_stripe_webhook",
    schema: [
      event: [type: :string, required: true],
      payload: [type: :map, default: %{}],
      received_at: [type: :any, required: false]
    ]

  def run(params, context) do
    IO.puts("\n  [Agent] Received Stripe webhook:")
    IO.puts("    Event: #{params.event}")
    IO.puts("    Payload: #{inspect(params.payload)}")

    current_events = Map.get(context.state, :events, [])
    events = [
      %{
        source: :stripe,
        event: params.event,
        payload: params.payload,
        received_at: params[:received_at] || DateTime.utc_now()
      }
      | current_events
    ]

    {:ok, %{events: events}}
  end
end

# =============================================================================
# SENSOR: RandomQuoteSensor
# 
# A simple sensor that emits random inspirational quotes at configurable intervals.
# This demonstrates the core Sensor pattern:
# 1. GenServer that observes/generates events (timer ticks)
# 2. Translates events into Jido Signals
# 3. Emits signals to a configured target (agent)
# =============================================================================

defmodule RandomQuoteSensor do
  @moduledoc """
  A sensor that emits random quotes at regular intervals.
  
  This demonstrates the Jido Sensor pattern without requiring
  the full `use Jido.Sensor` macro (which is part of the plan).
  """
  
  use GenServer
  alias Jido.Signal
  alias Jido.AgentServer

  @quotes [
    "The best way to predict the future is to create it.",
    "Code is like humor. When you have to explain it, it's bad.",
    "First, solve the problem. Then, write the code.",
    "Simplicity is the soul of efficiency.",
    "Make it work, make it right, make it fast.",
    "The only way to do great work is to love what you do.",
    "Talk is cheap. Show me the code.",
    "Any fool can write code that a computer can understand."
  ]

  defmodule Config do
    defstruct [:id, :target, :interval_ms, :category]
  end

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) do
    id = Keyword.get(opts, :id, __MODULE__)
    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    config = %Config{
      id: Keyword.fetch!(opts, :id),
      target: Keyword.fetch!(opts, :target),
      interval_ms: Keyword.get(opts, :interval_ms, 3_000),
      category: Keyword.get(opts, :category, "inspiration")
    }

    IO.puts("  [Sensor #{config.id}] Started, emitting every #{config.interval_ms}ms to #{inspect(config.target)}")
    
    schedule_emit(config.interval_ms)
    {:ok, %{config: config, emit_count: 0}}
  end

  @impl true
  def handle_info(:emit, state) do
    %{config: config, emit_count: count} = state
    
    quote = Enum.random(@quotes)
    new_count = count + 1
    
    # Create signal with type matching the route pattern
    signal = Signal.new!(
      "sensor.quote",
      %{
        quote: quote,
        category: config.category,
        emit_count: new_count,
        sensor_id: config.id
      },
      source: "/sensor/random_quote:#{config.id}"
    )

    emit_signal(signal, config.target)
    
    schedule_emit(config.interval_ms)
    {:noreply, %{state | emit_count: new_count}}
  end

  # Internal helpers

  defp schedule_emit(interval_ms) do
    Process.send_after(self(), :emit, interval_ms)
  end

  defp emit_signal(signal, target) when is_pid(target) do
    AgentServer.cast(target, signal)
  end

  defp emit_signal(signal, target) when is_binary(target) do
    AgentServer.cast(target, signal)
  end

  defp emit_signal(signal, {:agent, id}) do
    AgentServer.cast(id, signal)
  end
end

# =============================================================================
# WEBHOOK HELPER: Simulates external webhook injection
#
# For webhooks, you typically don't need a long-lived sensor process.
# Just create a signal and inject it directly.
# =============================================================================

defmodule WebhookHelper do
  @moduledoc """
  Helper module demonstrating webhook → signal pattern.
  
  In a real Phoenix app, this would be called from a controller.
  """

  alias Jido.Signal
  alias Jido.AgentServer

  def emit_github_event(agent_target, event_type, payload) do
    signal = Signal.new!(
      "webhook.github",
      %{
        event: event_type,
        payload: payload,
        received_at: DateTime.utc_now()
      },
      source: "/webhook/github"
    )

    AgentServer.cast(agent_target, signal)
  end

  def emit_stripe_event(agent_target, event_type, payload) do
    signal = Signal.new!(
      "webhook.stripe",
      %{
        event: event_type,
        payload: payload,
        received_at: DateTime.utc_now()
      },
      source: "/webhook/stripe"
    )

    AgentServer.cast(agent_target, signal)
  end
end

# =============================================================================
# AGENT: QuoteCollectorAgent
#
# An agent that receives signals from sensors and webhooks.
# Uses signal_routes/0 to map signal types to Actions.
# =============================================================================

defmodule QuoteCollectorAgent do
  @moduledoc """
  An agent that collects quotes from sensors and events from webhooks.
  
  Uses signal_routes/0 to map incoming signals to action handlers.
  """

  use Jido.Agent,
    name: "quote_collector",
    schema: [
      quotes: [type: {:list, :map}, default: []],
      events: [type: {:list, :map}, default: []],
      status: [type: :atom, default: :idle]
    ]

  # Map signal types to actions
  # Signal data is passed as action params
  def signal_routes do
    [
      {"sensor.quote", HandleQuoteAction},
      {"webhook.github", HandleGitHubWebhookAction},
      {"webhook.stripe", HandleStripeWebhookAction}
    ]
  end
end

# =============================================================================
# DEMO RUNNER
# =============================================================================

defmodule SensorDemoRunner do
  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts(">>> Jido Sensor Demo")
    IO.puts(String.duplicate("=", 60))
    
    # Start a Jido instance for the example
    {:ok, _} = Jido.start_link(name: SensorDemoRunner.Jido)

    # 1. Start the agent
    IO.puts("\n[1] Starting QuoteCollectorAgent...")
    {:ok, agent_pid} = Jido.start_agent(SensorDemoRunner.Jido, QuoteCollectorAgent, id: "collector-1")
    IO.puts("    Agent started: #{inspect(agent_pid)}")

    # 2. Start a sensor targeting the agent
    IO.puts("\n[2] Starting RandomQuoteSensor (interval: 2s)...")
    {:ok, _sensor_pid} = RandomQuoteSensor.start_link(
      id: "quote-sensor-1",
      target: agent_pid,
      interval_ms: 2_000,
      category: "programming"
    )

    # 3. Wait for a few quotes to come in
    IO.puts("\n[3] Waiting for sensor signals...")
    Process.sleep(5_000)

    # 4. Simulate webhook events (no sensor process needed)
    IO.puts("\n[4] Simulating webhook events...")
    
    IO.puts("    Sending GitHub push event...")
    WebhookHelper.emit_github_event(agent_pid, "push", %{
      ref: "refs/heads/main",
      commits: 3,
      repository: "myapp"
    })
    Process.sleep(500)

    IO.puts("    Sending Stripe payment event...")
    WebhookHelper.emit_stripe_event(agent_pid, "payment_intent.succeeded", %{
      amount: 9900,
      currency: "usd",
      customer: "cus_123"
    })
    Process.sleep(500)

    # 5. Wait for more quotes
    IO.puts("\n[5] Waiting for more sensor signals...")
    Process.sleep(4_000)

    # 6. Check final state
    IO.puts("\n[6] Checking agent state...")
    {:ok, state} = Jido.state(SensorDemoRunner.Jido, agent_pid)
    
    IO.puts("\n" <> String.duplicate("-", 60))
    IO.puts("FINAL STATE:")
    IO.puts(String.duplicate("-", 60))
    
    IO.puts("\nQuotes received: #{length(state.agent.state.quotes)}")
    for {quote, i} <- Enum.with_index(Enum.reverse(state.agent.state.quotes), 1) do
      IO.puts("  #{i}. \"#{quote.quote}\"")
    end

    IO.puts("\nEvents received: #{length(state.agent.state.events)}")
    for event <- Enum.reverse(state.agent.state.events) do
      IO.puts("  - [#{event.source}] #{event.event}")
    end

    # 7. Cleanup
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("[DONE] Sensor demo complete!")
    IO.puts(String.duplicate("=", 60) <> "\n")

    GenServer.stop(agent_pid, :normal)
  end
end

# Run the demo
SensorDemoRunner.run()
