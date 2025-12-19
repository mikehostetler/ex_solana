defmodule JidoCode.Tools.Registry do
  @moduledoc """
  Registry for tool registration and lookup.

  This GenServer maintains a registry of available tools that can be invoked
  by the LLM agent. Tools are stored in an ETS table for fast concurrent reads,
  with the GenServer handling writes and ensuring consistency.

  ## Starting the Registry

  The registry is started as part of the application supervision tree:

      children = [
        JidoCode.Tools.Registry,
        # ...
      ]

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
  """

  use GenServer

  alias JidoCode.Tools.Tool

  @table_name :jido_code_tools_registry

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Registry GenServer.

  ## Options

  - `:name` - GenServer name (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

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
  def register(%Tool{} = tool) do
    GenServer.call(__MODULE__, {:register, tool})
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
    GenServer.call(__MODULE__, {:unregister, name})
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
    @table_name
    |> :ets.tab2list()
    |> Enum.map(fn {_name, tool} -> tool end)
    |> Enum.sort_by(& &1.name)
  rescue
    ArgumentError -> []
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
    case :ets.lookup(@table_name, name) do
      [{^name, tool}] -> {:ok, tool}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
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
    :ets.info(@table_name, :size)
  rescue
    ArgumentError -> 0
  end

  @doc """
  Clears all registered tools.

  Primarily useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
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
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS table for fast reads
    table = :ets.new(@table_name, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, %Tool{name: name} = tool}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [] ->
        :ets.insert(@table_name, {name, tool})
        {:reply, :ok, state}

      [_existing] ->
        {:reply, {:error, :already_registered}, state}
    end
  end

  @impl true
  def handle_call({:unregister, name}, _from, state) do
    case :ets.lookup(@table_name, name) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [_existing] ->
        :ets.delete(@table_name, name)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

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
