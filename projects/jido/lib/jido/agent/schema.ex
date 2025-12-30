defmodule Jido.Agent.Schema do
  @moduledoc false
  # Utilities for merging agent and skill schemas.
  # Handles Zoi schema introspection and merging.

  alias Jido.Skill.Spec

  @doc """
  Merges the agent's base schema with skill schemas.

  Each skill's schema is nested under its `state_key`.
  Returns a Zoi object schema with base fields + skill fields.

  ## Examples

      base = Zoi.object(%{mode: Zoi.atom()})
      skills = [%Spec{state_key: :calc, schema: Zoi.object(%{x: Zoi.integer()})}]
      
      # Returns:
      # Zoi.object(%{
      #   mode: Zoi.atom(),
      #   calc: Zoi.object(%{x: Zoi.integer()})
      # })
  """
  @spec merge_with_skills(any(), [Spec.t()]) :: any()
  def merge_with_skills(nil, []), do: nil
  def merge_with_skills(base_schema, []), do: base_schema

  def merge_with_skills(base_schema, skill_specs) when is_list(skill_specs) do
    skill_fields =
      skill_specs
      |> Enum.filter(& &1.schema)
      |> Enum.map(fn spec -> {spec.state_key, spec.schema} end)
      |> Map.new()

    case base_schema do
      nil ->
        if map_size(skill_fields) == 0 do
          nil
        else
          Zoi.object(skill_fields)
        end

      base ->
        base_fields = extract_fields(base)
        Zoi.object(Map.merge(base_fields, skill_fields))
    end
  end

  @doc """
  Extracts known keys from a Zoi schema.

  Returns a list of atom keys for collision detection.
  """
  @spec known_keys(any()) :: [atom()]
  def known_keys(nil), do: []

  def known_keys(%{__struct__: Zoi.Types.Object, fields: fields}) when is_map(fields) do
    Map.keys(fields)
  end

  def known_keys(%{__struct__: Zoi.Types.Object, fields: fields}) when is_list(fields) do
    Keyword.keys(fields)
  end

  def known_keys(%{__struct__: Zoi.Types.Map, fields: fields}) when is_map(fields) do
    Map.keys(fields)
  end

  def known_keys(%{__struct__: Zoi.Types.Map, fields: fields}) when is_list(fields) do
    Keyword.keys(fields)
  end

  def known_keys(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_map(fields) do
    Map.keys(fields)
  end

  def known_keys(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_list(fields) do
    Keyword.keys(fields)
  end

  def known_keys(_), do: []

  @doc """
  Extracts default values from a Zoi schema.

  Walks the schema and extracts defaults from fields.
  Returns a map with default values.
  """
  @spec defaults_from_zoi_schema(any()) :: map()
  def defaults_from_zoi_schema(nil), do: %{}

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Object, fields: fields})
      when is_map(fields) do
    extract_defaults_from_fields(fields)
  end

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Object, fields: fields})
      when is_list(fields) do
    fields |> Map.new() |> extract_defaults_from_fields()
  end

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Map, fields: fields})
      when is_map(fields) do
    extract_defaults_from_fields(fields)
  end

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Map, fields: fields})
      when is_list(fields) do
    fields |> Map.new() |> extract_defaults_from_fields()
  end

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Struct, fields: fields})
      when is_map(fields) do
    extract_defaults_from_fields(fields)
  end

  def defaults_from_zoi_schema(%{__struct__: Zoi.Types.Struct, fields: fields})
      when is_list(fields) do
    fields |> Map.new() |> extract_defaults_from_fields()
  end

  def defaults_from_zoi_schema(_), do: %{}

  # Private helpers

  defp extract_fields(%{__struct__: Zoi.Types.Object, fields: fields}) when is_map(fields) do
    fields
  end

  defp extract_fields(%{__struct__: Zoi.Types.Object, fields: fields}) when is_list(fields) do
    Map.new(fields)
  end

  defp extract_fields(%{__struct__: Zoi.Types.Map, fields: fields}) when is_map(fields) do
    fields
  end

  defp extract_fields(%{__struct__: Zoi.Types.Map, fields: fields}) when is_list(fields) do
    Map.new(fields)
  end

  defp extract_fields(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_map(fields) do
    fields
  end

  defp extract_fields(%{__struct__: Zoi.Types.Struct, fields: fields}) when is_list(fields) do
    Map.new(fields)
  end

  defp extract_fields(_), do: %{}

  defp extract_defaults_from_fields(fields) when is_map(fields) do
    Enum.reduce(fields, %{}, fn {key, field_schema}, acc ->
      case extract_default(field_schema) do
        {:ok, default} -> Map.put(acc, key, default)
        :none -> acc
      end
    end)
  end

  defp extract_default(%{__struct__: Zoi.Types.Default, value: value}), do: {:ok, value}
  defp extract_default(_), do: :none
end
