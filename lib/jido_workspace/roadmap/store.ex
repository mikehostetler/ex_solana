defmodule JidoWorkspace.Roadmap.Store do
  @moduledoc """
  Persistence layer for roadmap data.

  Key principles:
  1. JSON files are the source of truth (git-tracked)
  2. All mutations go through this module (never edit JSON directly)
  3. Keys are always sorted for stable diffs
  4. All data is validated via Zoi schemas before save

  ## Usage

      # Load a task
      {:ok, task} = Store.load_task("jido-ecosystem/foundation-layer/...")

      # Save a task (validates and sorts keys)
      :ok = Store.save_task(task)

      # Load all tasks
      {:ok, tasks} = Store.load_all_tasks()
  """

  alias JidoWorkspace.Roadmap.Schema

  @roadmap_dir ".roadmap"

  # =============================================================================
  # TASK OPERATIONS
  # =============================================================================

  @doc """
  Load a task by ID.

  Returns {:ok, validated_task} or {:error, reason}.
  """
  def load_task(task_id) do
    path = task_path(task_id)

    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content, keys: :atoms),
         {:ok, task} <- Schema.validate_task(data) do
      {:ok, task}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:json_decode, path, Exception.message(e)}}

      {:error, errors} when is_list(errors) ->
        {:error, {:validation, path, errors}}

      {:error, reason} ->
        {:error, {:file, path, reason}}
    end
  end

  @doc """
  Save a task.

  Validates the task, then writes with sorted keys.
  Automatically updates `updated_at` timestamp.
  """
  def save_task(task) when is_map(task) do
    task = Map.put(task, :updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

    with {:ok, validated} <- Schema.validate_task(task),
         json <- encode_sorted(validated),
         path <- task_path(validated.id),
         :ok <- ensure_dir(path),
         :ok <- File.write(path, json) do
      :ok
    end
  end

  @doc """
  Load all tasks from the roadmap directory.

  Returns {:ok, [tasks]} or {:error, [{id, reason}, ...]}.
  """
  def load_all_tasks do
    case load_index() do
      {:ok, index} ->
        results =
          index.items
          |> Enum.map(fn id ->
            case load_task(id) do
              {:ok, task} -> {:ok, task}
              {:error, reason} -> {:error, {id, reason}}
            end
          end)

        errors = for {:error, e} <- results, do: e
        tasks = for {:ok, t} <- results, do: t

        if errors == [] do
          {:ok, tasks}
        else
          {:error, {:load_errors, errors}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a task exists.
  """
  def task_exists?(task_id) do
    task_id |> task_path() |> File.exists?()
  end

  @doc """
  Get the directory path for a task's artifacts.
  """
  def task_dir(task_id) do
    Path.join([roadmap_dir(), task_id])
  end

  @doc """
  Check if an artifact exists for a task.
  """
  def artifact_exists?(task_id, artifact_name) do
    task_id
    |> task_dir()
    |> Path.join(artifact_name)
    |> File.exists?()
  end

  @doc """
  List all artifacts for a task.
  """
  def list_artifacts(task_id) do
    dir = task_dir(task_id)

    case File.ls(dir) do
      {:ok, files} -> {:ok, files -- ["item.json"]}
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # INDEX OPERATIONS
  # =============================================================================

  @doc """
  Load the roadmap index.
  """
  def load_index do
    path = index_path()

    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content, keys: :atoms),
         {:ok, index} <- Schema.validate_index(data) do
      {:ok, index}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:json_decode, path, Exception.message(e)}}

      {:error, errors} when is_list(errors) ->
        {:error, {:validation, path, errors}}

      {:error, reason} ->
        {:error, {:file, path, reason}}
    end
  end

  @doc """
  Save the roadmap index.
  """
  def save_index(index) when is_map(index) do
    with {:ok, validated} <- Schema.validate_index(index),
         json <- encode_sorted(validated),
         :ok <- File.write(index_path(), json) do
      :ok
    end
  end

  @doc """
  Rebuild the index by scanning the roadmap directory.
  """
  def rebuild_index do
    items =
      roadmap_dir()
      |> scan_task_ids()
      |> Enum.sort()

    index = %{
      version: "1.0.0",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      items: items
    }

    save_index(index)
  end

  # =============================================================================
  # PRD OPERATIONS
  # =============================================================================

  @doc """
  Load a PRD for a task.
  """
  def load_prd(task_id) do
    path = prd_path(task_id)

    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content, keys: :atoms),
         {:ok, prd} <- Schema.validate_prd(data) do
      {:ok, prd}
    else
      {:error, %Jason.DecodeError{} = e} ->
        {:error, {:json_decode, path, Exception.message(e)}}

      {:error, errors} when is_list(errors) ->
        {:error, {:validation, path, errors}}

      {:error, reason} ->
        {:error, {:file, path, reason}}
    end
  end

  @doc """
  Save a PRD for a task.
  """
  def save_prd(task_id, prd) when is_map(prd) do
    with {:ok, validated} <- Schema.validate_prd(prd),
         json <- encode_sorted(validated),
         path <- prd_path(task_id),
         :ok <- ensure_dir(path),
         :ok <- File.write(path, json) do
      :ok
    end
  end

  # =============================================================================
  # PRIVATE HELPERS
  # =============================================================================

  defp roadmap_dir do
    Path.join(File.cwd!(), @roadmap_dir)
  end

  defp index_path do
    Path.join(roadmap_dir(), "index.json")
  end

  defp task_path(task_id) do
    Path.join([roadmap_dir(), task_id, "item.json"])
  end

  defp prd_path(task_id) do
    Path.join([roadmap_dir(), task_id, "prd.json"])
  end

  defp ensure_dir(file_path) do
    file_path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  @doc """
  Encode a map to JSON with sorted keys for stable diffs.

  This is critical for git collaboration - unsorted keys cause
  spurious diff noise on every save.
  """
  def encode_sorted(data) do
    data
    |> deep_sort_keys()
    |> Jason.encode!(pretty: true)
    |> Kernel.<>("\n")
  end

  defp deep_sort_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), deep_sort_keys(v)} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp deep_sort_keys(list) when is_list(list) do
    Enum.map(list, &deep_sort_keys/1)
  end

  defp deep_sort_keys(other), do: other

  defp scan_task_ids(dir) do
    dir
    |> Path.join("**/item.json")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      path
      |> Path.dirname()
      |> Path.relative_to(dir)
    end)
  end
end
