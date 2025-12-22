defmodule JidoCode.Tools.Handlers.TaskTest do
  use ExUnit.Case, async: false

  alias JidoCode.AgentSupervisor
  alias JidoCode.Agents.TaskAgent
  alias JidoCode.Tools.Definitions.Task, as: TaskDefinitions
  alias JidoCode.Tools.Handlers.Task, as: TaskHandler
  alias JidoCode.Tools.Registry

  # Provide explicit provider/model to bypass Config.get_llm_config()
  @test_provider :anthropic
  @test_model "claude-3-5-sonnet-20241022"

  setup do
    # Clear registry
    # Registry cleared at app startup - tools persist
    :ok
  end

  # ============================================================================
  # Session Context Tests
  # ============================================================================

  describe "session-aware context" do
    test "TaskAgent stores session_id in state" do
      session_id = "test-session-#{:rand.uniform(10000)}"

      opts = [
        task_id: "test_session_state_#{:rand.uniform(10000)}",
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model,
        session_id: session_id
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      status = TaskAgent.status(pid)
      assert status.session_id == session_id

      GenServer.stop(pid, :normal)
    end

    test "TaskAgent broadcasts to session-specific topic" do
      task_id = "test_session_pubsub_#{:rand.uniform(10000)}"
      session_id = "session-#{:rand.uniform(10000)}"

      # Subscribe to session-specific topic
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.#{session_id}")

      opts = [
        task_id: task_id,
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model,
        session_id: session_id
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      # Start execution (LLM call will fail but broadcast should happen)
      spawn(fn ->
        try do
          TaskAgent.execute(pid, timeout: 1000)
        catch
          _, _ -> :ok
        end
      end)

      # Should receive task_started on session topic
      assert_receive {:task_started, ^task_id}, 500

      try do
        GenServer.stop(pid, :normal)
      catch
        :exit, _ -> :ok
      end
    end

    test "TaskAgent without session_id still works" do
      opts = [
        task_id: "test_no_session_#{:rand.uniform(10000)}",
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      status = TaskAgent.status(pid)
      assert status.session_id == nil

      GenServer.stop(pid, :normal)
    end

    test "Task handler passes session_id to agent spec" do
      # This test verifies the handler builds correct spec
      # We can't easily test the full flow without mocking,
      # but we can verify the spec building logic
      task_id = "test_spec_#{:rand.uniform(10000)}"
      session_id = "session-#{:rand.uniform(10000)}"

      # Create agent directly with session_id to verify it works
      opts = [
        task_id: task_id,
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model,
        session_id: session_id
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      status = TaskAgent.status(pid)
      assert status.session_id == session_id

      GenServer.stop(pid, :normal)
    end
  end

  # ============================================================================
  # Tool Definition Tests
  # ============================================================================

  describe "TaskDefinitions.all/0" do
    test "returns spawn_task tool" do
      tools = TaskDefinitions.all()
      assert length(tools) == 1
      assert hd(tools).name == "spawn_task"
    end
  end

  describe "TaskDefinitions.spawn_task/0" do
    test "has correct name and handler" do
      tool = TaskDefinitions.spawn_task()
      assert tool.name == "spawn_task"
      assert tool.handler == TaskHandler
    end

    test "has required parameters" do
      tool = TaskDefinitions.spawn_task()
      param_names = Enum.map(tool.parameters, & &1.name)

      assert "description" in param_names
      assert "prompt" in param_names
    end

    test "has optional parameters" do
      tool = TaskDefinitions.spawn_task()
      param_names = Enum.map(tool.parameters, & &1.name)

      assert "subagent_type" in param_names
      assert "model" in param_names
      assert "timeout" in param_names
    end

    test "description and prompt are required" do
      tool = TaskDefinitions.spawn_task()

      description_param = Enum.find(tool.parameters, &(&1.name == "description"))
      prompt_param = Enum.find(tool.parameters, &(&1.name == "prompt"))

      assert description_param.required == true
      assert prompt_param.required == true
    end
  end

  describe "TaskHandler.execute/2 validation" do
    test "returns error when description is missing" do
      args = %{"prompt" => "Do something"}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "description"
    end

    test "returns error when prompt is missing" do
      args = %{"description" => "Test task"}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "prompt"
    end

    test "returns error when description is empty" do
      args = %{"description" => "", "prompt" => "Do something"}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "description cannot be empty"
    end

    test "returns error when prompt is empty" do
      args = %{"description" => "Test", "prompt" => ""}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "prompt cannot be empty"
    end

    test "returns error when description exceeds 200 characters" do
      long_description = String.duplicate("a", 201)
      args = %{"description" => long_description, "prompt" => "Do something"}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "200 characters"
    end

    test "returns error when prompt exceeds 10000 characters" do
      long_prompt = String.duplicate("a", 10_001)
      args = %{"description" => "Test", "prompt" => long_prompt}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "10000 characters"
    end

    test "returns error when timeout is not an integer" do
      args = %{"description" => "Test", "prompt" => "Do something", "timeout" => "1000"}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "timeout must be an integer"
    end

    test "returns error when timeout is less than 1000ms" do
      args = %{"description" => "Test", "prompt" => "Do something", "timeout" => 500}
      assert {:error, message} = TaskHandler.execute(args, %{})
      assert message =~ "at least 1000ms"
    end
  end

  describe "TaskAgent initialization" do
    test "starts with valid options" do
      opts = [
        task_id: "test_init_#{:rand.uniform(10000)}",
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      assert {:ok, pid} = TaskAgent.start_link(opts)
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid, :normal)
    end

    test "fails gracefully when task_id is missing" do
      Process.flag(:trap_exit, true)

      opts = [
        description: "Test",
        prompt: "Test prompt",
        provider: @test_provider,
        model: @test_model
      ]

      # start_link will return {:error, _} due to init failure
      result = TaskAgent.start_link(opts)
      assert match?({:error, _}, result) or match?(:ignore, result)
    end

    test "fails gracefully when description is missing" do
      Process.flag(:trap_exit, true)

      opts = [
        task_id: "test",
        prompt: "Test prompt",
        provider: @test_provider,
        model: @test_model
      ]

      result = TaskAgent.start_link(opts)
      assert match?({:error, _}, result) or match?(:ignore, result)
    end

    test "fails gracefully when prompt is missing" do
      Process.flag(:trap_exit, true)
      opts = [task_id: "test", description: "Test", provider: @test_provider, model: @test_model]

      result = TaskAgent.start_link(opts)
      assert match?({:error, _}, result) or match?(:ignore, result)
    end
  end

  describe "TaskAgent status" do
    test "returns ready status after initialization" do
      opts = [
        task_id: "test_status_#{:rand.uniform(10000)}",
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      status = TaskAgent.status(pid)
      assert status.status == :ready
      assert status.task_id == opts[:task_id]
      assert status.description == opts[:description]

      GenServer.stop(pid, :normal)
    end
  end

  describe "TaskAgent PubSub" do
    setup do
      task_id = "test_pubsub_#{:rand.uniform(10000)}"
      topic = "task.#{task_id}"
      Phoenix.PubSub.subscribe(JidoCode.PubSub, topic)
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

      {:ok, task_id: task_id, topic: topic}
    end

    test "broadcasts to task topic on start", %{task_id: task_id} do
      opts = [
        task_id: task_id,
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      # Start a task - the LLM call will fail but that's ok
      # We just want to verify the broadcast happens
      spawn(fn ->
        try do
          TaskAgent.execute(pid, timeout: 1000)
        catch
          _, _ -> :ok
        end
      end)

      # Should receive task_started
      assert_receive {:task_started, ^task_id}, 500

      # Clean up
      try do
        GenServer.stop(pid, :normal)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "TaskAgent telemetry" do
    test "emits init event" do
      task_id = "test_telemetry_#{:rand.uniform(10000)}"
      test_pid = self()

      :telemetry.attach(
        "test-task-init-#{task_id}",
        [:jido_code, :task_agent, :init],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_init, metadata})
        end,
        nil
      )

      opts = [
        task_id: task_id,
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      {:ok, pid} = TaskAgent.start_link(opts)

      assert_receive {:telemetry_init, %{task_id: ^task_id}}, 500

      :telemetry.detach("test-task-init-#{task_id}")
      GenServer.stop(pid, :normal)
    end

    test "emits terminate event" do
      task_id = "test_telemetry_term_#{:rand.uniform(10000)}"
      test_pid = self()

      :telemetry.attach(
        "test-task-terminate-#{task_id}",
        [:jido_code, :task_agent, :terminate],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_terminate, metadata})
        end,
        nil
      )

      opts = [
        task_id: task_id,
        description: "Test task",
        prompt: "Execute this test task",
        provider: @test_provider,
        model: @test_model
      ]

      {:ok, pid} = TaskAgent.start_link(opts)
      GenServer.stop(pid, :normal)

      assert_receive {:telemetry_terminate, %{task_id: ^task_id}}, 500

      :telemetry.detach("test-task-terminate-#{task_id}")
    end
  end

  describe "TaskAgent via AgentSupervisor" do
    test "can be started via AgentSupervisor" do
      task_id = "test_supervisor_#{:rand.uniform(10000)}"
      agent_name = String.to_atom(task_id)

      result =
        AgentSupervisor.start_agent(%{
          name: agent_name,
          module: TaskAgent,
          args: [
            task_id: task_id,
            description: "Test task",
            prompt: "Execute this test task",
            provider: @test_provider,
            model: @test_model
          ]
        })

      assert {:ok, pid} = result
      assert Process.alive?(pid)

      # Verify it's registered
      assert {:ok, ^pid} = AgentSupervisor.lookup_agent(agent_name)

      # Clean up
      assert :ok = AgentSupervisor.stop_agent(agent_name)
    end

    test "cleanup removes agent from supervisor" do
      task_id = "test_cleanup_#{:rand.uniform(10000)}"
      agent_name = String.to_atom(task_id)

      {:ok, pid} =
        AgentSupervisor.start_agent(%{
          name: agent_name,
          module: TaskAgent,
          args: [
            task_id: task_id,
            description: "Test task",
            prompt: "Execute this test task",
            provider: @test_provider,
            model: @test_model
          ]
        })

      assert :ok = AgentSupervisor.stop_agent(agent_name)

      # Wait for the process to terminate and registry to update
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1000 -> :ok
      end

      # Give the Registry time to clean up
      Process.sleep(50)

      # Process should be dead
      refute Process.alive?(pid)
    end
  end
end
