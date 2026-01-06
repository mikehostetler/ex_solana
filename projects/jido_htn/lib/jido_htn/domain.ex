defmodule Jido.HTN.Domain do
  @moduledoc """
  Represents the domain for Hierarchical Task Network (HTN) planning.

  This module provides functions to create and manipulate an HTN domain,
  including adding tasks, workflows, and callbacks, as well as validating
  the domain structure.
  """

  alias __MODULE__

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(description: "Domain name")
                |> Zoi.optional(),
              tasks:
                Zoi.map(description: "Task registry mapping task names to task definitions")
                |> Zoi.default(%{}),
              allowed_workflows:
                Zoi.map(description: "Allowed workflow modules by name")
                |> Zoi.default(%{}),
              callbacks:
                Zoi.map(description: "Callback functions for domain events")
                |> Zoi.default(%{}),
              root_tasks:
                Zoi.any(description: "Root task names (entry points for planning)")
                |> Zoi.default(MapSet.new())
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  # All delegations to helpers remain unchanged
  # Builder Methods
  defdelegate new(name), to: Domain.BuilderHelpers
  defdelegate compound(builder, name, opts \\ []), to: Domain.BuilderHelpers
  defdelegate primitive(builder, name, task, opts \\ []), to: Domain.BuilderHelpers
  defdelegate callback(builder, name, callback), to: Domain.BuilderHelpers
  defdelegate allow(builder, name, module), to: Domain.BuilderHelpers
  defdelegate replace(builder, name, new_task), to: Domain.BuilderHelpers
  defdelegate root(builder, name), to: Domain.BuilderHelpers

  def build(builder, opts \\ []), do: Domain.BuilderHelpers.build(builder, opts)
  def build!(builder, opts \\ []), do: Domain.BuilderHelpers.build!(builder, opts)

  # Read Methods
  defdelegate get_primitive(domain, name), to: Domain.ReadHelpers
  defdelegate get_compound(domain, name), to: Domain.ReadHelpers
  defdelegate tasks_to_map(domain), to: Domain.ReadHelpers
  defdelegate list_tasks(domain), to: Domain.ReadHelpers
  defdelegate list_allowed_workflows(domain), to: Domain.ReadHelpers
  defdelegate list_callbacks(domain), to: Domain.ReadHelpers

  # Validation Methods
  defdelegate validate(domain), to: Domain.ValidationHelpers
  defdelegate validate(domain, opts), to: Domain.ValidationHelpers
end
