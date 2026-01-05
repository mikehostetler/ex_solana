defmodule JidoSandbox.VFS.InMemory do
  @moduledoc """
  In-memory VFS implementation.

  Stores all files in a map with paths as keys and binary content as values.
  Directories are tracked explicitly in a MapSet.
  """

  @behaviour JidoSandbox.VFS

  alias JidoSandbox.VFS.Path, as: VPath

  @type t :: %__MODULE__{
          files: %{String.t() => binary()},
          dirs: MapSet.t(String.t())
        }

  defstruct files: %{}, dirs: MapSet.new(["/"])

  @impl true
  def new, do: %__MODULE__{}

  @impl true
  @spec write(t(), String.t(), iodata()) :: {:ok, t()} | {:error, term()}
  def write(%__MODULE__{} = vfs, path, content) do
    with {:ok, normalized} <- VPath.normalize(path),
         :ok <- ensure_parent_exists(vfs, normalized) do
      binary_content = IO.iodata_to_binary(content)
      {:ok, %{vfs | files: Map.put(vfs.files, normalized, binary_content)}}
    end
  end

  @impl true
  @spec read(t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def read(%__MODULE__{} = vfs, path) do
    with {:ok, normalized} <- VPath.normalize(path) do
      case Map.fetch(vfs.files, normalized) do
        {:ok, content} -> {:ok, content}
        :error -> {:error, :file_not_found}
      end
    end
  end

  @impl true
  @spec list(t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def list(%__MODULE__{} = vfs, path) do
    with {:ok, normalized} <- VPath.normalize(path) do
      if MapSet.member?(vfs.dirs, normalized) do
        files =
          vfs.files
          |> Map.keys()
          |> Enum.filter(&VPath.direct_child?(&1, normalized))
          |> Enum.map(&VPath.basename/1)

        subdirs =
          vfs.dirs
          |> MapSet.to_list()
          |> Enum.filter(fn d -> d != normalized and VPath.direct_child?(d, normalized) end)
          |> Enum.map(&(VPath.basename(&1) <> "/"))

        {:ok, Enum.sort(files ++ subdirs)}
      else
        {:error, :directory_not_found}
      end
    end
  end

  @impl true
  @spec delete(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def delete(%__MODULE__{} = vfs, path) do
    with {:ok, normalized} <- VPath.normalize(path) do
      cond do
        Map.has_key?(vfs.files, normalized) ->
          {:ok, %{vfs | files: Map.delete(vfs.files, normalized)}}

        MapSet.member?(vfs.dirs, normalized) and normalized != "/" ->
          has_children =
            Enum.any?(Map.keys(vfs.files), &String.starts_with?(&1, normalized <> "/")) or
              Enum.any?(MapSet.to_list(vfs.dirs), fn d ->
                d != normalized and String.starts_with?(d, normalized <> "/")
              end)

          if has_children do
            {:error, :directory_not_empty}
          else
            {:ok, %{vfs | dirs: MapSet.delete(vfs.dirs, normalized)}}
          end

        normalized == "/" ->
          {:error, :cannot_delete_root}

        true ->
          {:error, :not_found}
      end
    end
  end

  @impl true
  @spec mkdir(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def mkdir(%__MODULE__{} = vfs, path) do
    with {:ok, normalized} <- VPath.normalize(path),
         :ok <- ensure_parent_exists(vfs, normalized) do
      if MapSet.member?(vfs.dirs, normalized) do
        {:error, :directory_exists}
      else
        {:ok, %{vfs | dirs: MapSet.put(vfs.dirs, normalized)}}
      end
    end
  end

  defp ensure_parent_exists(%__MODULE__{} = vfs, path) do
    parent = VPath.parent(path)

    if MapSet.member?(vfs.dirs, parent) do
      :ok
    else
      {:error, :parent_directory_not_found}
    end
  end
end
