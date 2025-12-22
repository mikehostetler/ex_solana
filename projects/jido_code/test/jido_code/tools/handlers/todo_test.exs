defmodule JidoCode.Tools.Handlers.TodoTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session.State, as: SessionState
  alias JidoCode.Tools.Handlers.Todo

  @moduletag :tmp_dir

  setup do
    # Ensure application is started (PubSub and other infrastructure)
    Application.ensure_all_started(:jido_code)

    # Subscribe to PubSub to verify broadcasts
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")
    :ok
  end

  # ============================================================================
  # Session State Integration Tests
  # ============================================================================

  describe "session-aware context" do
    setup %{tmp_dir: tmp_dir} do
      # Set dummy API key for test
      System.put_env("ANTHROPIC_API_KEY", "test-key-todo-handler")

      on_exit(fn ->
        System.delete_env("ANTHROPIC_API_KEY")
      end)

      # Start required registries if not already started
      unless Process.whereis(JidoCode.SessionProcessRegistry) do
        start_supervised!({Registry, keys: :unique, name: JidoCode.SessionProcessRegistry})
      end

      # Create a session
      {:ok, session} = JidoCode.Session.new(project_path: tmp_dir, name: "todo-session-test")

      {:ok, supervisor_pid} =
        JidoCode.Session.Supervisor.start_link(
          session: session,
          name: {:via, Registry, {JidoCode.Registry, {:todo_session_test_sup, session.id}}}
        )

      on_exit(fn ->
        try do
          if Process.alive?(supervisor_pid), do: Supervisor.stop(supervisor_pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      %{session: session}
    end

    test "stores todos in Session.State when session_id provided", %{session: session} do
      todos = [
        %{"content" => "Task 1", "status" => "pending", "active_form" => "Task 1"},
        %{"content" => "Task 2", "status" => "in_progress", "active_form" => "Task 2"}
      ]

      context = %{session_id: session.id}
      assert {:ok, _message} = Todo.execute(%{"todos" => todos}, context)

      # Verify todos stored in Session.State
      {:ok, stored_todos} = SessionState.get_todos(session.id)
      assert length(stored_todos) == 2
      assert Enum.any?(stored_todos, &(&1.content == "Task 1"))
      assert Enum.any?(stored_todos, &(&1.status == :in_progress))
    end

    test "todos can be retrieved via Session.State.get_todos", %{session: session} do
      todos = [
        %{"content" => "Retrieve me", "status" => "completed", "active_form" => "Retrieving"}
      ]

      context = %{session_id: session.id}
      assert {:ok, _} = Todo.execute(%{"todos" => todos}, context)

      # Retrieve and verify
      {:ok, retrieved} = SessionState.get_todos(session.id)
      assert length(retrieved) == 1
      assert hd(retrieved).content == "Retrieve me"
      assert hd(retrieved).status == :completed
    end

    test "updating todos replaces previous list", %{session: session} do
      context = %{session_id: session.id}

      # First update
      todos1 = [%{"content" => "First", "status" => "pending", "active_form" => "First"}]
      assert {:ok, _} = Todo.execute(%{"todos" => todos1}, context)

      {:ok, stored1} = SessionState.get_todos(session.id)
      assert length(stored1) == 1
      assert hd(stored1).content == "First"

      # Second update replaces
      todos2 = [
        %{"content" => "Second A", "status" => "pending", "active_form" => "Second A"},
        %{"content" => "Second B", "status" => "completed", "active_form" => "Second B"}
      ]

      assert {:ok, _} = Todo.execute(%{"todos" => todos2}, context)

      {:ok, stored2} = SessionState.get_todos(session.id)
      assert length(stored2) == 2
      refute Enum.any?(stored2, &(&1.content == "First"))
    end

    test "gracefully handles non-existent session_id" do
      # Valid UUID format but no session exists
      context = %{session_id: "550e8400-e29b-41d4-a716-446655440000"}

      todos = [%{"content" => "Task", "status" => "pending", "active_form" => "Task"}]

      # Should succeed (logs warning but doesn't fail)
      assert {:ok, _message} = Todo.execute(%{"todos" => todos}, context)
    end

    test "still broadcasts via PubSub with session_id", %{session: session} do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.#{session.id}")

      todos = [
        %{"content" => "Broadcast me", "status" => "pending", "active_form" => "Broadcasting"}
      ]

      context = %{session_id: session.id}

      assert {:ok, _} = Todo.execute(%{"todos" => todos}, context)

      # Should receive on both global and session topics
      assert_receive {:todo_update, _}
      assert_receive {:todo_update, _}
    end
  end

  # ============================================================================
  # Original Tests (backwards compatibility)
  # ============================================================================

  describe "Todo.execute/2" do
    test "creates valid todo list" do
      todos = [
        %{
          "content" => "Implement feature",
          "status" => "in_progress",
          "active_form" => "Implementing feature"
        },
        %{
          "content" => "Write tests",
          "status" => "pending",
          "active_form" => "Writing tests"
        }
      ]

      assert {:ok, message} = Todo.execute(%{"todos" => todos}, %{})
      assert message =~ "in progress"
      assert message =~ "pending"

      # Verify PubSub broadcast
      assert_receive {:todo_update, received_todos}
      assert length(received_todos) == 2
      assert hd(received_todos).status == :in_progress
    end

    test "accepts all valid statuses" do
      todos = [
        %{"content" => "Task 1", "status" => "pending", "active_form" => "Task 1"},
        %{"content" => "Task 2", "status" => "in_progress", "active_form" => "Task 2"},
        %{"content" => "Task 3", "status" => "completed", "active_form" => "Task 3"}
      ]

      assert {:ok, message} = Todo.execute(%{"todos" => todos}, %{})
      assert message =~ "pending"
      assert message =~ "in progress"
      assert message =~ "completed"
    end

    test "handles empty todo list" do
      assert {:ok, message} = Todo.execute(%{"todos" => []}, %{})
      assert message =~ "cleared"
    end

    test "broadcasts to session-specific topic" do
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events.test_session")

      todos = [
        %{"content" => "Task", "status" => "pending", "active_form" => "Task"}
      ]

      context = %{session_id: "test_session"}
      assert {:ok, _} = Todo.execute(%{"todos" => todos}, context)

      # Should receive on both global and session topics
      assert_receive {:todo_update, _}
      assert_receive {:todo_update, _}
    end

    test "converts status to atom" do
      todos = [
        %{"content" => "Task", "status" => "in_progress", "active_form" => "Task"}
      ]

      assert {:ok, _} = Todo.execute(%{"todos" => todos}, %{})
      assert_receive {:todo_update, [%{status: :in_progress}]}
    end

    test "returns error for missing content" do
      todos = [
        %{"status" => "pending", "active_form" => "Task"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "content"
    end

    test "returns error for empty content" do
      todos = [
        %{"content" => "", "status" => "pending", "active_form" => "Task"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "content"
    end

    test "returns error for invalid status" do
      todos = [
        %{"content" => "Task", "status" => "invalid", "active_form" => "Task"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "status"
    end

    test "returns error for missing status" do
      todos = [
        %{"content" => "Task", "active_form" => "Task"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "status"
    end

    test "returns error for missing active_form" do
      todos = [
        %{"content" => "Task", "status" => "pending"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "active_form"
    end

    test "returns error for empty active_form" do
      todos = [
        %{"content" => "Task", "status" => "pending", "active_form" => ""}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "active_form"
    end

    test "returns error for non-map todo" do
      todos = ["just a string"]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "must be a map"
    end

    test "returns error for missing todos argument" do
      assert {:error, error} = Todo.execute(%{}, %{})
      assert error =~ "requires a todos array"
    end

    test "returns error if any todo is invalid" do
      todos = [
        %{"content" => "Valid", "status" => "pending", "active_form" => "Valid"},
        %{"content" => "Invalid", "status" => "bad_status", "active_form" => "Invalid"}
      ]

      assert {:error, error} = Todo.execute(%{"todos" => todos}, %{})
      assert error =~ "status"
    end

    test "formats success message correctly for single items" do
      todos = [
        %{"content" => "Task", "status" => "in_progress", "active_form" => "Task"}
      ]

      assert {:ok, message} = Todo.execute(%{"todos" => todos}, %{})
      assert message =~ "1 in progress"
    end

    test "formats success message correctly for multiple items" do
      todos = [
        %{"content" => "Task 1", "status" => "pending", "active_form" => "Task 1"},
        %{"content" => "Task 2", "status" => "pending", "active_form" => "Task 2"},
        %{"content" => "Task 3", "status" => "pending", "active_form" => "Task 3"}
      ]

      assert {:ok, message} = Todo.execute(%{"todos" => todos}, %{})
      assert message =~ "3 pending"
    end
  end
end
