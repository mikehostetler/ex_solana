defmodule JidoCode.TestHelpers.ManagerIsolation do
  @moduledoc """
  Test helper for isolating Manager state during tests.

  The Manager GenServer maintains the project_root for sandboxed operations.
  Tests that use temporary directories need to restart the Manager with the
  correct project_root for the test.

  ## Usage

      setup %{tmp_dir: tmp_dir} do
        JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
      end

  Or in a describe block:

      describe "file operations" do
        @describetag :tmp_dir

        setup %{tmp_dir: tmp_dir} do
          JidoCode.TestHelpers.ManagerIsolation.set_project_root(tmp_dir)
        end

        test "reads file", %{tmp_dir: tmp_dir} do
          # Manager now uses tmp_dir as project_root
          File.write!(Path.join(tmp_dir, "test.txt"), "hello")
          assert {:ok, "hello"} = Manager.read_file("test.txt")
        end
      end
  """

  alias JidoCode.Tools.Manager

  @doc """
  Restarts the Manager with a new project_root.

  Saves the original project_root and registers cleanup on exit to restore it.
  Returns :ok.
  """
  @spec set_project_root(String.t()) :: :ok
  def set_project_root(new_project_root) do
    # Ensure we have an absolute path
    new_project_root = Path.expand(new_project_root)

    # Get current project root (or use cwd if Manager isn't running)
    original_root =
      case Process.whereis(Manager) do
        nil -> File.cwd!()
        _pid ->
          {:ok, root} = Manager.project_root()
          root
      end

    # Forcefully stop and restart Manager to ensure clean state
    stop_manager()
    start_manager_with_root(new_project_root)

    # Register cleanup to restore original root
    ExUnit.Callbacks.on_exit(fn ->
      stop_manager()
      start_manager_with_root(original_root)
    end)

    :ok
  end

  defp stop_manager do
    case Process.whereis(Manager) do
      nil -> :ok
      pid when is_pid(pid) ->
        ref = Process.monitor(pid)

        try do
          GenServer.stop(Manager, :normal, 5_000)
        catch
          :exit, _ -> :ok
        end

        # Wait for process to actually terminate
        receive do
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          100 -> :ok
        end
    end
  end

  defp start_manager_with_root(project_root) do
    case Manager.start_link(project_root: project_root, name: Manager) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_started, pid}} ->
        # Process still running despite our stop attempt, kill it
        Process.exit(pid, :kill)
        Process.sleep(50)
        start_manager_with_root(project_root)
    end
  end
end
