defmodule JidoCode.PubSubHelpersTest do
  use ExUnit.Case, async: true

  alias JidoCode.PubSubHelpers

  describe "session_topic/1" do
    test "returns global topic for nil session_id" do
      assert PubSubHelpers.session_topic(nil) == "tui.events"
    end

    test "returns session-specific topic for session_id" do
      assert PubSubHelpers.session_topic("abc-123") == "tui.events.abc-123"
    end

    test "returns session-specific topic for UUID" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert PubSubHelpers.session_topic(uuid) == "tui.events.#{uuid}"
    end
  end

  describe "global_topic/0" do
    test "returns the global topic" do
      assert PubSubHelpers.global_topic() == "tui.events"
    end
  end

  describe "broadcast/2" do
    test "broadcasts to global topic when session_id is nil" do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      :ok = PubSubHelpers.broadcast(nil, {:test_event, :data})

      assert_receive {:test_event, :data}, 1000
    end

    test "broadcasts to BOTH session and global topics when session_id provided" do
      session_id = "test-session-#{:rand.uniform(100_000)}"

      # Subscribe to both topics
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.#{session_id}")
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      :ok = PubSubHelpers.broadcast(session_id, {:dual_event, :payload})

      # Should receive on session topic
      assert_receive {:dual_event, :payload}, 1000
      # Should also receive on global topic
      assert_receive {:dual_event, :payload}, 1000
    end

    test "does not broadcast to session topic when session_id is nil" do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.nil")
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      :ok = PubSubHelpers.broadcast(nil, {:nil_test, :data})

      # Should receive on global
      assert_receive {:nil_test, :data}, 1000
      # Should NOT receive on "tui.events.nil"
      refute_receive {:nil_test, :data}, 100
    end
  end
end
