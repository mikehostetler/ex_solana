defmodule JidoTest.Agent.Directive.CronTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.Cron
  alias Jido.Signal

  describe "Cron directive creation" do
    test "creates cron directive with required fields" do
      message = Signal.new!(%{type: "test.tick", source: "/test", data: %{}})
      directive = %Cron{cron: "* * * * *", message: message}

      assert %Cron{} = directive
      assert directive.cron == "* * * * *"
      assert directive.message == message
      assert directive.job_id == nil
      assert directive.timezone == nil
    end

    test "creates cron directive with all fields" do
      message = Signal.new!(%{type: "test.tick", source: "/test", data: %{}})

      directive = %Cron{
        cron: "@daily",
        message: message,
        job_id: :cleanup,
        timezone: "America/New_York"
      }

      assert directive.cron == "@daily"
      assert directive.message == message
      assert directive.job_id == :cleanup
      assert directive.timezone == "America/New_York"
    end

    test "creates cron directive with atom job_id" do
      directive = %Cron{cron: "*/5 * * * *", message: :tick_msg, job_id: :heartbeat}

      assert directive.job_id == :heartbeat
    end

    test "creates cron directive with string job_id" do
      directive = %Cron{cron: "0 0 * * *", message: :daily, job_id: "daily_task"}

      assert directive.job_id == "daily_task"
    end

    test "supports various cron expression formats" do
      test_expressions = [
        "* * * * *",
        "@hourly",
        "@daily",
        "@weekly",
        "@monthly",
        "*/15 * * * *",
        "0 9 * * MON",
        "0 0 1 * *"
      ]

      for expr <- test_expressions do
        directive = %Cron{cron: expr, message: :test}
        assert directive.cron == expr
      end
    end
  end

  describe "Directive.cron/3 helper" do
    test "creates cron directive with minimal arguments" do
      message = Signal.new!(%{type: "test.tick", source: "/test", data: %{}})
      directive = Directive.cron("* * * * *", message)

      assert %Cron{} = directive
      assert directive.cron == "* * * * *"
      assert directive.message == message
      assert directive.job_id == nil
      assert directive.timezone == nil
    end

    test "creates cron directive with job_id option" do
      directive = Directive.cron("@daily", :cleanup_msg, job_id: :daily_cleanup)

      assert directive.cron == "@daily"
      assert directive.message == :cleanup_msg
      assert directive.job_id == :daily_cleanup
      assert directive.timezone == nil
    end

    test "creates cron directive with timezone option" do
      directive = Directive.cron("0 9 * * *", :morning_task, timezone: "America/Los_Angeles")

      assert directive.cron == "0 9 * * *"
      assert directive.timezone == "America/Los_Angeles"
    end

    test "creates cron directive with both job_id and timezone" do
      directive =
        Directive.cron(
          "0 9 * * MON",
          :weekly_signal,
          job_id: :monday_9am,
          timezone: "America/New_York"
        )

      assert directive.job_id == :monday_9am
      assert directive.timezone == "America/New_York"
    end

    test "handles signal structs as messages" do
      signal = Signal.new!(%{type: "cron.tick", source: "/scheduler", data: %{count: 1}})
      directive = Directive.cron("*/5 * * * *", signal, job_id: :check)

      assert %Signal{} = directive.message
      assert directive.message.type == "cron.tick"
    end

    test "handles atom messages" do
      directive = Directive.cron("* * * * *", :tick)

      assert directive.message == :tick
    end

    test "handles map messages" do
      message = %{action: "cleanup", priority: :high}
      directive = Directive.cron("@daily", message)

      assert directive.message == message
    end
  end

  describe "schema validation" do
    test "has valid schema" do
      assert is_struct(Cron.schema())
    end

    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(Cron, %{message: :test})
      end

      assert_raise ArgumentError, fn ->
        struct!(Cron, %{cron: "* * * * *"})
      end
    end

    test "allows optional fields to be nil" do
      directive = %Cron{cron: "* * * * *", message: :test}

      assert directive.job_id == nil
      assert directive.timezone == nil
    end
  end
end
