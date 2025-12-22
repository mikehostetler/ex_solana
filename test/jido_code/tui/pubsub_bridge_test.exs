defmodule JidoCode.TUI.PubSubBridgeTest do
  use ExUnit.Case, async: false

  alias JidoCode.TUI.PubSubBridge

  setup do
    # Create a test runtime that receives messages
    test_pid = self()

    # Use a mock runtime that forwards messages to test process
    mock_runtime =
      spawn_link(fn ->
        receive_loop(test_pid)
      end)

    {:ok, bridge} = PubSubBridge.start_link(runtime: mock_runtime)

    on_exit(fn ->
      if Process.alive?(bridge), do: PubSubBridge.stop(bridge)
    end)

    {:ok, bridge: bridge, test_pid: test_pid}
  end

  defp receive_loop(test_pid) do
    receive do
      {:"$gen_cast", {:message, component_id, message}} ->
        send(test_pid, {:forwarded, component_id, message})
        receive_loop(test_pid)

      _ ->
        receive_loop(test_pid)
    end
  end

  describe "PubSubBridge message forwarding" do
    test "forwards {:agent_response, content} to runtime", %{bridge: _bridge} do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:agent_response, "Hello!"})

      assert_receive {:forwarded, :root, {:agent_response, "Hello!"}}, 1000
    end

    test "forwards {:agent_status, status} to runtime", %{bridge: _bridge} do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:agent_status, :processing})

      assert_receive {:forwarded, :root, {:agent_status, :processing}}, 1000
    end

    test "forwards {:reasoning_step, step} to runtime", %{bridge: _bridge} do
      step = %{step: "Analyzing query", status: :active}
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:reasoning_step, step})

      assert_receive {:forwarded, :root, {:reasoning_step, ^step}}, 1000
    end

    test "forwards {:config_changed, config} to runtime", %{bridge: _bridge} do
      config = %{provider: "anthropic", model: "claude-3-5-haiku-20241022"}
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:config_changed, config})

      assert_receive {:forwarded, :root, {:config_changed, ^config}}, 1000
    end

    test "ignores unknown messages", %{bridge: _bridge} do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:unknown_msg, "data"})

      refute_receive {:forwarded, _, _}, 100
    end
  end
end
