defmodule Jido.Signal.DispatchStressTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch

  @moduletag :stress
  @moduletag timeout: 60_000

  describe "concurrent dispatch stress tests" do
    @tag :capture_log
    test "handles 1000 concurrent dispatches" do
      {:ok, signal} = Signal.new("stress.concurrent", %{batch: 1000})

      configs =
        Enum.map(1..1000, fn _i ->
          {:noop, []}
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n1000 concurrent dispatches completed in #{elapsed_ms}ms")

      assert :ok = result
      assert elapsed_ms < 10_000, "Should complete in less than 10 seconds"
    end

    @tag :capture_log
    test "handles varying concurrency limits" do
      {:ok, signal} = Signal.new("stress.limited", %{batch: 500})

      configs =
        Enum.map(1..500, fn _i ->
          {:noop, []}
        end)

      concurrency_limits = [1, 10, 50, 100, 500]

      for limit <- concurrency_limits do
        {elapsed_us, result} =
          :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs, max_concurrency: limit) end)

        _elapsed_ms = div(elapsed_us, 1000)

        # IO.puts("500 dispatches with max_concurrency=#{limit} completed in #{elapsed_ms}ms")

        assert :ok = result
      end
    end
  end

  describe "batch dispatch stress tests" do
    @tag :capture_log
    test "handles batch dispatch with 10k configs" do
      {:ok, signal} = Signal.new("stress.batch", %{batch: 10_000})

      configs =
        Enum.map(1..10_000, fn _i ->
          {:noop, []}
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n10,000 batch dispatches completed in #{elapsed_ms}ms")

      assert :ok = result
      assert elapsed_ms < 30_000, "Should complete in less than 30 seconds"
    end

    @tag :capture_log
    test "handles batch dispatch with mixed adapter types" do
      {:ok, signal} = Signal.new("stress.mixed", %{})

      configs =
        Enum.flat_map(1..1000, fn _i ->
          [
            {:noop, []},
            {:logger, [level: :debug]}
          ]
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n2,000 mixed adapter dispatches completed in #{elapsed_ms}ms")

      assert :ok = result
    end
  end

  describe "memory and resource stress tests" do
    @tag :capture_log
    test "handles rapid sequential dispatch_batch calls" do
      {elapsed_us, total_dispatches} =
        :timer.tc(fn ->
          Enum.reduce(1..100, 0, fn batch, acc ->
            {:ok, signal} = Signal.new("stress.sequential", %{batch: batch})

            configs =
              Enum.map(1..100, fn _i ->
                {:noop, []}
              end)

            assert :ok = Dispatch.dispatch_batch(signal, configs)
            acc + length(configs)
          end)
        end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n100 batches of 100 dispatches (10,000 total) completed in #{elapsed_ms}ms")

      assert total_dispatches == 10_000
    end

    @tag :capture_log
    test "handles large payloads in bulk" do
      large_data = %{
        data: String.duplicate("x", 1000),
        nested: %{
          items: Enum.map(1..100, fn i -> %{id: i, value: "item_#{i}"} end)
        }
      }

      {:ok, signal} = Signal.new("stress.large_payload", large_data)

      configs =
        Enum.map(1..1000, fn _i ->
          {:noop, []}
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n1,000 large payload dispatches completed in #{elapsed_ms}ms")

      assert :ok = result
    end
  end

  describe "batch size stress tests" do
    @tag :capture_log
    test "handles different batch sizes efficiently" do
      {:ok, signal} = Signal.new("stress.batch_sizes", %{})

      configs =
        Enum.map(1..1000, fn _i ->
          {:noop, []}
        end)

      batch_sizes = [1, 10, 50, 100, 500, 1000]

      for size <- batch_sizes do
        {elapsed_us, result} =
          :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs, batch_size: size) end)

        _elapsed_ms = div(elapsed_us, 1000)

        # IO.puts("1000 dispatches with batch_size=#{size} completed in #{elapsed_ms}ms")

        assert :ok = result
      end
    end
  end

  describe "combined stress scenarios" do
    @tag :capture_log
    test "handles complex mixed scenario" do
      {:ok, signal} = Signal.new("stress.complex", %{})

      configs =
        Enum.flat_map(1..500, fn _i ->
          [
            {:noop, []},
            {:logger, [level: :debug]},
            {:logger, [level: :info]},
            {:noop, []}
          ]
        end)

      {elapsed_us, result} =
        :timer.tc(fn ->
          Dispatch.dispatch_batch(signal, configs, batch_size: 100, max_concurrency: 50)
        end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n2,000 mixed scenario dispatches completed in #{elapsed_ms}ms")

      assert :ok = result
    end
  end

  describe "PID dispatch stress" do
    test "handles 1000 PID dispatches" do
      {:ok, signal} = Signal.new("stress.pid", %{})
      test_pid = self()

      configs =
        Enum.map(1..1000, fn _i ->
          {:pid, [target: test_pid]}
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n1,000 PID dispatches completed in #{elapsed_ms}ms")

      assert :ok = result

      for _i <- 1..1000 do
        assert_received {:signal, %Signal{type: "stress.pid"}}
      end
    end

    test "concurrent PID dispatches to multiple processes" do
      {:ok, signal} = Signal.new("stress.multi_pid", %{})

      pids =
        Enum.map(1..10, fn _i ->
          spawn(fn ->
            # Receive 100 messages before terminating
            Enum.each(1..100, fn _j ->
              receive do
                {:signal, _signal} -> :ok
              end
            end)
          end)
        end)

      configs =
        Enum.flat_map(pids, fn pid ->
          Enum.map(1..100, fn _i -> {:pid, [target: pid]} end)
        end)

      {elapsed_us, result} =
        :timer.tc(fn -> Dispatch.dispatch_batch(signal, configs) end)

      _elapsed_ms = div(elapsed_us, 1000)

      # IO.puts("\n1,000 dispatches to 10 different PIDs completed in #{elapsed_ms}ms")

      assert :ok = result
    end
  end
end
