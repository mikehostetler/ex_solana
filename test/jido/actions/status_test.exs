defmodule JidoTest.Actions.StatusTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.Status

  describe "SetStatus" do
    test "sets status field" do
      {:ok, result} = Status.SetStatus.run(%{status: :working}, %{})
      assert result == %{status: :working}
    end

    test "accepts any atom status" do
      {:ok, result} = Status.SetStatus.run(%{status: :custom_status}, %{})
      assert result == %{status: :custom_status}
    end
  end

  describe "MarkCompleted" do
    test "sets status to completed" do
      {:ok, result} = Status.MarkCompleted.run(%{result: nil}, %{})
      assert result == %{status: :completed}
    end

    test "includes last_answer when result provided" do
      {:ok, result} = Status.MarkCompleted.run(%{result: "Answer: 42"}, %{})
      assert result == %{status: :completed, last_answer: "Answer: 42"}
    end

    test "handles complex result values" do
      {:ok, result} = Status.MarkCompleted.run(%{result: %{data: [1, 2, 3]}}, %{})
      assert result == %{status: :completed, last_answer: %{data: [1, 2, 3]}}
    end
  end

  describe "MarkFailed" do
    test "sets status to failed with default reason" do
      {:ok, result} = Status.MarkFailed.run(%{reason: :unknown_error}, %{})
      assert result == %{status: :failed, error: :unknown_error}
    end

    test "includes custom error reason" do
      {:ok, result} = Status.MarkFailed.run(%{reason: :timeout}, %{})
      assert result == %{status: :failed, error: :timeout}
    end

    test "handles tuple error reasons" do
      {:ok, result} = Status.MarkFailed.run(%{reason: {:validation, "bad input"}}, %{})
      assert result == %{status: :failed, error: {:validation, "bad input"}}
    end
  end

  describe "MarkWorking" do
    test "sets status to working" do
      {:ok, result} = Status.MarkWorking.run(%{task_id: nil}, %{})
      assert result == %{status: :working}
    end

    test "includes current_task when task_id provided" do
      {:ok, result} = Status.MarkWorking.run(%{task_id: "task-123"}, %{})
      assert result == %{status: :working, current_task: "task-123"}
    end
  end

  describe "MarkIdle" do
    test "sets status to idle" do
      {:ok, result} = Status.MarkIdle.run(%{}, %{})
      assert result == %{status: :idle}
    end
  end
end
