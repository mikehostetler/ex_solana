defmodule JidoFlame.DirectiveTest do
  use ExUnit.Case, async: true

  alias JidoFlame.Directive.{
    RemoteCall,
    RemoteCast,
    PlaceRemoteChild,
    SpawnRemoteAgent,
    StopRemoteAgent
  }

  describe "RemoteCall" do
    test "creates valid directive with required fields" do
      assert {:ok, directive} =
               RemoteCall.new(%{
                 pool: MyPool,
                 fun: fn -> :ok end
               })

      assert directive.pool == MyPool
      assert is_function(directive.fun, 0)
      assert directive.opts == []
    end

    test "creates directive with all optional fields" do
      assert {:ok, directive} =
               RemoteCall.new(%{
                 pool: MyPool,
                 fun: fn -> :ok end,
                 opts: [timeout: 5000],
                 result_type: "my.result",
                 tag: :test
               })

      assert directive.result_type == "my.result"
      assert directive.tag == :test
    end

    test "fails without pool" do
      assert {:error, _} = RemoteCall.new(%{fun: fn -> :ok end})
    end

    test "fails without fun" do
      assert {:error, _} = RemoteCall.new(%{pool: MyPool})
    end

    test "new!/1 raises on invalid input" do
      assert_raise JidoFlame.Error.InvalidInputError, fn ->
        RemoteCall.new!(%{})
      end
    end
  end

  describe "RemoteCast" do
    test "creates valid directive" do
      assert {:ok, directive} =
               RemoteCast.new(%{
                 pool: MyPool,
                 fun: fn -> :ok end
               })

      assert directive.pool == MyPool
    end

    test "creates directive with optional fields" do
      assert {:ok, directive} =
               RemoteCast.new(%{
                 pool: MyPool,
                 fun: fn -> :ok end,
                 opts: [timeout: 5000],
                 tag: :batch_1
               })

      assert directive.tag == :batch_1
      assert directive.opts == [timeout: 5000]
    end

    test "fails without pool" do
      assert {:error, _} = RemoteCast.new(%{fun: fn -> :ok end})
    end

    test "fails without fun" do
      assert {:error, _} = RemoteCast.new(%{pool: MyPool})
    end

    test "new!/1 raises on invalid input" do
      assert_raise JidoFlame.Error.InvalidInputError, fn ->
        RemoteCast.new!(%{})
      end
    end
  end

  describe "PlaceRemoteChild" do
    test "creates valid directive" do
      child_spec = {MyWorker, []}

      assert {:ok, directive} =
               PlaceRemoteChild.new(%{
                 pool: MyPool,
                 child_spec: child_spec
               })

      assert directive.child_spec == child_spec
      assert directive.track? == false
    end

    test "supports track? option" do
      assert {:ok, directive} =
               PlaceRemoteChild.new(%{
                 pool: MyPool,
                 child_spec: {MyWorker, []},
                 track?: true
               })

      assert directive.track? == true
    end

    test "supports tag option" do
      assert {:ok, directive} =
               PlaceRemoteChild.new(%{
                 pool: MyPool,
                 child_spec: {MyWorker, []},
                 tag: :worker_1
               })

      assert directive.tag == :worker_1
    end

    test "fails without pool" do
      assert {:error, _} = PlaceRemoteChild.new(%{child_spec: {MyWorker, []}})
    end

    test "fails without child_spec" do
      assert {:error, _} = PlaceRemoteChild.new(%{pool: MyPool})
    end

    test "new!/1 raises on invalid input" do
      assert_raise JidoFlame.Error.InvalidInputError, fn ->
        PlaceRemoteChild.new!(%{})
      end
    end
  end

  describe "SpawnRemoteAgent" do
    test "creates valid directive with required fields" do
      assert {:ok, directive} =
               SpawnRemoteAgent.new(%{
                 pool: MyPool,
                 agent: MyAgent,
                 tag: :worker_1
               })

      assert directive.pool == MyPool
      assert directive.agent == MyAgent
      assert directive.tag == :worker_1
      assert directive.opts == %{}
      assert directive.meta == %{}
    end

    test "creates directive with all optional fields" do
      assert {:ok, directive} =
               SpawnRemoteAgent.new(%{
                 pool: MyPool,
                 agent: MyAgent,
                 tag: :worker_1,
                 opts: %{initial_state: %{}},
                 meta: %{purpose: "testing"},
                 jido: MyApp.Jido,
                 flame_opts: [timeout: 60_000]
               })

      assert directive.opts == %{initial_state: %{}}
      assert directive.meta == %{purpose: "testing"}
      assert directive.jido == MyApp.Jido
    end

    test "fails without pool" do
      assert {:error, _} = SpawnRemoteAgent.new(%{agent: MyAgent, tag: :worker})
    end

    test "fails without agent" do
      assert {:error, _} = SpawnRemoteAgent.new(%{pool: MyPool, tag: :worker})
    end

    test "fails without tag" do
      assert {:error, _} = SpawnRemoteAgent.new(%{pool: MyPool, agent: MyAgent})
    end

    test "new!/1 raises on invalid input" do
      assert_raise JidoFlame.Error.InvalidInputError, fn ->
        SpawnRemoteAgent.new!(%{})
      end
    end
  end

  describe "StopRemoteAgent" do
    test "creates valid directive" do
      assert {:ok, directive} = StopRemoteAgent.new(%{tag: :worker_1})

      assert directive.tag == :worker_1
      assert directive.reason == :normal
    end

    test "supports custom reason" do
      assert {:ok, directive} =
               StopRemoteAgent.new(%{
                 tag: :worker_1,
                 reason: :shutdown
               })

      assert directive.reason == :shutdown
    end

    test "fails without tag" do
      assert {:error, _} = StopRemoteAgent.new(%{})
    end

    test "new!/1 raises on invalid input" do
      assert_raise JidoFlame.Error.InvalidInputError, fn ->
        StopRemoteAgent.new!(%{})
      end
    end
  end
end
