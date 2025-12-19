defmodule JidoCode.Tools do
  @moduledoc """
  Tool system for LLM agent interactions with the codebase.

  This module provides the namespace and convenience functions for the tool
  infrastructure that enables the LLM agent to perform operations like
  reading files, searching code, and executing commands.

  ## Architecture

  The tool system consists of:

  - `JidoCode.Tools.Param` - Parameter definitions for tool inputs
  - `JidoCode.Tools.Tool` - Tool definitions with schema and handlers
  - `JidoCode.Tools.Registry` - Registration and lookup of available tools

  ## Usage

      # Define a tool
      {:ok, tool} = JidoCode.Tools.Tool.new(%{
        name: "read_file",
        description: "Read the contents of a file",
        parameters: [
          %{name: "path", type: :string, description: "File path to read"}
        ],
        handler: JidoCode.Tools.Handlers.ReadFile
      })

      # Register the tool
      :ok = JidoCode.Tools.Registry.register(tool)

      # Look up a tool
      {:ok, tool} = JidoCode.Tools.Registry.get("read_file")

      # Get LLM-compatible format for system prompt
      tools_json = JidoCode.Tools.Registry.to_llm_format()

  ## Handler Contract

  Tool handlers must implement the following callback:

      @callback execute(params :: map(), context :: map()) ::
        {:ok, result :: term()} | {:error, reason :: term()}

  The `context` map provides execution context including:
  - `:project_root` - The root directory for sandboxed operations
  - `:timeout` - Execution timeout in milliseconds
  """

  alias JidoCode.Tools.{Param, Registry, Tool}
  alias JidoCode.Tools.Definitions

  @doc """
  Registers all built-in tools with the Registry.

  This is a convenience function to register all available tools at once.
  Includes: file system, search, shell, livebook, web, todo, and task tools.

  ## Returns

  - `:ok` if all tools registered successfully
  - `{:error, failed}` with list of tools that failed to register

  ## Examples

      :ok = JidoCode.Tools.register_all()
  """
  @spec register_all() :: :ok | {:error, [{String.t(), term()}]}
  def register_all do
    tools =
      Definitions.FileSystem.all() ++
        Definitions.Search.all() ++
        Definitions.Shell.all() ++
        Definitions.Livebook.all() ++
        Definitions.Web.all() ++
        Definitions.Todo.all() ++
        Definitions.Task.all()

    results =
      Enum.map(tools, fn tool ->
        case Registry.register(tool) do
          :ok -> {:ok, tool.name}
          {:error, :already_registered} -> {:ok, tool.name}
          {:error, reason} -> {:error, {tool.name, reason}}
        end
      end)

    failed = Enum.filter(results, &match?({:error, _}, &1))

    if Enum.empty?(failed) do
      :ok
    else
      {:error, Enum.map(failed, fn {:error, info} -> info end)}
    end
  end

  @doc """
  Creates a new tool parameter.

  Delegates to `JidoCode.Tools.Param.new/1`.

  ## Examples

      {:ok, param} = JidoCode.Tools.new_param(%{
        name: "path",
        type: :string,
        description: "File path"
      })
  """
  @spec new_param(map()) :: {:ok, Param.t()} | {:error, String.t()}
  defdelegate new_param(attrs), to: Param, as: :new

  @doc """
  Creates a new tool.

  Delegates to `JidoCode.Tools.Tool.new/1`.

  ## Examples

      {:ok, tool} = JidoCode.Tools.new_tool(%{
        name: "read_file",
        description: "Read a file",
        handler: MyHandler
      })
  """
  @spec new_tool(map()) :: {:ok, Tool.t()} | {:error, String.t()}
  defdelegate new_tool(attrs), to: Tool, as: :new

  @doc """
  Registers a tool in the registry.

  Delegates to `JidoCode.Tools.Registry.register/1`.
  """
  @spec register(Tool.t()) :: :ok | {:error, term()}
  defdelegate register(tool), to: Registry

  @doc """
  Lists all registered tools.

  Delegates to `JidoCode.Tools.Registry.list/0`.
  """
  @spec list_tools() :: [Tool.t()]
  defdelegate list_tools, to: Registry, as: :list

  @doc """
  Gets a tool by name.

  Delegates to `JidoCode.Tools.Registry.get/1`.
  """
  @spec get_tool(String.t()) :: {:ok, Tool.t()} | {:error, :not_found}
  defdelegate get_tool(name), to: Registry, as: :get

  @doc """
  Gets all tools in LLM-compatible format.

  Delegates to `JidoCode.Tools.Registry.to_llm_format/0`.
  """
  @spec to_llm_format() :: [map()]
  defdelegate to_llm_format, to: Registry
end
