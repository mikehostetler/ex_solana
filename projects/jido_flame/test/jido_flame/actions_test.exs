defmodule JidoFlame.ActionsTest do
  use ExUnit.Case, async: true

  alias JidoFlame.Actions.{RemoteCall, RemoteCast, SpawnRemoteAgent, StopRemoteAgent}
  alias JidoFlame.Directive

  describe "RemoteCall action" do
    test "returns directive with function" do
      params = %{
        pool: MyPool,
        fun: fn -> :result end,
        result_type: "test.result"
      }

      assert {:ok, result, [directive]} = RemoteCall.run(params, %{})
      assert result.directive_type == :remote_call
      assert %Directive.RemoteCall{} = directive
      assert directive.pool == MyPool
    end

    test "returns directive with MFA" do
      params = %{
        pool: MyPool,
        mfa: %{module: String, function: :upcase, args: ["hello"]},
        result_type: "test.result"
      }

      assert {:ok, _result, [directive]} = RemoteCall.run(params, %{})
      assert %Directive.RemoteCall{} = directive
      assert is_function(directive.fun, 0)
      assert directive.fun.() == "HELLO"
    end

    test "returns directive with MFA without args" do
      params = %{
        pool: MyPool,
        mfa: %{module: Node, function: :self},
        result_type: "test.result"
      }

      assert {:ok, _result, [directive]} = RemoteCall.run(params, %{})
      assert is_function(directive.fun, 0)
    end

    test "includes optional fields in directive" do
      params = %{
        pool: MyPool,
        fun: fn -> :ok end,
        result_type: "test.completed",
        tag: :test_call
      }

      assert {:ok, _result, [directive]} = RemoteCall.run(params, %{})
      assert directive.result_type == "test.completed"
      assert directive.tag == :test_call
    end

    test "includes timeout in opts" do
      params = %{
        pool: MyPool,
        fun: fn -> :ok end,
        timeout: 60_000,
        result_type: "test.result"
      }

      assert {:ok, _result, [directive]} = RemoteCall.run(params, %{})
      assert Keyword.get(directive.opts, :timeout) == 60_000
    end
  end

  describe "RemoteCast action" do
    test "returns directive" do
      params = %{
        pool: MyPool,
        fun: fn -> :ok end
      }

      assert {:ok, result, [directive]} = RemoteCast.run(params, %{})
      assert result.directive_type == :remote_cast
      assert %Directive.RemoteCast{} = directive
      assert directive.pool == MyPool
    end

    test "includes optional tag" do
      params = %{
        pool: MyPool,
        fun: fn -> :ok end,
        tag: :batch_1
      }

      assert {:ok, _result, [directive]} = RemoteCast.run(params, %{})
      assert directive.tag == :batch_1
    end

    test "includes opts" do
      params = %{
        pool: MyPool,
        fun: fn -> :ok end,
        opts: [timeout: 5000]
      }

      assert {:ok, _result, [directive]} = RemoteCast.run(params, %{})
      assert directive.opts == [timeout: 5000]
    end
  end

  describe "SpawnRemoteAgent action" do
    test "returns directive" do
      params = %{
        pool: MyPool,
        agent: MyAgent,
        tag: :worker_1
      }

      assert {:ok, result, [directive]} = SpawnRemoteAgent.run(params, %{})
      assert result.directive_type == :spawn_remote_agent
      assert result.tag == :worker_1
      assert result.agent == MyAgent
      assert result.pool == MyPool
      assert %Directive.SpawnRemoteAgent{} = directive
    end

    test "includes optional fields" do
      params = %{
        pool: MyPool,
        agent: MyAgent,
        tag: :worker_1,
        opts: %{initial_state: %{foo: :bar}},
        meta: %{purpose: "testing"},
        jido: MyApp.Jido,
        flame_opts: [timeout: 60_000]
      }

      assert {:ok, _result, [directive]} = SpawnRemoteAgent.run(params, %{})
      assert directive.opts == %{initial_state: %{foo: :bar}}
      assert directive.meta == %{purpose: "testing"}
      assert directive.jido == MyApp.Jido
      assert directive.flame_opts == [timeout: 60_000]
    end
  end

  describe "StopRemoteAgent action" do
    test "returns directive" do
      params = %{tag: :worker_1}

      assert {:ok, result, [directive]} = StopRemoteAgent.run(params, %{})
      assert result.directive_type == :stop_remote_agent
      assert result.tag == :worker_1
      assert %Directive.StopRemoteAgent{} = directive
    end

    test "includes custom reason" do
      params = %{tag: :worker_1, reason: :shutdown}

      assert {:ok, _result, [directive]} = StopRemoteAgent.run(params, %{})
      assert directive.reason == :shutdown
    end

    test "defaults to :normal reason" do
      params = %{tag: :worker_1}

      assert {:ok, _result, [directive]} = StopRemoteAgent.run(params, %{})
      assert directive.reason == :normal
    end
  end
end
