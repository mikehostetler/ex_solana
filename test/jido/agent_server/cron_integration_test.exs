defmodule JidoTest.AgentServer.CronIntegrationTest do
  use ExUnit.Case

  @moduletag :integration
  @moduletag capture_log: true

  alias Jido.AgentServer
  alias Jido.Agent.Directive
  alias Jido.Signal

  defmodule CronCountAction do
    @moduledoc false
    use Jido.Action, name: "cron_count", schema: []

    def run(params, context) do
      count = Map.get(context.state, :tick_count, 0)
      ticks = Map.get(context.state, :ticks, [])
      {:ok, %{tick_count: count + 1, ticks: ticks ++ [params]}}
    end
  end

  defmodule RegisterCronAction do
    @moduledoc false
    use Jido.Action, name: "register_cron", schema: []

    def run(params, _context) do
      cron_expr = Map.get(params, :cron)
      job_id = Map.get(params, :job_id)
      message = Map.get(params, :message, Signal.new!(%{type: "cron.tick", source: "/test"}))
      timezone = Map.get(params, :timezone)

      directive = Directive.cron(cron_expr, message, job_id: job_id, timezone: timezone)
      {:ok, %{}, [directive]}
    end
  end

  defmodule CancelCronAction do
    @moduledoc false
    use Jido.Action, name: "cancel_cron", schema: []

    def run(%{job_id: job_id}, _context) do
      {:ok, %{}, [Directive.cron_cancel(job_id)]}
    end
  end

  defmodule CronTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "cron_test_agent",
      schema: [
        tick_count: [type: :integer, default: 0],
        ticks: [type: {:list, :any}, default: []]
      ]

    def signal_routes do
      [
        {"register_cron", RegisterCronAction},
        {"cancel_cron", CancelCronAction},
        {"cron.tick", CronCountAction}
      ]
    end
  end

  setup do
    :ok
  end

  describe "cron job registration" do
    test "agent can register a cron job" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-1")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :heartbeat,
            cron: "* * * * *"
          }
        })

      :ok = AgentServer.cast("cron-test-1", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-1")
      assert Map.has_key?(state.cron_jobs, :heartbeat)

      job_pid = state.cron_jobs[:heartbeat]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)

      GenServer.stop(pid)
    end

    test "agent can register multiple cron jobs" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-2")

      for {job_id, cron_expr} <- [heartbeat: "* * * * *", daily: "@daily", hourly: "@hourly"] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: cron_expr}
          })

        :ok = AgentServer.cast("cron-test-2", register_signal)
      end

      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-2")
      assert map_size(state.cron_jobs) == 3
      assert Map.has_key?(state.cron_jobs, :heartbeat)
      assert Map.has_key?(state.cron_jobs, :daily)
      assert Map.has_key?(state.cron_jobs, :hourly)

      # All should be pids
      for {_id, job_pid} <- state.cron_jobs do
        assert is_pid(job_pid)
        assert Process.alive?(job_pid)
      end

      GenServer.stop(pid)
    end

    test "registering same job_id updates existing job (upsert)" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-3")

      register_signal1 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-3", register_signal1)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-3")
      first_job_pid = state1.cron_jobs[:updatable]
      assert is_pid(first_job_pid)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :updatable, cron: "@hourly"}
        })

      :ok = AgentServer.cast("cron-test-3", register_signal2)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-3")
      assert map_size(state2.cron_jobs) == 1
      second_job_pid = state2.cron_jobs[:updatable]
      assert is_pid(second_job_pid)

      # The old pid should have been cancelled (may or may not be alive depending on timing)
      # The new pid should be different
      refute first_job_pid == second_job_pid

      GenServer.stop(pid)
    end

    test "cron job with timezone" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-4")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{
            job_id: :timezone_test,
            cron: "0 9 * * *",
            timezone: "America/New_York"
          }
        })

      :ok = AgentServer.cast("cron-test-4", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-4")
      assert Map.has_key?(state.cron_jobs, :timezone_test)
      assert is_pid(state.cron_jobs[:timezone_test])

      GenServer.stop(pid)
    end

    test "auto-generates job_id if not provided" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-5")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-5", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-5")
      assert map_size(state.cron_jobs) == 1

      [job_id] = Map.keys(state.cron_jobs)
      assert is_reference(job_id)

      GenServer.stop(pid)
    end
  end

  describe "cron job cancellation" do
    test "agent can cancel a cron job" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-6")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cancellable, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-6", register_signal)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-6")
      assert Map.has_key?(state1.cron_jobs, :cancellable)
      job_pid = state1.cron_jobs[:cancellable]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :cancellable}
        })

      :ok = AgentServer.cast("cron-test-6", cancel_signal)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-6")
      refute Map.has_key?(state2.cron_jobs, :cancellable)

      # The job pid should no longer be alive
      refute Process.alive?(job_pid)

      GenServer.stop(pid)
    end

    test "cancelling non-existent job is safe" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-7")

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :nonexistent}
        })

      :ok = AgentServer.cast("cron-test-7", cancel_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-7")
      assert map_size(state.cron_jobs) == 0

      GenServer.stop(pid)
    end

    test "can cancel and re-register same job_id" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-8")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-8", register_signal)
      Process.sleep(100)

      cancel_signal =
        Signal.new!(%{
          type: "cancel_cron",
          source: "/test",
          data: %{job_id: :toggle}
        })

      :ok = AgentServer.cast("cron-test-8", cancel_signal)
      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-8")
      refute Map.has_key?(state1.cron_jobs, :toggle)

      register_signal2 =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :toggle, cron: "@hourly"}
        })

      :ok = AgentServer.cast("cron-test-8", register_signal2)
      Process.sleep(100)

      {:ok, state2} = AgentServer.state("cron-test-8")
      assert Map.has_key?(state2.cron_jobs, :toggle)
      assert is_pid(state2.cron_jobs[:toggle])

      GenServer.stop(pid)
    end
  end

  describe "cleanup on agent termination" do
    test "cron jobs are cleaned up when agent stops normally" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-10")

      register_signal =
        Signal.new!(%{
          type: "register_cron",
          source: "/test",
          data: %{job_id: :cleanup_test, cron: "* * * * *"}
        })

      :ok = AgentServer.cast("cron-test-10", register_signal)
      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-10")
      job_pid = state.cron_jobs[:cleanup_test]
      assert is_pid(job_pid)
      assert Process.alive?(job_pid)

      GenServer.stop(pid)
      Process.sleep(100)

      # The job pid should no longer be alive after agent terminates
      refute Process.alive?(job_pid)
    end

    test "multiple cron jobs are all cleaned up on termination" do
      {:ok, pid} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-11")

      job_ids = [:job1, :job2, :job3]

      for job_id <- job_ids do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: job_id, cron: "* * * * *"}
          })

        :ok = AgentServer.cast("cron-test-11", register_signal)
      end

      Process.sleep(100)

      {:ok, state} = AgentServer.state("cron-test-11")
      job_pids = Enum.map(job_ids, fn id -> state.cron_jobs[id] end)

      # All pids should be alive before termination
      for job_pid <- job_pids do
        assert is_pid(job_pid)
        assert Process.alive?(job_pid)
      end

      GenServer.stop(pid)
      Process.sleep(100)

      # All pids should be dead after termination
      for job_pid <- job_pids do
        refute Process.alive?(job_pid)
      end
    end
  end

  describe "job scoping" do
    test "different agents can use same job_id without collision" do
      {:ok, pid1} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12a")
      {:ok, pid2} = AgentServer.start_link(agent: CronTestAgent, id: "cron-test-12b")

      for agent_id <- ["cron-test-12a", "cron-test-12b"] do
        register_signal =
          Signal.new!(%{
            type: "register_cron",
            source: "/test",
            data: %{job_id: :shared_name, cron: "* * * * *"}
          })

        :ok = AgentServer.cast(agent_id, register_signal)
      end

      Process.sleep(100)

      {:ok, state1} = AgentServer.state("cron-test-12a")
      {:ok, state2} = AgentServer.state("cron-test-12b")

      assert Map.has_key?(state1.cron_jobs, :shared_name)
      assert Map.has_key?(state2.cron_jobs, :shared_name)

      job_pid1 = state1.cron_jobs[:shared_name]
      job_pid2 = state2.cron_jobs[:shared_name]

      # Each agent has its own SchedEx process
      refute job_pid1 == job_pid2
      assert Process.alive?(job_pid1)
      assert Process.alive?(job_pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end
end
