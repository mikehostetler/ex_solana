defmodule JidoCode.Tools.Tool do
  @moduledoc """
  Defines a tool that can be invoked by the LLM agent.

  Tools encapsulate operations like file reading, searching, or command execution.
  Each tool has a name, description, parameters schema, and a handler module that
  implements the actual execution logic.

  ## Structure

  - `:name` - Unique identifier for the tool (e.g., "read_file")
  - `:description` - Human-readable description for LLM context
  - `:parameters` - List of `Param` structs defining accepted inputs
  - `:handler` - Module atom that implements `execute/2` callback

  ## Handler Contract

  Handler modules must implement:

      @callback execute(params :: map(), context :: map()) ::
        {:ok, result :: term()} | {:error, reason :: term()}

  ## Examples

      # Define a file reading tool
      {:ok, tool} = Tool.new(%{
        name: "read_file",
        description: "Read the contents of a file",
        parameters: [
          %{name: "path", type: :string, description: "Path to the file"}
        ],
        handler: JidoCode.Tools.Handlers.ReadFile
      })

      # Convert to LLM function format
      Tool.to_llm_function(tool)
      # => %{
      #   type: "function",
      #   function: %{
      #     name: "read_file",
      #     description: "Read the contents of a file",
      #     parameters: %{...}
      #   }
      # }
  """

  alias JidoCode.Tools.Param

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: [Param.t()],
          handler: atom()
        }

  @enforce_keys [:name, :description, :handler]
  defstruct [
    :name,
    :description,
    :handler,
    parameters: []
  ]

  @doc """
  Creates a new Tool struct with validation.

  ## Parameters

  - `attrs` - A map with the following keys:
    - `:name` (required) - Unique tool name as string
    - `:description` (required) - Human-readable description
    - `:handler` (required) - Module atom implementing execute/2
    - `:parameters` (optional) - List of parameter definitions (maps or Param structs)

  ## Returns

  - `{:ok, %Tool{}}` - Valid tool
  - `{:error, reason}` - Validation failure

  ## Examples

      iex> Tool.new(%{
      ...>   name: "list_files",
      ...>   description: "List files in a directory",
      ...>   handler: MyApp.ListFilesHandler,
      ...>   parameters: [
      ...>     %{name: "path", type: :string, description: "Directory path"}
      ...>   ]
      ...> })
      {:ok, %Tool{name: "list_files", ...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    with {:ok, name} <- validate_name(attrs),
         {:ok, description} <- validate_description(attrs),
         {:ok, handler} <- validate_handler(attrs),
         {:ok, parameters} <- validate_parameters(attrs) do
      tool = %__MODULE__{
        name: name,
        description: description,
        handler: handler,
        parameters: parameters
      }

      {:ok, tool}
    end
  end

  @doc """
  Creates a new Tool struct, raising on validation failure.

  Same as `new/1` but raises `ArgumentError` on failure.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, tool} -> tool
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Converts a Tool to LLM function calling format.

  Generates an OpenAI-compatible function definition that can be included
  in the `tools` array of a chat completion request.

  ## Returns

  A map with:
  - `:type` - Always "function"
  - `:function` - Map with name, description, and parameters schema

  ## Examples

      iex> tool = %Tool{name: "read_file", description: "Read file", handler: MyHandler, parameters: []}
      iex> Tool.to_llm_function(tool)
      %{
        type: "function",
        function: %{
          name: "read_file",
          description: "Read file",
          parameters: %{type: "object", properties: %{}, required: []}
        }
      }
  """
  @spec to_llm_function(t()) :: map()
  def to_llm_function(%__MODULE__{} = tool) do
    %{
      type: "function",
      function: %{
        name: tool.name,
        description: tool.description,
        parameters: parameters_to_json_schema(tool.parameters)
      }
    }
  end

  @doc """
  Returns the list of required parameter names for a tool.

  ## Examples

      iex> tool = %Tool{parameters: [%Param{name: "path", required: true}, %Param{name: "opts", required: false}]}
      iex> Tool.required_params(tool)
      ["path"]
  """
  @spec required_params(t()) :: [String.t()]
  def required_params(%__MODULE__{parameters: params}) do
    params
    |> Enum.filter(& &1.required)
    |> Enum.map(& &1.name)
  end

  @doc """
  Validates that a map of arguments satisfies the tool's parameter requirements.

  Checks:
  - All required parameters are present
  - No unknown parameters are provided
  - Parameter types match (basic type checking)

  ## Returns

  - `:ok` - All parameters valid
  - `{:error, reason}` - Validation failure with details

  ## Examples

      iex> tool = %Tool{parameters: [%Param{name: "path", type: :string, required: true}]}
      iex> Tool.validate_args(tool, %{"path" => "/tmp/file.txt"})
      :ok

      iex> Tool.validate_args(tool, %{})
      {:error, "missing required parameter: path"}
  """
  @spec validate_args(t(), map()) :: :ok | {:error, String.t()}
  def validate_args(%__MODULE__{parameters: params}, args) when is_map(args) do
    with :ok <- check_required_params(params, args),
         :ok <- check_unknown_params(params, args) do
      check_param_types(params, args)
    end
  end

  # ============================================================================
  # Private Validation Functions
  # ============================================================================

  defp validate_name(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    # Validate name format: lowercase letters, numbers, underscores
    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      {:ok, name}
    else
      {:error,
       "name must start with lowercase letter and contain only lowercase letters, numbers, and underscores"}
    end
  end

  defp validate_name(%{name: name}) when is_atom(name) and not is_nil(name) do
    validate_name(%{name: Atom.to_string(name)})
  end

  defp validate_name(%{name: _}) do
    {:error, "name must be a non-empty string"}
  end

  defp validate_name(_) do
    {:error, "name is required"}
  end

  defp validate_description(%{description: desc}) when is_binary(desc) and byte_size(desc) > 0 do
    {:ok, desc}
  end

  defp validate_description(%{description: _}) do
    {:error, "description must be a non-empty string"}
  end

  defp validate_description(_) do
    {:error, "description is required"}
  end

  defp validate_handler(%{handler: handler}) when is_atom(handler) and not is_nil(handler) do
    {:ok, handler}
  end

  defp validate_handler(%{handler: _}) do
    {:error, "handler must be a module atom"}
  end

  defp validate_handler(_) do
    {:error, "handler is required"}
  end

  defp validate_parameters(%{parameters: params}) when is_list(params) do
    results =
      Enum.map(params, fn
        %Param{} = p -> {:ok, p}
        map when is_map(map) -> Param.new(map)
        other -> {:error, "invalid parameter: #{inspect(other)}"}
      end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, p} -> p end)}
      {:error, reason} -> {:error, "invalid parameter: #{reason}"}
    end
  end

  defp validate_parameters(_) do
    {:ok, []}
  end

  # ============================================================================
  # Private JSON Schema Helpers
  # ============================================================================

  defp parameters_to_json_schema(params) when is_list(params) do
    properties =
      params
      |> Enum.map(fn param -> {param.name, Param.to_json_schema(param)} end)
      |> Map.new()

    required =
      params
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  # ============================================================================
  # Private Argument Validation Helpers
  # ============================================================================

  defp check_required_params(params, args) do
    missing =
      params
      |> Enum.filter(& &1.required)
      |> Enum.reject(fn p -> Map.has_key?(args, p.name) end)
      |> Enum.map(& &1.name)

    case missing do
      [] -> :ok
      [name] -> {:error, "missing required parameter: #{name}"}
      names -> {:error, "missing required parameters: #{Enum.join(names, ", ")}"}
    end
  end

  defp check_unknown_params(params, args) do
    known_names = MapSet.new(Enum.map(params, & &1.name))
    arg_names = MapSet.new(Map.keys(args))
    unknown = MapSet.difference(arg_names, known_names)

    case MapSet.to_list(unknown) do
      [] -> :ok
      [name] -> {:error, "unknown parameter: #{name}"}
      names -> {:error, "unknown parameters: #{Enum.join(names, ", ")}"}
    end
  end

  defp check_param_types(params, args) do
    params
    |> Enum.reduce_while(:ok, fn param, _acc ->
      case Map.get(args, param.name) do
        nil -> {:cont, :ok}
        value -> check_type(param, value)
      end
    end)
  end

  defp check_type(%Param{type: :string}, value) when is_binary(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :string}, value) do
    {:halt, {:error, "parameter '#{name}' must be a string, got: #{inspect(value)}"}}
  end

  defp check_type(%Param{type: :integer}, value) when is_integer(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :integer}, value) do
    {:halt, {:error, "parameter '#{name}' must be an integer, got: #{inspect(value)}"}}
  end

  defp check_type(%Param{type: :number}, value) when is_number(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :number}, value) do
    {:halt, {:error, "parameter '#{name}' must be a number, got: #{inspect(value)}"}}
  end

  defp check_type(%Param{type: :boolean}, value) when is_boolean(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :boolean}, value) do
    {:halt, {:error, "parameter '#{name}' must be a boolean, got: #{inspect(value)}"}}
  end

  defp check_type(%Param{type: :array}, value) when is_list(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :array}, value) do
    {:halt, {:error, "parameter '#{name}' must be an array, got: #{inspect(value)}"}}
  end

  defp check_type(%Param{type: :object}, value) when is_map(value) do
    {:cont, :ok}
  end

  defp check_type(%Param{name: name, type: :object}, value) do
    {:halt, {:error, "parameter '#{name}' must be an object, got: #{inspect(value)}"}}
  end
end
