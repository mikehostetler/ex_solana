defmodule JidoSandbox.Schemas do
  @moduledoc """
  Zoi schemas for validating LLM tool inputs.

  These schemas ensure that inputs to sandbox operations are valid
  before processing, providing clear error messages for LLM tools.
  """

  @doc """
  Schema for validating file/directory paths.

  Paths must:
  - Be non-empty strings
  - Start with `/` (absolute)
  - Not contain `..` (no traversal)
  """
  @spec path_schema() :: term()
  def path_schema do
    Zoi.string()
    |> Zoi.min(1)
    |> Zoi.refine(fn path ->
      cond do
        not String.starts_with?(path, "/") ->
          {:error, "path must be absolute (start with /)"}

        String.contains?(path, "..") ->
          {:error, "path traversal (..) is not allowed"}

        true ->
          :ok
      end
    end)
  end

  @doc """
  Schema for write operation parameters.
  """
  @spec write_schema() :: term()
  def write_schema do
    Zoi.map(%{
      "path" => path_schema(),
      "content" => Zoi.string()
    })
  end

  @doc """
  Schema for read operation parameters.
  """
  @spec read_schema() :: term()
  def read_schema do
    Zoi.map(%{
      "path" => path_schema()
    })
  end

  @doc """
  Schema for list operation parameters.
  """
  @spec list_schema() :: term()
  def list_schema do
    Zoi.map(%{
      "path" => path_schema()
    })
  end

  @doc """
  Schema for delete operation parameters.
  """
  @spec delete_schema() :: term()
  def delete_schema do
    Zoi.map(%{
      "path" => path_schema()
    })
  end

  @doc """
  Schema for mkdir operation parameters.
  """
  @spec mkdir_schema() :: term()
  def mkdir_schema do
    Zoi.map(%{
      "path" => path_schema()
    })
  end

  @doc """
  Schema for eval_lua operation parameters.
  """
  @spec eval_lua_schema() :: term()
  def eval_lua_schema do
    Zoi.map(%{
      "code" => Zoi.string() |> Zoi.min(1)
    })
  end

  @doc """
  Validate a path string.

  ## Examples

      iex> JidoSandbox.Schemas.validate_path("/foo/bar")
      {:ok, "/foo/bar"}

      iex> JidoSandbox.Schemas.validate_path("relative")
      {:error, _}

  """
  @spec validate_path(String.t()) :: {:ok, String.t()} | {:error, term()}
  def validate_path(path) do
    case Zoi.parse(path_schema(), path) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate write parameters.
  """
  @spec validate_write(map()) :: {:ok, map()} | {:error, term()}
  def validate_write(params) do
    case Zoi.parse(write_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate read parameters.
  """
  @spec validate_read(map()) :: {:ok, map()} | {:error, term()}
  def validate_read(params) do
    case Zoi.parse(read_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate list parameters.
  """
  @spec validate_list(map()) :: {:ok, map()} | {:error, term()}
  def validate_list(params) do
    case Zoi.parse(list_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate delete parameters.
  """
  @spec validate_delete(map()) :: {:ok, map()} | {:error, term()}
  def validate_delete(params) do
    case Zoi.parse(delete_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate mkdir parameters.
  """
  @spec validate_mkdir(map()) :: {:ok, map()} | {:error, term()}
  def validate_mkdir(params) do
    case Zoi.parse(mkdir_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  @doc """
  Validate eval_lua parameters.
  """
  @spec validate_eval_lua(map()) :: {:ok, map()} | {:error, term()}
  def validate_eval_lua(params) do
    case Zoi.parse(eval_lua_schema(), params) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  defp format_errors(errors) do
    Enum.map_join(errors, "; ", &format_error/1)
  end

  defp format_error(%{message: message, path: path}) when path != [] do
    "#{Enum.join(path, ".")}: #{message}"
  end

  defp format_error(%{message: message}), do: message
end
