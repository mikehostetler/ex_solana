defmodule JidoClaude.SignalsTest do
  use ExUnit.Case, async: true

  alias JidoClaude.Signals

  describe "session_started/1" do
    test "builds signal with session_id and model" do
      signal = Signals.session_started(%{session_id: "test-123", model: "sonnet"})

      assert signal.type == "claude.session.started"
      assert signal.data.session_id == "test-123"
      assert signal.data.model == "sonnet"
      assert signal.source == "/claude"
    end
  end

  describe "assistant_text/2" do
    test "builds signal with session_id and text" do
      signal = Signals.assistant_text("test-123", %{text: "Hello, world!"})

      assert signal.type == "claude.turn.text"
      assert signal.data.session_id == "test-123"
      assert signal.data.text == "Hello, world!"
    end
  end

  describe "tool_use/2" do
    test "builds signal with session_id, tool name and input" do
      signal = Signals.tool_use("test-123", %{name: "Read", input: %{path: "/tmp/file.txt"}})

      assert signal.type == "claude.turn.tool_use"
      assert signal.data.session_id == "test-123"
      assert signal.data.tool == "Read"
      assert signal.data.input == %{path: "/tmp/file.txt"}
    end
  end

  describe "session_success/1" do
    test "builds signal with result and cost" do
      signal =
        Signals.session_success(%{
          session_id: "test-123",
          result: "Analysis complete",
          num_turns: 5,
          total_cost_usd: 0.0234,
          duration_ms: 15000
        })

      assert signal.type == "claude.session.success"
      assert signal.data.session_id == "test-123"
      assert signal.data.result == "Analysis complete"
      assert signal.data.turns == 5
      assert signal.data.cost_usd == 0.0234
      assert signal.data.duration_ms == 15000
    end
  end

  describe "session_error/3" do
    test "builds signal with error type and details" do
      signal =
        Signals.session_error("test-123", :error_timeout, %{
          message: "Session timed out"
        })

      assert signal.type == "claude.session.error"
      assert signal.data.session_id == "test-123"
      assert signal.data.error_type == :error_timeout
      assert signal.data.details.message == "Session timed out"
    end
  end
end
