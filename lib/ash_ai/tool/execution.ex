# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Execution do
  @moduledoc """
  Executes Ash actions from tool call arguments.

  This module is responsible for taking the arguments passed to a tool
  and executing the corresponding Ash action (read, create, update,
  destroy, or generic action).
  """

  require Ash.Expr

  alias AshAi.Tool.Errors

  defmodule Context do
    @moduledoc """
    Context struct for tool execution.

    Contains all the information needed to execute an Ash action:
    - actor: The actor performing the action
    - tenant: The tenant context
    - context: Additional context passed to the action
    - load: Fields to load on the result
    - domain: The Ash domain
    """
    defstruct [:actor, :tenant, :context, :load, :domain]
  end

  @doc """
  Executes a tool with the given arguments and context.

  Returns `{:ok, json_result, raw_result}` on success or `{:error, json_error}` on failure.
  """
  def run(
        %AshAi.Tool{
          domain: domain,
          resource: resource,
          action: action,
          load: load,
          identity: identity
        },
        arguments,
        context
      ) do
    arguments = arguments || %{}
    input = arguments["input"] || %{}
    opts = build_opts(domain, context)

    exec_ctx = %Context{
      actor: context[:actor],
      tenant: context[:tenant],
      context: context[:context] || %{},
      load: load,
      domain: domain
    }

    try do
      case action.type do
        :read -> run_read(resource, action, arguments, input, opts, exec_ctx)
        :create -> run_create(resource, action, input, opts, exec_ctx)
        :update -> run_update(resource, action, arguments, input, opts, identity, exec_ctx)
        :destroy -> run_destroy(resource, action, arguments, input, opts, identity, exec_ctx)
        :action -> run_generic(resource, action, input, opts, exec_ctx)
      end
    rescue
      error ->
        error = Ash.Error.to_error_class(error)
        {:error, Errors.format(domain, resource, error, action.type)}
    end
  end

  defp build_opts(domain, context) do
    [
      domain: domain,
      actor: context[:actor],
      tenant: context[:tenant],
      context: context[:context] || %{}
    ]
  end

  defp run_read(resource, action, arguments, input, opts, ctx) do
    sort = build_sort(arguments["sort"])
    limit = build_limit(arguments["limit"], action.pagination)

    query =
      resource
      |> Ash.Query.limit(limit)
      |> Ash.Query.offset(arguments["offset"])
      |> apply_sort(sort)
      |> apply_filter(arguments["filter"])
      |> Ash.Query.for_read(action.name, input, opts)

    execute_read(query, action, arguments["result_type"] || "run_query", ctx)
  end

  defp build_sort(sort) when is_list(sort) do
    sort
    |> Enum.map(fn map ->
      case map["direction"] || "asc" do
        "asc" -> map["field"]
        "desc" -> "-#{map["field"]}"
      end
    end)
    |> Enum.join(",")
  end

  defp build_sort(_), do: ""

  defp build_limit(limit, pagination) do
    case {limit, pagination} do
      {limit, false} when is_integer(limit) ->
        limit

      {limit, %Ash.Resource.Actions.Read.Pagination{default_limit: default, max_page_size: max}} ->
        cond do
          is_integer(limit) and is_integer(max) -> min(limit, max)
          is_nil(limit) and is_integer(default) -> default
          true -> 25
        end

      _ ->
        25
    end
  end

  defp apply_sort(query, ""), do: query
  defp apply_sort(query, sort), do: Ash.Query.sort_input(query, sort)

  defp apply_filter(query, nil), do: query
  defp apply_filter(query, filter), do: Ash.Query.filter_input(query, filter)

  defp execute_read(query, action, "run_query", ctx) do
    query
    |> Ash.Actions.Read.unpaginated_read(action, load: ctx.load)
    |> case do
      {:ok, value} -> value
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      resource = query.resource

      result
      |> AshAi.Serializer.serialize_value({:array, resource}, [], ctx.domain, load: ctx.load)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_read(query, _action, "count", ctx) do
    query
    |> Ash.Query.unset([:limit, :offset])
    |> Ash.count()
    |> case do
      {:ok, value} -> value
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> AshAi.Serializer.serialize_value(Ash.Type.Integer, [], ctx.domain)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_read(query, _action, "exists", ctx) do
    query
    |> Ash.exists()
    |> case do
      {:ok, value} -> value
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> AshAi.Serializer.serialize_value(Ash.Type.Boolean, [], ctx.domain)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_read(query, _action, %{"aggregate" => aggregate_kind} = aggregate, ctx) do
    resource = query.resource

    if aggregate_kind not in ["min", "max", "sum", "avg", "count"] do
      raise "invalid aggregate function"
    end

    if !aggregate["field"] do
      raise "missing field argument"
    end

    field = Ash.Resource.Info.field(resource, aggregate["field"])

    if !field || !field.public? do
      raise "no such field"
    end

    aggregate_kind = String.to_existing_atom(aggregate_kind)

    aggregate_struct =
      Ash.Query.Aggregate.new!(resource, :aggregate_result, aggregate_kind,
        field: field.name
      )

    query
    |> Ash.aggregate(aggregate_struct)
    |> case do
      {:ok, value} -> value
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> AshAi.Serializer.serialize_value(
        aggregate_struct.type,
        aggregate_struct.constraints,
        ctx.domain
      )
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp run_create(resource, action, input, opts, ctx) do
    resource
    |> Ash.Changeset.for_create(action.name, input, opts)
    |> Ash.create!(load: ctx.load)
    |> then(fn result ->
      result
      |> AshAi.Serializer.serialize_value(resource, [], ctx.domain, load: ctx.load)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp run_update(resource, action, arguments, input, opts, identity, ctx) do
    filter = identity_filter(identity, resource, arguments)

    resource
    |> Ash.Query.do_filter(filter)
    |> Ash.Query.limit(1)
    |> Ash.bulk_update!(
      action.name,
      input,
      Keyword.merge(opts,
        return_errors?: true,
        notify?: true,
        strategy: [:atomic, :stream, :atomic_batches],
        load: ctx.load,
        allow_stream_with: :full_read,
        return_records?: true
      )
    )
    |> case do
      %Ash.BulkResult{status: :success, records: [result]} ->
        result
        |> AshAi.Serializer.serialize_value(resource, [], ctx.domain, load: ctx.load)
        |> Jason.encode!()
        |> then(&{:ok, &1, result})

      %Ash.BulkResult{status: :success, records: []} ->
        raise Ash.Error.to_error_class(
                Ash.Error.Query.NotFound.exception(primary_key: filter)
              )
    end
  end

  defp run_destroy(resource, action, arguments, input, opts, identity, ctx) do
    filter = identity_filter(identity, resource, arguments)

    resource
    |> Ash.Query.do_filter(filter)
    |> Ash.Query.limit(1)
    |> Ash.bulk_destroy!(
      action.name,
      input,
      Keyword.merge(opts,
        return_errors?: true,
        notify?: true,
        load: ctx.load,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        return_records?: true
      )
    )
    |> case do
      %Ash.BulkResult{status: :success, records: [result]} ->
        result
        |> AshAi.Serializer.serialize_value(resource, [], ctx.domain, load: ctx.load)
        |> Jason.encode!()
        |> then(&{:ok, &1, result})

      %Ash.BulkResult{status: :success, records: []} ->
        raise Ash.Error.to_error_class(
                Ash.Error.Query.NotFound.exception(primary_key: filter)
              )
    end
  end

  defp run_generic(resource, action, input, opts, ctx) do
    resource
    |> Ash.ActionInput.for_action(action.name, input, opts)
    |> Ash.run_action!()
    |> then(fn result ->
      if action.returns do
        result
        |> AshAi.Serializer.serialize_value(action.returns, [], ctx.domain, load: ctx.load)
        |> Jason.encode!()
      else
        "success"
      end
      |> then(&{:ok, &1, result})
    end)
  end

  defp identity_filter(false, _resource, _arguments), do: nil

  defp identity_filter(nil, resource, arguments) do
    resource
    |> Ash.Resource.Info.primary_key()
    |> Enum.reduce(nil, fn key, expr ->
      value = Map.get(arguments, to_string(key))

      if expr do
        Ash.Expr.expr(^expr and ^Ash.Expr.ref(key) == ^value)
      else
        Ash.Expr.expr(^Ash.Expr.ref(key) == ^value)
      end
    end)
  end

  defp identity_filter(identity, resource, arguments) do
    resource
    |> Ash.Resource.Info.identities()
    |> Enum.find(&(&1.name == identity))
    |> Map.get(:keys)
    |> Enum.map(fn key ->
      {key, Map.get(arguments, to_string(key))}
    end)
  end
end
