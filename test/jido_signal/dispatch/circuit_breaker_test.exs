defmodule Jido.Signal.Dispatch.CircuitBreakerTest do
  use ExUnit.Case, async: false

  alias Jido.Signal.Dispatch.CircuitBreaker

  @test_adapter :test_circuit_adapter

  setup do
    adapter = :"#{@test_adapter}_#{:erlang.unique_integer([:positive])}"
    {:ok, adapter: adapter}
  end

  describe "install/2" do
    test "installs a circuit breaker", %{adapter: adapter} do
      assert :ok = CircuitBreaker.install(adapter)
      assert CircuitBreaker.installed?(adapter)
    end

    test "is idempotent - returns :ok if already installed", %{adapter: adapter} do
      assert :ok = CircuitBreaker.install(adapter)
      assert :ok = CircuitBreaker.install(adapter)
    end

    test "accepts custom configuration", %{adapter: adapter} do
      opts = [
        strategy: {:standard, 2, 5_000},
        refresh: 10_000
      ]

      assert :ok = CircuitBreaker.install(adapter, opts)
      assert CircuitBreaker.installed?(adapter)
    end
  end

  describe "run/2" do
    test "executes function when circuit is closed", %{adapter: adapter} do
      CircuitBreaker.install(adapter)

      result = CircuitBreaker.run(adapter, fn -> {:ok, :success} end)
      assert result == {:ok, :success}
    end

    test "returns :ok for successful functions returning :ok", %{adapter: adapter} do
      CircuitBreaker.install(adapter)

      result = CircuitBreaker.run(adapter, fn -> :ok end)
      assert result == :ok
    end

    test "records failure and returns error", %{adapter: adapter} do
      CircuitBreaker.install(adapter)

      result = CircuitBreaker.run(adapter, fn -> {:error, :some_error} end)
      assert result == {:error, :some_error}
    end

    test "handles exceptions", %{adapter: adapter} do
      CircuitBreaker.install(adapter)

      result =
        CircuitBreaker.run(adapter, fn ->
          raise "test exception"
        end)

      assert {:error, {:exception, "test exception"}} = result
    end
  end

  describe "circuit opens after failures" do
    test "opens circuit after threshold failures", %{adapter: adapter} do
      # {:standard, N, window} means: allow N failures, blow on N+1th
      CircuitBreaker.install(adapter, strategy: {:standard, 1, 5_000}, refresh: 30_000)

      # First failure - still within tolerance
      CircuitBreaker.run(adapter, fn -> {:error, :fail1} end)
      assert CircuitBreaker.status(adapter) == :ok

      # Second failure - exceeds threshold, circuit blows
      CircuitBreaker.run(adapter, fn -> {:error, :fail2} end)
      assert CircuitBreaker.status(adapter) == :blown
    end

    test "returns :circuit_open when circuit is open", %{adapter: adapter} do
      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 30_000)

      # First failure blows the circuit
      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      result = CircuitBreaker.run(adapter, fn -> {:ok, :should_not_run} end)
      assert result == {:error, :circuit_open}
    end
  end

  describe "status/1" do
    test "returns :ok when circuit is closed", %{adapter: adapter} do
      CircuitBreaker.install(adapter)
      assert CircuitBreaker.status(adapter) == :ok
    end

    test "returns :blown when circuit is open", %{adapter: adapter} do
      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 30_000)

      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      assert CircuitBreaker.status(adapter) == :blown
    end
  end

  describe "reset/1" do
    test "resets an open circuit", %{adapter: adapter} do
      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 30_000)

      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      assert CircuitBreaker.status(adapter) == :blown

      assert :ok = CircuitBreaker.reset(adapter)
      assert CircuitBreaker.status(adapter) == :ok
    end

    test "allows requests after reset", %{adapter: adapter} do
      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 30_000)

      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      assert CircuitBreaker.status(adapter) == :blown

      CircuitBreaker.reset(adapter)

      result = CircuitBreaker.run(adapter, fn -> {:ok, :success} end)
      assert result == {:ok, :success}
    end
  end

  describe "installed?/1" do
    test "returns true for installed circuit", %{adapter: adapter} do
      CircuitBreaker.install(adapter)
      assert CircuitBreaker.installed?(adapter) == true
    end

    test "returns false for non-installed circuit" do
      assert CircuitBreaker.installed?(:non_existent_adapter_xyz) == false
    end
  end

  describe "telemetry events" do
    test "emits melt event on failure", %{adapter: adapter} do
      test_pid = self()
      handler_id = "test-melt-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:jido, :dispatch, :circuit, :melt],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      CircuitBreaker.install(adapter)
      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      assert_receive {:telemetry, [:jido, :dispatch, :circuit, :melt], %{}, %{adapter: ^adapter}}

      :telemetry.detach(handler_id)
    end

    test "emits rejected event when circuit is open", %{adapter: adapter} do
      test_pid = self()
      handler_id = "test-rejected-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:jido, :dispatch, :circuit, :rejected],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 30_000)
      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      CircuitBreaker.run(adapter, fn -> {:ok, :should_not_run} end)

      assert_receive {:telemetry, [:jido, :dispatch, :circuit, :rejected], %{},
                      %{adapter: ^adapter}}

      :telemetry.detach(handler_id)
    end

    test "emits reset event on reset", %{adapter: adapter} do
      test_pid = self()
      handler_id = "test-reset-#{:erlang.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:jido, :dispatch, :circuit, :reset],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      CircuitBreaker.install(adapter)
      CircuitBreaker.reset(adapter)

      assert_receive {:telemetry, [:jido, :dispatch, :circuit, :reset], %{}, %{adapter: ^adapter}}

      :telemetry.detach(handler_id)
    end
  end

  describe "circuit auto-reset after timeout" do
    @tag :flaky
    test "circuit resets after refresh timeout", %{adapter: adapter} do
      # Allow 0 failures (blow on first)
      CircuitBreaker.install(adapter, strategy: {:standard, 0, 5_000}, refresh: 100)

      CircuitBreaker.run(adapter, fn -> {:error, :fail} end)

      assert CircuitBreaker.status(adapter) == :blown

      Process.sleep(150)

      result = CircuitBreaker.run(adapter, fn -> {:ok, :success} end)
      assert result == {:ok, :success}
    end
  end
end
