defmodule JidoCode.Tools.Param do
  @moduledoc """
  Defines a parameter for a tool.

  Parameters describe the inputs a tool accepts, including their types,
  descriptions, and whether they are required. This information is used
  for validation and for generating LLM-compatible function schemas.

  ## Supported Types

  - `:string` - Text values
  - `:integer` - Whole numbers
  - `:number` - Floating point numbers
  - `:boolean` - True/false values
  - `:array` - Lists of values (items type specified via `:items`)
  - `:object` - Nested objects (properties specified via `:properties`)

  ## Examples

      # Simple required string parameter
      {:ok, param} = Param.new(%{
        name: "path",
        type: :string,
        description: "The file path to read"
      })

      # Optional boolean with default
      {:ok, param} = Param.new(%{
        name: "recursive",
        type: :boolean,
        description: "Search recursively",
        required: false,
        default: false
      })

      # Array parameter with item type
      {:ok, param} = Param.new(%{
        name: "patterns",
        type: :array,
        description: "List of glob patterns",
        items: :string
      })
  """

  @type param_type :: :string | :integer | :number | :boolean | :array | :object

  @type t :: %__MODULE__{
          name: String.t(),
          type: param_type(),
          description: String.t(),
          required: boolean(),
          default: term() | nil,
          items: param_type() | nil,
          properties: [t()] | nil,
          enum: [term()] | nil
        }

  @enforce_keys [:name, :type, :description]
  defstruct [
    :name,
    :type,
    :description,
    :default,
    :items,
    :properties,
    :enum,
    required: true
  ]

  @valid_types [:string, :integer, :number, :boolean, :array, :object]

  @doc """
  Creates a new Param struct with validation.

  ## Parameters

  - `attrs` - A map with the following keys:
    - `:name` (required) - Parameter name as string
    - `:type` (required) - One of: :string, :integer, :number, :boolean, :array, :object
    - `:description` (required) - Human-readable description
    - `:required` (optional) - Whether parameter is required, defaults to true
    - `:default` (optional) - Default value if not provided
    - `:items` (optional) - Item type for array parameters
    - `:properties` (optional) - Nested params for object parameters
    - `:enum` (optional) - List of allowed values

  ## Returns

  - `{:ok, %Param{}}` - Valid parameter
  - `{:error, reason}` - Validation failure

  ## Examples

      iex> Param.new(%{name: "path", type: :string, description: "File path"})
      {:ok, %Param{name: "path", type: :string, description: "File path", required: true}}

      iex> Param.new(%{name: "x", type: :invalid, description: "Bad"})
      {:error, "invalid type :invalid, must be one of: string, integer, number, boolean, array, object"}
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    with {:ok, name} <- validate_name(attrs),
         {:ok, type} <- validate_type(attrs),
         {:ok, description} <- validate_description(attrs),
         {:ok, items} <- validate_items(type, attrs),
         {:ok, properties} <- validate_properties(type, attrs) do
      param = %__MODULE__{
        name: name,
        type: type,
        description: description,
        required: Map.get(attrs, :required, true),
        default: Map.get(attrs, :default),
        items: items,
        properties: properties,
        enum: Map.get(attrs, :enum)
      }

      {:ok, param}
    end
  end

  @doc """
  Creates a new Param struct, raising on validation failure.

  Same as `new/1` but raises `ArgumentError` on failure.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, param} -> param
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Converts a Param to JSON Schema format for LLM function calling.

  ## Returns

  A map representing the parameter in JSON Schema format, suitable for
  inclusion in an OpenAI-compatible function definition.

  ## Examples

      iex> param = %Param{name: "path", type: :string, description: "File path", required: true}
      iex> Param.to_json_schema(param)
      %{type: "string", description: "File path"}
  """
  @spec to_json_schema(t()) :: map()
  def to_json_schema(%__MODULE__{} = param) do
    schema = %{
      type: type_to_json_schema(param.type),
      description: param.description
    }

    schema
    |> maybe_add_items(param)
    |> maybe_add_properties(param)
    |> maybe_add_enum(param)
    |> maybe_add_default(param)
  end

  # ============================================================================
  # Private Validation Functions
  # ============================================================================

  defp validate_name(%{name: name}) when is_binary(name) and byte_size(name) > 0 do
    {:ok, name}
  end

  defp validate_name(%{name: name}) when is_atom(name) and not is_nil(name) do
    {:ok, Atom.to_string(name)}
  end

  defp validate_name(%{name: _}) do
    {:error, "name must be a non-empty string"}
  end

  defp validate_name(_) do
    {:error, "name is required"}
  end

  defp validate_type(%{type: type}) when type in @valid_types do
    {:ok, type}
  end

  defp validate_type(%{type: type}) do
    valid_types_str = @valid_types |> Enum.map_join(", ", &Atom.to_string/1)
    {:error, "invalid type #{inspect(type)}, must be one of: #{valid_types_str}"}
  end

  defp validate_type(_) do
    {:error, "type is required"}
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

  defp validate_items(:array, %{items: items}) when items in @valid_types do
    {:ok, items}
  end

  defp validate_items(:array, %{items: items}) when not is_nil(items) do
    {:error, "items must be a valid type for array parameters"}
  end

  defp validate_items(:array, _) do
    # Default to string items if not specified
    {:ok, :string}
  end

  defp validate_items(_, _) do
    {:ok, nil}
  end

  defp validate_properties(:object, %{properties: props}) when is_list(props) do
    # Validate each nested property is a valid Param
    results =
      Enum.map(props, fn
        %__MODULE__{} = p -> {:ok, p}
        map when is_map(map) -> new(map)
        other -> {:error, "invalid property: #{inspect(other)}"}
      end)

    case Enum.find(results, fn {status, _} -> status == :error end) do
      nil -> {:ok, Enum.map(results, fn {:ok, p} -> p end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_properties(:object, _) do
    {:ok, []}
  end

  defp validate_properties(_, _) do
    {:ok, nil}
  end

  # ============================================================================
  # Private JSON Schema Helpers
  # ============================================================================

  defp type_to_json_schema(:integer), do: "integer"
  defp type_to_json_schema(:number), do: "number"
  defp type_to_json_schema(:boolean), do: "boolean"
  defp type_to_json_schema(:array), do: "array"
  defp type_to_json_schema(:object), do: "object"
  defp type_to_json_schema(_), do: "string"

  defp maybe_add_items(schema, %{type: :array, items: items}) when not is_nil(items) do
    Map.put(schema, :items, %{type: type_to_json_schema(items)})
  end

  defp maybe_add_items(schema, _), do: schema

  defp maybe_add_properties(schema, %{type: :object, properties: props})
       when is_list(props) and length(props) > 0 do
    properties =
      props
      |> Enum.map(fn param -> {param.name, to_json_schema(param)} end)
      |> Map.new()

    required =
      props
      |> Enum.filter(& &1.required)
      |> Enum.map(& &1.name)

    schema
    |> Map.put(:properties, properties)
    |> Map.put(:required, required)
  end

  defp maybe_add_properties(schema, _), do: schema

  defp maybe_add_enum(schema, %{enum: enum}) when is_list(enum) and length(enum) > 0 do
    Map.put(schema, :enum, enum)
  end

  defp maybe_add_enum(schema, _), do: schema

  defp maybe_add_default(schema, %{default: default}) when not is_nil(default) do
    Map.put(schema, :default, default)
  end

  defp maybe_add_default(schema, _), do: schema
end
