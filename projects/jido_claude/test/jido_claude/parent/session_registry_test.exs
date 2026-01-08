defmodule JidoClaude.Parent.SessionRegistryTest do
  use ExUnit.Case, async: true

  alias JidoClaude.Parent.SessionRegistry

  describe "init_sessions/1" do
    test "adds empty sessions map if not present" do
      state = %{other: :data}
      result = SessionRegistry.init_sessions(state)

      assert result.sessions == %{}
      assert result.other == :data
    end

    test "preserves existing sessions map" do
      state = %{sessions: %{"existing" => %{status: :running}}}
      result = SessionRegistry.init_sessions(state)

      assert result.sessions == %{"existing" => %{status: :running}}
    end
  end

  describe "register_session/3" do
    test "adds session with default values" do
      state = %{sessions: %{}}
      result = SessionRegistry.register_session(state, "test-123", %{prompt: "Hello"})

      session = result.sessions["test-123"]
      assert session.status == :starting
      assert session.prompt == "Hello"
      assert session.turns == 0
      assert %DateTime{} = session.started_at
      assert %DateTime{} = session.last_activity
    end

    test "merges custom attributes" do
      state = %{sessions: %{}}

      result =
        SessionRegistry.register_session(state, "test-123", %{
          prompt: "Hello",
          model: "opus",
          meta: %{pr_number: 123}
        })

      session = result.sessions["test-123"]
      assert session.model == "opus"
      assert session.meta == %{pr_number: 123}
    end
  end

  describe "update_session/3" do
    test "updates session and refreshes last_activity" do
      now = DateTime.utc_now()

      state = %{
        sessions: %{
          "test-123" => %{
            status: :starting,
            turns: 0,
            last_activity: DateTime.add(now, -60, :second)
          }
        }
      }

      result = SessionRegistry.update_session(state, "test-123", %{status: :running, turns: 5})

      session = result.sessions["test-123"]
      assert session.status == :running
      assert session.turns == 5
      assert DateTime.compare(session.last_activity, now) in [:gt, :eq]
    end
  end

  describe "get_session/2" do
    test "returns session by id" do
      state = %{sessions: %{"test-123" => %{status: :running}}}

      assert SessionRegistry.get_session(state, "test-123") == %{status: :running}
    end

    test "returns nil for unknown session" do
      state = %{sessions: %{}}

      assert SessionRegistry.get_session(state, "unknown") == nil
    end
  end

  describe "remove_session/2" do
    test "removes session from registry" do
      state = %{sessions: %{"test-123" => %{}, "other" => %{}}}
      result = SessionRegistry.remove_session(state, "test-123")

      refute Map.has_key?(result.sessions, "test-123")
      assert Map.has_key?(result.sessions, "other")
    end
  end

  describe "active_sessions/1" do
    test "returns only starting and running sessions" do
      state = %{
        sessions: %{
          "starting" => %{status: :starting},
          "running" => %{status: :running},
          "success" => %{status: :success},
          "failure" => %{status: :failure}
        }
      }

      result = SessionRegistry.active_sessions(state)

      assert map_size(result) == 2
      assert Map.has_key?(result, "starting")
      assert Map.has_key?(result, "running")
    end
  end

  describe "completed_sessions/1" do
    test "returns only completed sessions" do
      state = %{
        sessions: %{
          "running" => %{status: :running},
          "success" => %{status: :success},
          "failure" => %{status: :failure},
          "cancelled" => %{status: :cancelled}
        }
      }

      result = SessionRegistry.completed_sessions(state)

      assert map_size(result) == 3
      assert Map.has_key?(result, "success")
      assert Map.has_key?(result, "failure")
      assert Map.has_key?(result, "cancelled")
    end
  end

  describe "count_active/1" do
    test "counts active sessions" do
      state = %{
        sessions: %{
          "running1" => %{status: :running},
          "running2" => %{status: :running},
          "success" => %{status: :success}
        }
      }

      assert SessionRegistry.count_active(state) == 2
    end
  end

  describe "total_cost/1" do
    test "sums cost across all sessions" do
      state = %{
        sessions: %{
          "a" => %{cost_usd: 0.01},
          "b" => %{cost_usd: 0.02},
          "c" => %{}
        }
      }

      assert SessionRegistry.total_cost(state) == 0.03
    end
  end

  describe "find_by_meta/3" do
    test "finds sessions matching metadata" do
      state = %{
        sessions: %{
          "a" => %{meta: %{pr_number: 123}},
          "b" => %{meta: %{pr_number: 456}},
          "c" => %{meta: %{pr_number: 123}}
        }
      }

      result = SessionRegistry.find_by_meta(state, :pr_number, 123)

      assert map_size(result) == 2
      assert Map.has_key?(result, "a")
      assert Map.has_key?(result, "c")
    end
  end
end
