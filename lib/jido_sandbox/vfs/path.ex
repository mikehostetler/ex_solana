defmodule JidoSandbox.VFS.Path do
  @moduledoc """
  Path normalization and validation for the VFS.

  All paths must:
  - Be absolute (start with `/`)
  - Not contain path traversal (`..`)
  - Use forward slashes as separators
  """

  @doc """
  Normalize and validate a path.

  Returns `{:ok, normalized_path}` or `{:error, reason}`.

  ## Examples

      iex> JidoSandbox.VFS.Path.normalize("/foo/bar")
      {:ok, "/foo/bar"}

      iex> JidoSandbox.VFS.Path.normalize("/foo//bar")
      {:ok, "/foo/bar"}

      iex> JidoSandbox.VFS.Path.normalize("relative/path")
      {:error, :path_must_be_absolute}

      iex> JidoSandbox.VFS.Path.normalize("/foo/../bar")
      {:error, :path_traversal_not_allowed}

  """
  @spec normalize(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def normalize(path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") ->
        {:error, :path_must_be_absolute}

      String.contains?(path, "..") ->
        {:error, :path_traversal_not_allowed}

      true ->
        normalized =
          path
          |> String.split("/")
          |> Enum.reject(&(&1 == ""))
          |> then(fn parts ->
            case parts do
              [] -> "/"
              parts -> "/" <> Enum.join(parts, "/")
            end
          end)

        {:ok, normalized}
    end
  end

  def normalize(_), do: {:error, :invalid_path}

  @doc """
  Get the parent directory of a path.

  ## Examples

      iex> JidoSandbox.VFS.Path.parent("/foo/bar/baz.txt")
      "/foo/bar"

      iex> JidoSandbox.VFS.Path.parent("/foo")
      "/"

      iex> JidoSandbox.VFS.Path.parent("/")
      "/"

  """
  @spec parent(String.t()) :: String.t()
  def parent("/"), do: "/"

  def parent(path) when is_binary(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> Enum.drop(-1)
    |> then(fn
      [] -> "/"
      parts -> "/" <> Enum.join(parts, "/")
    end)
  end

  @doc """
  Get the basename (filename) of a path.

  ## Examples

      iex> JidoSandbox.VFS.Path.basename("/foo/bar/baz.txt")
      "baz.txt"

      iex> JidoSandbox.VFS.Path.basename("/foo")
      "foo"

      iex> JidoSandbox.VFS.Path.basename("/")
      ""

  """
  @spec basename(String.t()) :: String.t()
  def basename("/"), do: ""

  def basename(path) when is_binary(path) do
    path
    |> String.split("/")
    |> List.last()
  end

  @doc """
  Check if a path is a direct child of a parent directory.

  ## Examples

      iex> JidoSandbox.VFS.Path.direct_child?("/foo/bar.txt", "/foo")
      true

      iex> JidoSandbox.VFS.Path.direct_child?("/foo/bar/baz.txt", "/foo")
      false

      iex> JidoSandbox.VFS.Path.direct_child?("/foo", "/")
      true

  """
  @spec direct_child?(String.t(), String.t()) :: boolean()
  def direct_child?(path, parent_dir) do
    parent(path) == parent_dir
  end
end
