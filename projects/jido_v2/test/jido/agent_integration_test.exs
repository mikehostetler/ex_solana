defmodule JidoTest.Agent.IntegrationTest do
  @moduledoc """
  Integration tests for Jido.Agent v2 kernel.

  These tests exercise the core agent contract end-to-end:
  - State transitions via handle_signal/2
  - Effect generation
  - Zoi schema validation
  """
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Agent.Effect

  # ---------------------------------------------------------------------------
  # Example Agent: EventCounterAgent
  # ---------------------------------------------------------------------------

  defmodule EventCounterAgent do
    @moduledoc """
    A simple metrics agent that counts events by type.

    Exercises:
    - Zoi schema with map, integer, string, defaults, optional
    - Pattern matching on signal types
    - Effect.Reply generation
    - State transitions
    """
    use Jido.Agent,
      name: "event_counter",
      schema: %{
        counts: Zoi.map() |> Zoi.default(%{}),
        total: Zoi.integer() |> Zoi.non_negative() |> Zoi.default(0),
        last_event_type: Zoi.string() |> Zoi.optional()
      }

    @impl true
    def handle_signal(state, %Signal{type: "metrics.event", data: %{"type" => type}}) do
      current = Map.get(state.counts, type, 0)
      new_counts = Map.put(state.counts, type, current + 1)

      new_state = %{
        state
        | counts: new_counts,
          total: state.total + 1,
          last_event_type: type
      }

      {:ok, new_state, []}
    end

    def handle_signal(state, %Signal{type: "metrics.snapshot_requested"}) do
      effects = [
        %Effect.Reply{
          signal:
            Signal.new!("metrics.snapshot", %{
              counts: state.counts,
              total: state.total,
              last_event_type: state.last_event_type
            })
        }
      ]

      {:ok, state, effects}
    end

    def handle_signal(state, _signal), do: {:ok, state, []}
  end

  # ---------------------------------------------------------------------------
  # Example Agent: OrderWorkflowAgent
  # ---------------------------------------------------------------------------

  defmodule OrderWorkflowAgent do
    @moduledoc """
    A multi-step order workflow agent.

    Exercises:
    - Multiple state transitions
    - All three effect types: Run, Reply, Timer
    - Conditional logic in handle_signal
    - Rich Zoi schema
    """
    use Jido.Agent,
      name: "order_workflow",
      schema: %{
        customer_id: Zoi.string() |> Zoi.optional(),
        total_cents: Zoi.integer() |> Zoi.non_negative() |> Zoi.default(0),
        status: Zoi.atom() |> Zoi.default(:pending),
        items: Zoi.array(Zoi.map()) |> Zoi.default([]),
        attempts: Zoi.integer() |> Zoi.non_negative() |> Zoi.default(0),
        last_error: Zoi.string() |> Zoi.optional()
      }

    @impl true
    def handle_signal(state, %Signal{type: "order.created"}) do
      new_state = %{state | status: :pending_payment}

      effects = [
        %Effect.Run{
          action: FakeReserveInventory,
          params: %{order_id: state.id, items: state.items}
        },
        %Effect.Timer{
          in: 15_000,
          key: :payment_timeout,
          signal: Signal.new!("order.payment_timeout", %{order_id: state.id})
        }
      ]

      {:ok, new_state, effects}
    end

    def handle_signal(state, %Signal{type: "order.payment_succeeded"}) do
      new_state = %{state | status: :fulfilled, last_error: nil}

      effects = [
        %Effect.Run{
          action: FakeSendReceiptEmail,
          params: %{order_id: state.id, customer_id: state.customer_id}
        },
        %Effect.Reply{
          signal:
            Signal.new!("order.confirmed", %{
              order_id: state.id,
              total_cents: state.total_cents
            })
        }
      ]

      {:ok, new_state, effects}
    end

    def handle_signal(state, %Signal{type: "order.payment_failed", data: data}) do
      reason = Map.get(data, "reason", "unknown")
      attempts = state.attempts + 1
      new_state = %{state | status: :payment_failed, attempts: attempts, last_error: reason}

      effects =
        if attempts < 3 do
          [
            %Effect.Reply{
              signal:
                Signal.new!("order.payment_retry_requested", %{
                  order_id: state.id,
                  attempts: attempts
                })
            }
          ]
        else
          [
            %Effect.Reply{
              signal:
                Signal.new!("order.cancelled", %{
                  order_id: state.id,
                  reason: "too_many_failures"
                })
            }
          ]
        end

      {:ok, new_state, effects}
    end

    def handle_signal(state, %Signal{type: "order.payment_timeout"}) do
      {new_state, effects} =
        case state.status do
          :pending_payment ->
            {
              %{state | status: :payment_timeout},
              [
                %Effect.Reply{
                  signal: Signal.new!("order.timed_out", %{order_id: state.id})
                }
              ]
            }

          _other ->
            {state, []}
        end

      {:ok, new_state, effects}
    end

    def handle_signal(state, _signal), do: {:ok, state, []}
  end

  # ---------------------------------------------------------------------------
  # Tests: EventCounterAgent
  # ---------------------------------------------------------------------------

  describe "EventCounterAgent" do
    test "new/0 creates agent with defaults" do
      {:ok, agent} = EventCounterAgent.new()

      assert agent.counts == %{}
      assert agent.total == 0
      assert agent.last_event_type == nil
    end

    test "new/1 creates agent with provided values" do
      {:ok, agent} = EventCounterAgent.new(%{id: "counter-1"})

      assert agent.id == "counter-1"
      assert agent.counts == %{}
    end

    test "handle_signal increments counts for metrics.event" do
      {:ok, agent} = EventCounterAgent.new(%{id: "counter-1"})

      signal = Signal.new!("metrics.event", %{"type" => "page_view"}, source: "/test")
      {:ok, agent, effects} = EventCounterAgent.handle_signal(agent, signal)

      assert agent.counts == %{"page_view" => 1}
      assert agent.total == 1
      assert agent.last_event_type == "page_view"
      assert effects == []
    end

    test "handle_signal tracks multiple event types" do
      {:ok, agent} = EventCounterAgent.new(%{id: "counter-1"})

      # Send different event types
      signal1 = Signal.new!("metrics.event", %{"type" => "page_view"}, source: "/test")
      {:ok, agent, _} = EventCounterAgent.handle_signal(agent, signal1)

      signal2 = Signal.new!("metrics.event", %{"type" => "click"}, source: "/test")
      {:ok, agent, _} = EventCounterAgent.handle_signal(agent, signal2)

      signal3 = Signal.new!("metrics.event", %{"type" => "page_view"}, source: "/test")
      {:ok, agent, _} = EventCounterAgent.handle_signal(agent, signal3)

      assert agent.counts == %{"page_view" => 2, "click" => 1}
      assert agent.total == 3
      assert agent.last_event_type == "page_view"
    end

    test "handle_signal returns Reply effect for snapshot_requested" do
      {:ok, agent} = EventCounterAgent.new(%{id: "counter-1"})

      # Add some events first
      signal1 = Signal.new!("metrics.event", %{"type" => "login"}, source: "/test")
      {:ok, agent, _} = EventCounterAgent.handle_signal(agent, signal1)

      # Request snapshot
      snapshot_signal = Signal.new!("metrics.snapshot_requested", %{}, source: "/test")
      {:ok, returned_agent, effects} = EventCounterAgent.handle_signal(agent, snapshot_signal)

      # State should be unchanged
      assert returned_agent == agent

      # Should have one Reply effect
      assert length(effects) == 1
      assert %Effect.Reply{signal: reply_signal} = hd(effects)
      assert reply_signal.type == "metrics.snapshot"
      assert reply_signal.data.counts == %{"login" => 1}
      assert reply_signal.data.total == 1
    end

    test "handle_signal ignores unknown signals" do
      {:ok, agent} = EventCounterAgent.new(%{id: "counter-1"})

      signal = Signal.new!("unknown.signal", %{}, source: "/test")
      {:ok, returned_agent, effects} = EventCounterAgent.handle_signal(agent, signal)

      assert returned_agent == agent
      assert effects == []
    end
  end

  # ---------------------------------------------------------------------------
  # Tests: OrderWorkflowAgent
  # ---------------------------------------------------------------------------

  describe "OrderWorkflowAgent" do
    test "new/1 creates agent with defaults" do
      {:ok, agent} = OrderWorkflowAgent.new(%{id: "order-1", customer_id: "cust-1"})

      assert agent.id == "order-1"
      assert agent.customer_id == "cust-1"
      assert agent.status == :pending
      assert agent.attempts == 0
      assert agent.items == []
    end

    test "order.created transitions to pending_payment with Run and Timer effects" do
      {:ok, agent} =
        OrderWorkflowAgent.new(%{
          id: "order-1",
          customer_id: "cust-1",
          items: [%{"sku" => "ABC", "qty" => 2}]
        })

      signal = Signal.new!("order.created", %{}, source: "/checkout")
      {:ok, agent, effects} = OrderWorkflowAgent.handle_signal(agent, signal)

      assert agent.status == :pending_payment
      assert length(effects) == 2

      # First effect: Run to reserve inventory
      assert %Effect.Run{action: FakeReserveInventory, params: params} = Enum.at(effects, 0)
      assert params.order_id == "order-1"

      # Second effect: Timer for payment timeout
      assert %Effect.Timer{in: 15_000, key: :payment_timeout} = Enum.at(effects, 1)
    end

    test "order.payment_succeeded transitions to fulfilled" do
      {:ok, agent} =
        OrderWorkflowAgent.new(%{
          id: "order-1",
          customer_id: "cust-1",
          total_cents: 1999,
          status: :pending_payment
        })

      signal = Signal.new!("order.payment_succeeded", %{}, source: "/payments")
      {:ok, agent, effects} = OrderWorkflowAgent.handle_signal(agent, signal)

      assert agent.status == :fulfilled
      assert agent.last_error == nil
      assert length(effects) == 2

      # Run effect for email
      assert %Effect.Run{action: FakeSendReceiptEmail} = Enum.at(effects, 0)

      # Reply effect for confirmation
      assert %Effect.Reply{signal: reply} = Enum.at(effects, 1)
      assert reply.type == "order.confirmed"
      assert reply.data.total_cents == 1999
    end

    test "order.payment_failed increments attempts and requests retry" do
      {:ok, agent} =
        OrderWorkflowAgent.new(%{
          id: "order-1",
          status: :pending_payment
        })

      signal = Signal.new!("order.payment_failed", %{"reason" => "declined"}, source: "/payments")
      {:ok, agent, effects} = OrderWorkflowAgent.handle_signal(agent, signal)

      assert agent.status == :payment_failed
      assert agent.attempts == 1
      assert agent.last_error == "declined"

      assert [%Effect.Reply{signal: reply}] = effects
      assert reply.type == "order.payment_retry_requested"
      assert reply.data.attempts == 1
    end

    test "order.payment_failed cancels after 3 attempts" do
      {:ok, agent} =
        OrderWorkflowAgent.new(%{
          id: "order-1",
          status: :pending_payment,
          attempts: 2
        })

      signal = Signal.new!("order.payment_failed", %{"reason" => "declined"}, source: "/payments")
      {:ok, agent, effects} = OrderWorkflowAgent.handle_signal(agent, signal)

      assert agent.status == :payment_failed
      assert agent.attempts == 3

      assert [%Effect.Reply{signal: reply}] = effects
      assert reply.type == "order.cancelled"
      assert reply.data.reason == "too_many_failures"
    end

    test "order.payment_timeout only triggers when pending_payment" do
      # When pending_payment -> should transition
      {:ok, pending_agent} =
        OrderWorkflowAgent.new(%{
          id: "order-1",
          status: :pending_payment
        })

      signal = Signal.new!("order.payment_timeout", %{}, source: "/timer")
      {:ok, timed_out_agent, effects} = OrderWorkflowAgent.handle_signal(pending_agent, signal)

      assert timed_out_agent.status == :payment_timeout
      assert length(effects) == 1

      # When already fulfilled -> should be no-op
      {:ok, fulfilled_agent} =
        OrderWorkflowAgent.new(%{
          id: "order-2",
          status: :fulfilled
        })

      {:ok, still_fulfilled, effects} = OrderWorkflowAgent.handle_signal(fulfilled_agent, signal)

      assert still_fulfilled.status == :fulfilled
      assert effects == []
    end
  end
end
