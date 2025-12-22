defmodule JidoCode.Tools.Registry do
  @moduledoc """
  Registry for tool registration and lookup using :persistent_term.

  This module provides a simple, fast registry for tools using Erlang's
  :persistent_term storage. This is ideal for our use case where ~100 tools
  are registered once at startup and read thousands of times during execution.

  ## Why :persistent_term?

  - **Faster reads**: Constant-time lookups, faster than ETS
  - **No process overhead**: No GenServer bottleneck for concurrent access
  - **Simpler**: No process supervision or ETS table management
  - **Perfect for our pattern**: Write-once-read-many with ~100 tools

  ## Usage

      # Register a tool
      :ok = Registry.register(tool)

      # List all tools
      tools = Registry.list()

      # Look up by name
      {:ok, tool} = Registry.get("read_file")

      # Get LLM format for system prompt
      functions = Registry.to_llm_format()

  ## Duplicate Prevention

  Attempting to register a tool with a name that already exists will return
  an error. Use `unregister/1` first if you need to replace a tool.

  ## Performance Characteristics

  - **Reads**: Extremely fast, constant time, no locks
  - **Writes**: Triggers global GC (acceptable for startup-only writes)
  - **Concurrency**: Perfect for concurrent reads, avoid concurrent writes
  """

  alias JidoCode.Tools.Tool

  @prefix {:jido_code_tools_registry}
  @all_tools_key {@prefix, :all_tools}

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Registers a tool in the registry.

  ## Parameters

  - `tool` - A `%Tool{}` struct to register

  ## Returns

  - `:ok` - Tool registered successfully
  - `{:error, :already_registered}` - A tool with this name already exists
  - `{:error, :invalid_tool}` - The argument is not a valid Tool struct

  ## Examples

      {:ok, tool} = Tool.new(%{name: "read_file", ...})
      :ok = Registry.register(tool)

      # Duplicate registration fails
      {:error, :already_registered} = Registry.register(tool)
  """
  @spec register(Tool.t()) :: :ok | {:error, :already_registered | :invalid_tool}
  def register(%Tool{name: name} = tool) do
    key = {@prefix, name}

    case :persistent_term.get(key, nil) do
      nil ->
        :persistent_term.put(key, tool)
        add_to_tools_list(name)
        :ok

      _existing ->
        {:error, :already_registered}
    end
  end

  def register(_), do: {:error, :invalid_tool}

  @doc """
  Unregisters a tool from the registry.

  ## Parameters

  - `name` - The tool name to unregister

  ## Returns

  - `:ok` - Tool unregistered successfully
  - `{:error, :not_found}` - No tool with this name exists

  ## Examples

      :ok = Registry.unregister("read_file")
  """
  @spec unregister(String.t()) :: :ok | {:error, :not_found}
  def unregister(name) when is_binary(name) do
    key = {@prefix, name}

    case :persistent_term.get(key, nil) do
      nil ->
        {:error, :not_found}

      _existing ->
        :persistent_term.erase(key)
        remove_from_tools_list(name)
        :ok
    end
  end

  @doc """
  Lists all registered tools.

  ## Returns

  A list of all registered `%Tool{}` structs, sorted by name.

  ## Examples

      tools = Registry.list()
      # => [%Tool{name: "find_files", ...}, %Tool{name: "read_file", ...}]
  """
  @spec list() :: [Tool.t()]
  def list do
    @all_tools_key
    |> :persistent_term.get([])
    |> Enum.map(fn name ->
      {:ok, tool} = get(name)
      tool
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Gets a tool by name.

  ## Parameters

  - `name` - The tool name to look up

  ## Returns

  - `{:ok, tool}` - Tool found
  - `{:error, :not_found}` - No tool with this name

  ## Examples

      {:ok, tool} = Registry.get("read_file")
      {:error, :not_found} = Registry.get("unknown")
  """
  @spec get(String.t()) :: {:ok, Tool.t()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    key = {@prefix, name}

    case :persistent_term.get(key, nil) do
      nil -> {:error, :not_found}
      tool -> {:ok, tool}
    end
  end

  @doc """
  Checks if a tool is registered.

  ## Parameters

  - `name` - The tool name to check

  ## Returns

  `true` if the tool exists, `false` otherwise.
  """
  @spec registered?(String.t()) :: boolean()
  def registered?(name) when is_binary(name) do
    case get(name) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Returns the count of registered tools.
  """
  @spec count() :: non_neg_integer()
  def count do
    @all_tools_key
    |> :persistent_term.get([])
    |> length()
  end

  @doc """
  Clears all registered tools.

  **WARNING**: This triggers a global garbage collection! Only use in tests.

  Primarily useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    # Get all tool names and erase them
    for name <- :persistent_term.get(@all_tools_key, []) do
      :persistent_term.erase({@prefix, name})
    end

    # Clear the tools list
    :persistent_term.erase(@all_tools_key)
    :ok
  end

  @doc """
  Converts all registered tools to LLM-compatible format.

  Returns a list of function definitions suitable for inclusion in an
  OpenAI-compatible chat completion request's `tools` parameter.

  ## Returns

  A list of maps with the structure:

      [
        %{
          type: "function",
          function: %{
            name: "tool_name",
            description: "Tool description",
            parameters: %{type: "object", properties: %{...}, required: [...]}
          }
        },
        ...
      ]

  ## Examples

      functions = Registry.to_llm_format()
      # Can be used directly in API calls
  """
  @spec to_llm_format() :: [map()]
  def to_llm_format do
    list()
    |> Enum.map(&Tool.to_llm_function/1)
  end

  @doc """
  Generates a text description of all tools for system prompts.

  Creates a human-readable summary of available tools that can be included
  in system prompts for models that don't support function calling.

  ## Returns

  A formatted string describing all available tools.
  """
  @spec to_text_description() :: String.t()
  def to_text_description do
    tools = list()

    if Enum.empty?(tools) do
      "No tools available."
    else
      Enum.map_join(tools, "\n\n", &format_tool_description/1)
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp add_to_tools_list(name) do
    current_tools = :persistent_term.get(@all_tools_key, [])

    unless name in current_tools do
      :persistent_term.put(@all_tools_key, [name | current_tools])
    end
  end

  defp remove_from_tools_list(name) do
    current_tools = :persistent_term.get(@all_tools_key, [])
    :persistent_term.put(@all_tools_key, List.delete(current_tools, name))
  end

  defp format_tool_description(%Tool{} = tool) do
    params_desc = format_params_description(tool.parameters)

    """
    ## #{tool.name}
    #{tool.description}

    Parameters:
    #{params_desc}
    """
  end

  defp format_params_description([]), do: "  No parameters"

  defp format_params_description(params) do
    Enum.map_join(params, "\n", fn p ->
      required = if p.required, do: "(required)", else: "(optional)"
      "  - #{p.name}: #{p.type} #{required} - #{p.description}"
    end)
  end
end
