defmodule Jido.Signal.Journal.CheckpointTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Journal.Adapters.ETS
  alias Jido.Signal.Journal.Adapters.InMemory

  describe "ETS adapter checkpoint operations" do
    setup do
      {:ok, pid} = ETS.init()

      on_exit(fn ->
        if Process.alive?(pid), do: ETS.cleanup(pid)
      end)

      {:ok, pid: pid}
    end

    test "put_checkpoint/3 and get_checkpoint/2 round-trip", %{pid: pid} do
      subscription_id = "sub_123"
      checkpoint = 42

      assert :ok = ETS.put_checkpoint(subscription_id, checkpoint, pid)
      assert {:ok, ^checkpoint} = ETS.get_checkpoint(subscription_id, pid)
    end

    test "get_checkpoint/2 returns {:error, :not_found} for missing", %{pid: pid} do
      assert {:error, :not_found} = ETS.get_checkpoint("nonexistent", pid)
    end

    test "delete_checkpoint/2 removes the checkpoint", %{pid: pid} do
      subscription_id = "sub_to_delete"
      checkpoint = 100

      assert :ok = ETS.put_checkpoint(subscription_id, checkpoint, pid)
      assert {:ok, ^checkpoint} = ETS.get_checkpoint(subscription_id, pid)

      assert :ok = ETS.delete_checkpoint(subscription_id, pid)
      assert {:error, :not_found} = ETS.get_checkpoint(subscription_id, pid)
    end

    test "put_checkpoint/3 overwrites existing checkpoint", %{pid: pid} do
      subscription_id = "sub_overwrite"

      assert :ok = ETS.put_checkpoint(subscription_id, 10, pid)
      assert {:ok, 10} = ETS.get_checkpoint(subscription_id, pid)

      assert :ok = ETS.put_checkpoint(subscription_id, 20, pid)
      assert {:ok, 20} = ETS.get_checkpoint(subscription_id, pid)
    end

    test "multiple subscriptions maintain separate checkpoints", %{pid: pid} do
      assert :ok = ETS.put_checkpoint("sub_a", 100, pid)
      assert :ok = ETS.put_checkpoint("sub_b", 200, pid)
      assert :ok = ETS.put_checkpoint("sub_c", 300, pid)

      assert {:ok, 100} = ETS.get_checkpoint("sub_a", pid)
      assert {:ok, 200} = ETS.get_checkpoint("sub_b", pid)
      assert {:ok, 300} = ETS.get_checkpoint("sub_c", pid)
    end
  end

  describe "InMemory adapter checkpoint operations" do
    setup do
      {:ok, pid} = InMemory.init()
      {:ok, pid: pid}
    end

    test "put_checkpoint/3 and get_checkpoint/2 round-trip", %{pid: pid} do
      subscription_id = "sub_123"
      checkpoint = 42

      assert :ok = InMemory.put_checkpoint(subscription_id, checkpoint, pid)
      assert {:ok, ^checkpoint} = InMemory.get_checkpoint(subscription_id, pid)
    end

    test "get_checkpoint/2 returns {:error, :not_found} for missing", %{pid: pid} do
      assert {:error, :not_found} = InMemory.get_checkpoint("nonexistent", pid)
    end

    test "delete_checkpoint/2 removes the checkpoint", %{pid: pid} do
      subscription_id = "sub_to_delete"
      checkpoint = 100

      assert :ok = InMemory.put_checkpoint(subscription_id, checkpoint, pid)
      assert {:ok, ^checkpoint} = InMemory.get_checkpoint(subscription_id, pid)

      assert :ok = InMemory.delete_checkpoint(subscription_id, pid)
      assert {:error, :not_found} = InMemory.get_checkpoint(subscription_id, pid)
    end

    test "put_checkpoint/3 overwrites existing checkpoint", %{pid: pid} do
      subscription_id = "sub_overwrite"

      assert :ok = InMemory.put_checkpoint(subscription_id, 10, pid)
      assert {:ok, 10} = InMemory.get_checkpoint(subscription_id, pid)

      assert :ok = InMemory.put_checkpoint(subscription_id, 20, pid)
      assert {:ok, 20} = InMemory.get_checkpoint(subscription_id, pid)
    end

    test "multiple subscriptions maintain separate checkpoints", %{pid: pid} do
      assert :ok = InMemory.put_checkpoint("sub_a", 100, pid)
      assert :ok = InMemory.put_checkpoint("sub_b", 200, pid)
      assert :ok = InMemory.put_checkpoint("sub_c", 300, pid)

      assert {:ok, 100} = InMemory.get_checkpoint("sub_a", pid)
      assert {:ok, 200} = InMemory.get_checkpoint("sub_b", pid)
      assert {:ok, 300} = InMemory.get_checkpoint("sub_c", pid)
    end
  end
end
