defmodule Jido.Character.Definition do
  @moduledoc """
  Definition of a character type, used by `use Jido.Character`.

  Stores compile-time configuration for character modules:
  - `module` - The module that defined this character type
  - `extensions` - List of enabled extensions (atoms)
  - `defaults` - Default attribute values for new characters
  - `adapter` - Persistence adapter module
  - `adapter_opts` - Options passed to the persistence adapter
  - `renderer` - Renderer module implementing `Jido.Character.Renderer` behaviour
  - `renderer_opts` - Options passed to the renderer
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(),
              extensions: Zoi.array(Zoi.atom()) |> Zoi.default([]),
              defaults: Zoi.map() |> Zoi.default(%{}),
              adapter: Zoi.atom() |> Zoi.default(Jido.Character.Persistence.Memory),
              adapter_opts: Zoi.list() |> Zoi.default([]),
              renderer: Zoi.atom() |> Zoi.default(Jido.Character.Context.Renderer),
              renderer_opts: Zoi.list() |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Definition"
  def schema, do: @schema

  @doc """
  Creates a new Definition struct from a map, validating with Zoi schema.

  ## Examples

      iex> Jido.Character.Definition.new(%{module: MyApp.Character})
      {:ok, %Jido.Character.Definition{module: MyApp.Character, extensions: [], ...}}

      iex> Jido.Character.Definition.new(%{})
      {:error, _validation_errors}
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  @doc """
  Creates a new Definition struct from a map, raising on validation errors.

  ## Examples

      iex> Jido.Character.Definition.new!(%{module: MyApp.Character})
      %Jido.Character.Definition{module: MyApp.Character, extensions: [], ...}
  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, definition} -> definition
      {:error, reason} -> raise ArgumentError, "Invalid definition: #{inspect(reason)}"
    end
  end
end
