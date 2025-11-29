# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Schema do
  @moduledoc false

  alias AshAi.OpenApi

  @doc """
  Generate parameter schema for an action based on its type.

  Dispatches to type-specific schema builders and returns a JSON-compatible map.
  """
  def for_action(resource, action, _tool_def, opts \\ []) do
    action_parameters = opts[:action_parameters]

    case action.type do
      :read ->
        for_read(resource, action, _tool_def = nil, action_parameters)

      :create ->
        for_create(resource, action, _tool_def = nil)

      :update ->
        for_update(resource, action, _tool_def = nil)

      :destroy ->
        for_destroy(resource, action, _tool_def = nil)

      :action ->
        for_generic(resource, action, _tool_def = nil)
    end
  end

  @doc """
  Generate schema for read actions.

  Includes filter, sort, limit, offset, and result_type parameters.
  Optionally filters to only include specific action_parameters.
  """
  def for_read(resource, action, _tool_def, action_parameters \\ nil) do
    input_schema = build_input_schema(resource, action)

    props_with_input =
      if Enum.empty?(input_schema.properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: input_schema.properties,
            required: input_schema.required
          }
        }
      end

    read_properties =
      Map.merge(props_with_input, %{
        filter: build_filter_schema(resource),
        result_type: build_result_type_schema(resource),
        limit: build_limit_schema(action.pagination),
        offset: build_offset_schema(),
        sort: build_sort_schema(resource)
      })

    filtered_properties =
      if action_parameters do
        Map.take(read_properties, action_parameters)
      else
        read_properties
      end

    %{
      type: :object,
      properties: filtered_properties,
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> encode_decode()
  end

  @doc """
  Generate schema for create actions.

  Includes input object with attributes and arguments.
  """
  def for_create(resource, action, _tool_def) do
    input_schema = build_input_schema(resource, action)

    props_with_input =
      if Enum.empty?(input_schema.properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: input_schema.properties,
            required: input_schema.required
          }
        }
      end

    %{
      type: :object,
      properties: props_with_input,
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> encode_decode()
  end

  @doc """
  Generate schema for update actions.

  Includes input object and identity keys (primary key by default).
  """
  def for_update(resource, action, _tool_def) do
    input_schema = build_input_schema(resource, action)

    props_with_input =
      if Enum.empty?(input_schema.properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: input_schema.properties,
            required: input_schema.required
          }
        }
      end

    identity_keys = build_identity_keys_schema(resource, action.type)

    %{
      type: :object,
      properties: Map.merge(props_with_input, identity_keys),
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> encode_decode()
  end

  @doc """
  Generate schema for destroy actions.

  Includes identity keys but no input properties.
  """
  def for_destroy(resource, action, _tool_def) do
    identity_keys = build_identity_keys_schema(resource, action.type)

    %{
      type: :object,
      properties: identity_keys,
      required: [],
      additionalProperties: false
    }
    |> encode_decode()
  end

  @doc """
  Generate schema for generic actions.

  Includes input object with arguments only (no attributes).
  """
  def for_generic(resource, action, _tool_def) do
    input_schema = build_input_schema(resource, action)

    props_with_input =
      if Enum.empty?(input_schema.properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: input_schema.properties,
            required: input_schema.required
          }
        }
      end

    %{
      type: :object,
      properties: props_with_input,
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> encode_decode()
  end

  defp build_input_schema(resource, action) do
    attributes =
      if action.type in [:action, :read] do
        %{}
      else
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.filter(&(&1.name in action.accept && &1.writable?))
        |> Map.new(fn attribute ->
          value = OpenApi.resource_write_attribute_type(attribute, resource, action.type)
          {attribute.name, value}
        end)
      end

    properties =
      action.arguments
      |> Enum.filter(& &1.public?)
      |> Enum.reduce(attributes, fn argument, acc ->
        value = OpenApi.resource_write_attribute_type(argument, resource, :create)
        Map.put(acc, argument.name, value)
      end)

    required = OpenApi.required_write_attributes(resource, action.arguments, action)

    %{properties: properties, required: required}
  end

  defp build_filter_schema(resource) do
    %{
      type: :object,
      description: "Filter results",
      properties:
        Ash.Resource.Info.fields(resource, [:attributes, :aggregates, :calculations])
        |> Enum.filter(&(&1.public? && &1.filterable?))
        |> Map.new(fn field ->
          value = OpenApi.raw_filter_type(field, resource)
          {field.name, value}
        end)
    }
  end

  defp build_result_type_schema(resource) do
    %{
      default: "run_query",
      description: "The type of result to return",
      oneOf: [
        %{
          description:
            "Run the query returning all results, or return a count of results, or check if any results exist",
          enum: ["run_query", "count", "exists"]
        },
        %{
          properties: %{
            aggregate: %{
              type: :string,
              description: "The aggregate function to use",
              enum: ["max", "min", "sum", "avg", "count"]
            },
            field: %{
              type: :string,
              description: "The field to aggregate",
              enum:
                Ash.Resource.Info.fields(resource, [:attributes, :aggregates, :calculations])
                |> Enum.filter(& &1.public?)
                |> Enum.map(& &1.name)
            }
          }
        }
      ]
    }
  end

  defp build_limit_schema(pagination) do
    %{
      type: :integer,
      description: "The maximum number of records to return",
      default:
        case pagination do
          %Ash.Resource.Actions.Read.Pagination{default_limit: limit} when is_integer(limit) ->
            limit

          _ ->
            25
        end
    }
  end

  defp build_offset_schema do
    %{
      type: :integer,
      description: "The number of records to skip",
      default: 0
    }
  end

  defp build_sort_schema(resource) do
    %{
      type: :array,
      items: %{
        type: :object,
        properties:
          %{
            field: %{
              type: :string,
              description: "The field to sort by",
              enum:
                Ash.Resource.Info.fields(resource, [:attributes, :calculations, :aggregates])
                |> Enum.filter(&(&1.public? && &1.sortable?))
                |> Enum.map(& &1.name)
            },
            direction: %{
              type: :string,
              description: "The direction to sort by",
              enum: ["asc", "desc"]
            }
          }
          |> add_input_for_fields(resource)
      }
    }
  end

  defp build_identity_keys_schema(resource, action_type) do
    Map.new(Ash.Resource.Info.primary_key(resource), fn key ->
      value =
        Ash.Resource.Info.attribute(resource, key)
        |> OpenApi.resource_write_attribute_type(resource, action_type)

      {key, value}
    end)
  end

  defp add_input_for_fields(sort_obj, resource) do
    resource
    |> Ash.Resource.Info.fields([:calculations])
    |> Enum.filter(&(&1.public? && &1.sortable? && !Enum.empty?(&1.arguments)))
    |> case do
      [] ->
        sort_obj

      fields ->
        input_for_fields = %{
          type: :object,
          additonalProperties: false,
          properties:
            Map.new(fields, fn field ->
              inputs =
                Enum.map(field.arguments, fn argument ->
                  value = OpenApi.resource_write_attribute_type(argument, resource, :create)
                  {argument.name, value}
                end)

              required =
                Enum.flat_map(field.arguments, fn argument ->
                  if argument.allow_nil?, do: [], else: [argument.name]
                end)

              {field.name,
               %{
                 type: :object,
                 properties: Map.new(inputs),
                 required: required,
                 additionalProperties: false
               }}
            end)
        }

        Map.put(sort_obj, :input, input_for_fields)
    end
  end

  defp encode_decode(schema) do
    schema
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
