defmodule JidoCode.Tools.HandlerHelpers do
  @moduledoc """
  Shared helper functions for tool handlers.

  This module consolidates common functionality used across FileSystem,
  Search, and Shell handlers to reduce code duplication.

  ## Functions

  - `get_project_root/1` - Extract project root from context or Manager
  - `format_common_error/2` - Format errors common across all handlers

  ## Usage

      alias JidoCode.Tools.HandlerHelpers

      with {:ok, project_root} <- HandlerHelpers.get_project_root(context) do
        # use project_root
      end
  """

  alias JidoCode.Tools.Manager

  @doc """
  Extracts the project root from the context map or fetches from Manager.

  ## Examples

      iex> HandlerHelpers.get_project_root(%{project_root: "/home/user/project"})
      {:ok, "/home/user/project"}

      iex> HandlerHelpers.get_project_root(%{})
      # Returns Manager.project_root() result
  """
  @spec get_project_root(map()) :: {:ok, String.t()} | {:error, String.t()}
  def get_project_root(%{project_root: root}) when is_binary(root), do: {:ok, root}
  def get_project_root(_context), do: Manager.project_root()

  @doc """
  Formats common error types used across all handlers.

  Returns the formatted error message. Handlers may extend this with
  domain-specific error patterns.

  ## Common Errors

  - `:enoent` - File/path not found
  - `:eacces` - Permission denied
  - `:path_escapes_boundary` - Path traversal attempt
  - `:path_outside_boundary` - Path outside project
  - `:symlink_escapes_boundary` - Symlink points outside project

  ## Examples

      iex> HandlerHelpers.format_common_error(:enoent, "/path/to/file")
      {:ok, "Path not found: /path/to/file"}

      iex> HandlerHelpers.format_common_error(:custom_error, "/path")
      :not_handled
  """
  @spec format_common_error(atom() | tuple() | String.t(), String.t()) ::
          {:ok, String.t()} | :not_handled
  def format_common_error(:enoent, path), do: {:ok, "Path not found: #{path}"}
  def format_common_error(:eacces, path), do: {:ok, "Permission denied: #{path}"}

  def format_common_error(:path_escapes_boundary, path),
    do: {:ok, "Security error: path escapes project boundary: #{path}"}

  def format_common_error(:path_outside_boundary, path),
    do: {:ok, "Security error: path is outside project: #{path}"}

  def format_common_error(:symlink_escapes_boundary, path),
    do: {:ok, "Security error: symlink points outside project: #{path}"}

  def format_common_error(reason, _path) when is_binary(reason), do: {:ok, reason}
  def format_common_error(_reason, _path), do: :not_handled
end
