# SPDX-FileCopyrightText: 2024 ash_ai contributors <https://github.com/ash-project/ash_ai/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshAi.Tool.Execution do
  @moduledoc false

  require Ash.Expr

  alias AshAi.Serializer
  alias AshAi.Tool.Errors

  @type exec_ctx :: %{
          actor: any(),
          tenant: any(),
          context: map(),
          tool_callbacks: map(),
          load: list(),
          identity: atom() | false | nil,
          domain: module()
        }

  @type result :: {:ok, String.t(), any()} | {:error, String.t()}

  @doc """
  Executes a tool action with the given arguments and execution context.

  Returns `{:ok, json_string, raw_result}` on success or `{:error, json_string}` on failure.
  """
  @spec run(module(), Ash.Resource.Actions.action(), map(), exec_ctx()) :: result()
  def run(resource, action, arguments, exec_ctx) do
    # Handle nil arguments from LangChain/MCP clients
    arguments = arguments || %{}

    input = arguments["input"] || %{}

    opts = [
      domain: exec_ctx.domain,
      actor: exec_ctx.actor,
      tenant: exec_ctx.tenant,
      context: exec_ctx.context || %{}
    ]

    try do
      case action.type do
        :read ->
          execute_read(resource, action, arguments, input, opts, exec_ctx)

        :create ->
          execute_create(resource, action, input, opts, exec_ctx)

        :update ->
          execute_update(resource, action, arguments, input, opts, exec_ctx)

        :destroy ->
          execute_destroy(resource, action, arguments, input, opts, exec_ctx)

        :action ->
          execute_generic(resource, action, input, opts, exec_ctx)
      end
    rescue
      error ->
        error = Ash.Error.to_error_class(error)

        {:error,
         exec_ctx.domain
         |> Errors.to_json_api_errors(resource, error, action.type)
         |> Errors.serialize_errors()
         |> Jason.encode!()}
    end
  end

  defp execute_read(resource, action, arguments, input, opts, exec_ctx) do
    sort = build_sort(arguments["sort"])

    limit = build_limit(arguments["limit"], action.pagination)

    resource
    |> Ash.Query.limit(limit)
    |> Ash.Query.offset(arguments["offset"])
    |> then(fn query ->
      if sort != "" do
        Ash.Query.sort_input(query, sort)
      else
        query
      end
    end)
    |> then(fn query ->
      if Map.has_key?(arguments, "filter") do
        Ash.Query.filter_input(query, arguments["filter"])
      else
        query
      end
    end)
    |> Ash.Query.for_read(action.name, input, opts)
    |> then(fn query ->
      result_type = arguments["result_type"] || "run_query"

      case result_type do
        "run_query" ->
          execute_run_query(query, action, resource, exec_ctx)

        "count" ->
          execute_count(query, exec_ctx)

        "exists" ->
          execute_exists(query, exec_ctx)

        %{"aggregate" => _} = aggregate ->
          execute_aggregate(query, aggregate, resource, exec_ctx)
      end
    end)
  end

  defp execute_create(resource, action, input, opts, exec_ctx) do
    resource
    |> Ash.Changeset.for_create(action.name, input, opts)
    |> Ash.create!(load: exec_ctx.load)
    |> then(fn result ->
      result
      |> Serializer.serialize_value(resource, [], exec_ctx.domain, load: exec_ctx.load)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_update(resource, action, arguments, input, opts, exec_ctx) do
    filter = identity_filter(exec_ctx.identity, resource, arguments)

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
        load: exec_ctx.load,
        allow_stream_with: :full_read,
        return_records?: true
      )
    )
    |> case do
      %Ash.BulkResult{status: :success, records: [result]} ->
        result
        |> Serializer.serialize_value(resource, [], exec_ctx.domain, load: exec_ctx.load)
        |> Jason.encode!()
        |> then(&{:ok, &1, result})

      %Ash.BulkResult{status: :success, records: []} ->
        raise Ash.Error.to_error_class(Ash.Error.Query.NotFound.exception(primary_key: filter))
    end
  end

  defp execute_destroy(resource, action, arguments, input, opts, exec_ctx) do
    filter = identity_filter(exec_ctx.identity, resource, arguments)

    resource
    |> Ash.Query.do_filter(filter)
    |> Ash.Query.limit(1)
    |> Ash.bulk_destroy!(
      action.name,
      input,
      Keyword.merge(opts,
        return_errors?: true,
        notify?: true,
        load: exec_ctx.load,
        strategy: [:atomic, :stream, :atomic_batches],
        allow_stream_with: :full_read,
        return_records?: true
      )
    )
    |> case do
      %Ash.BulkResult{status: :success, records: [result]} ->
        result
        |> Serializer.serialize_value(resource, [], exec_ctx.domain, load: exec_ctx.load)
        |> Jason.encode!()
        |> then(&{:ok, &1, result})

      %Ash.BulkResult{status: :success, records: []} ->
        raise Ash.Error.to_error_class(Ash.Error.Query.NotFound.exception(primary_key: filter))
    end
  end

  defp execute_generic(resource, action, input, opts, exec_ctx) do
    resource
    |> Ash.ActionInput.for_action(action.name, input, opts)
    |> Ash.run_action!()
    |> then(fn result ->
      if action.returns do
        result
        |> Serializer.serialize_value(action.returns, [], exec_ctx.domain, load: exec_ctx.load)
        |> Jason.encode!()
      else
        "success"
      end
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_run_query(query, action, resource, exec_ctx) do
    query
    |> Ash.Actions.Read.unpaginated_read(action, load: exec_ctx.load)
    |> case do
      {:ok, value} ->
        value

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> Serializer.serialize_value({:array, resource}, [], exec_ctx.domain, load: exec_ctx.load)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_count(query, exec_ctx) do
    query
    |> Ash.Query.unset([:limit, :offset])
    |> Ash.count()
    |> case do
      {:ok, value} ->
        value

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> Serializer.serialize_value(Ash.Type.Integer, [], exec_ctx.domain)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_exists(query, exec_ctx) do
    query
    |> Ash.exists()
    |> case do
      {:ok, value} ->
        value

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> Serializer.serialize_value(Ash.Type.Boolean, [], exec_ctx.domain)
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp execute_aggregate(query, aggregate, resource, exec_ctx) do
    aggregate_kind = aggregate["aggregate"]

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

    aggregate_def =
      Ash.Query.Aggregate.new!(resource, :aggregate_result, aggregate_kind, field: field.name)

    query
    |> Ash.aggregate(aggregate_def)
    |> case do
      {:ok, %{aggregate_result: value}} ->
        value

      {:error, error} ->
        raise Ash.Error.to_error_class(error)
    end
    |> then(fn result ->
      result
      |> Serializer.serialize_value(
        aggregate_def.type,
        aggregate_def.constraints,
        exec_ctx.domain
      )
      |> Jason.encode!()
      |> then(&{:ok, &1, result})
    end)
  end

  defp build_sort(nil), do: ""

  defp build_sort(sort) when is_list(sort) do
    Enum.map_join(sort, ",", fn map ->
      case map["direction"] || "asc" do
        "asc" -> map["field"]
        "desc" -> "-#{map["field"]}"
      end
    end)
  end

  defp build_limit(limit, false) when is_integer(limit), do: limit

  defp build_limit(
         limit,
         %Ash.Resource.Actions.Read.Pagination{
           default_limit: default,
           max_page_size: max
         }
       ) do
    cond do
      is_integer(limit) and is_integer(max) -> min(limit, max)
      is_nil(limit) and is_integer(default) -> default
      true -> 25
    end
  end

  defp build_limit(_, _), do: 25

  defp identity_filter(false, _resource, _arguments) do
    nil
  end

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
