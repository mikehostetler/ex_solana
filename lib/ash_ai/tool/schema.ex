# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Schema do
  @moduledoc """
  Generates JSON schemas for tool parameters based on Ash action types.

  This module is responsible for building the parameter schema that describes
  what arguments a tool accepts. The schema is used by LLMs to understand
  how to call tools correctly.
  """

  @doc """
  Generates a JSON schema for the given tool definition.
  """
  def for_tool(%AshAi.Tool{
        domain: domain,
        resource: resource,
        action: action,
        action_parameters: action_parameters
      }) do
    for_action(domain, resource, action, action_parameters)
  end

  @doc """
  Generates a JSON schema for the given action.
  """
  def for_action(_domain, resource, action, action_parameters \\ nil) do
    attributes =
      if action.type in [:action, :read] do
        %{}
      else
        resource
        |> Ash.Resource.Info.attributes()
        |> Enum.filter(&(&1.name in action.accept && &1.writable?))
        |> Map.new(fn attribute ->
          value =
            AshAi.OpenApi.resource_write_attribute_type(
              attribute,
              resource,
              action.type
            )

          {attribute.name, value}
        end)
      end

    properties =
      action.arguments
      |> Enum.filter(& &1.public?)
      |> Enum.reduce(attributes, fn argument, attributes ->
        value =
          AshAi.OpenApi.resource_write_attribute_type(argument, resource, :create)

        Map.put(
          attributes,
          argument.name,
          value
        )
      end)

    props_with_input =
      if Enum.empty?(properties) do
        %{}
      else
        %{
          input: %{
            type: :object,
            properties: properties,
            additionalProperties: false,
            required: AshAi.OpenApi.required_write_attributes(resource, action.arguments, action)
          }
        }
      end

    %{
      type: :object,
      properties:
        add_action_specific_properties(props_with_input, resource, action, action_parameters),
      required: Map.keys(props_with_input),
      additionalProperties: false
    }
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp add_action_specific_properties(
         properties,
         resource,
         %{type: :read, pagination: pagination},
         action_parameters
       ) do
    Map.merge(properties, %{
      filter: %{
        type: :object,
        description: "Filter results",
        properties:
          Ash.Resource.Info.fields(resource, [:attributes, :aggregates, :calculations])
          |> Enum.filter(&(&1.public? && &1.filterable?))
          |> Map.new(fn field ->
            value =
              AshAi.OpenApi.raw_filter_type(field, resource)

            {field.name, value}
          end)
      },
      result_type: %{
        default: "run_query",
        description: "The type of result to return",
        oneOf: [
          %{
            description:
              "Run the query returning all results, or return a count of results, or check if any results exist",
            enum: [
              "run_query",
              "count",
              "exists"
            ]
          },
          %{
            properties: %{
              aggregate: %{
                type: :string,
                description: "The aggregate function to use",
                enum: [:max, :min, :sum, :avg, :count]
              },
              field: %{
                type: :string,
                description: "The field to aggregate",
                enum:
                  Ash.Resource.Info.fields(resource, [
                    :attributes,
                    :aggregates,
                    :calculations
                  ])
                  |> Enum.filter(& &1.public?)
                  |> Enum.map(& &1.name)
              }
            }
          }
        ]
      },
      limit: %{
        type: :integer,
        description: "The maximum number of records to return",
        default:
          case pagination do
            %Ash.Resource.Actions.Read.Pagination{default_limit: limit} when is_integer(limit) ->
              limit

            _ ->
              25
          end
      },
      offset: %{
        type: :integer,
        description: "The number of records to skip",
        default: 0
      },
      sort: %{
        type: :array,
        items: %{
          type: :object,
          properties:
            %{
              field: %{
                type: :string,
                description: "The field to sort by",
                enum:
                  Ash.Resource.Info.fields(resource, [
                    :attributes,
                    :calculations,
                    :aggregates
                  ])
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
    })
    |> then(fn map ->
      if action_parameters do
        Map.take(map, action_parameters)
      else
        map
      end
    end)
  end

  defp add_action_specific_properties(properties, resource, %{type: type}, _action_parameters)
       when type in [:update, :destroy] do
    pkey =
      Map.new(Ash.Resource.Info.primary_key(resource), fn key ->
        value =
          Ash.Resource.Info.attribute(resource, key)
          |> AshAi.OpenApi.resource_write_attribute_type(resource, type)

        {key, value}
      end)

    Map.merge(properties, pkey)
  end

  defp add_action_specific_properties(properties, _resource, _action, _action_parameters),
    do: properties

  defp add_input_for_fields(sort_obj, resource) do
    resource
    |> Ash.Resource.Info.fields([
      :calculations
    ])
    |> Enum.filter(&(&1.public? && &1.sortable? && !Enum.empty?(&1.arguments)))
    |> case do
      [] ->
        sort_obj

      fields ->
        input_for_fields =
          %{
            type: :object,
            additonalProperties: false,
            properties:
              Map.new(fields, fn field ->
                inputs =
                  Enum.map(field.arguments, fn argument ->
                    value =
                      AshAi.OpenApi.resource_write_attribute_type(
                        argument,
                        resource,
                        :create
                      )

                    {argument.name, value}
                  end)

                required =
                  Enum.flat_map(field.arguments, fn argument ->
                    if argument.allow_nil? do
                      []
                    else
                      [argument.name]
                    end
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

        Map.put(sort_obj, :input_for_fields, input_for_fields)
    end
  end
end
