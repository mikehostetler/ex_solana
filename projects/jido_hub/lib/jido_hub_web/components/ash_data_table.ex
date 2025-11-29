defmodule JidoHubWeb.AshDataTable do
  @moduledoc """
  Ash-aware pagination, filtering, and sorting for DataTable components.

  Provides a unified interface for querying Ash resources with:
  - Pagination (limit/offset and page-based)
  - Multi-field sorting
  - Field-specific filtering with type-aware operators
  - Metadata for building UI controls

  ## Example

      defmodule MyAppWeb.UserLive.Index do
        use MyAppWeb, :live_view
        alias JidoHubWeb.AshDataTable
        
        @impl true
        def handle_params(params, _url, socket) do
          opts = [
            default_limit: 25,
            sortable: [:username, :email, :inserted_at],
            filterable: [:username, :email, :is_suspended, :is_deleted, :inserted_at]
          ]
          
          {records, meta} = AshDataTable.search(User, params, opts, socket.assigns.current_user)
          
          {:noreply, assign(socket, users: records, meta: meta)}
        end
      end
  """

  require Ash.Query

  @default_limit 50
  @max_limit 100

  @doc """
  Search an Ash resource with pagination, sorting, and filtering.

  ## Parameters

    * `queryable` - Ash resource module
    * `params` - Map of query parameters from URL/form
    * `opts` - Keyword list of options:
      * `:default_limit` - Default page size (default: 50)
      * `:sortable` - List of sortable field atoms
      * `:filterable` - List of filterable field atoms
      * `:domain` - Ash domain module (inferred from resource if not provided)
    * `actor` - Current user/actor for authorization (default: nil)

  ## Returns

  `{records, meta}` tuple where:
    * `records` - List of Ash resource structs
    * `meta` - Map with pagination/filter/sort metadata

  ## Params format

      %{
        "limit" => "25",
        "page" => "2",
        "order_by" => ["username", "inserted_at"],
        "order_directions" => ["asc", "desc"],
        "filters" => %{
          "username" => "john",
          "is_suspended" => "false",
          "inserted_at" => %{"from" => "2024-01-01", "to" => "2024-12-31"}
        }
      }
  """
  def search(queryable, params \\ %{}, opts \\ [], actor \\ nil) do
    domain = opts[:domain] || infer_domain(queryable)
    sortable = opts[:sortable] || []
    filterable = opts[:filterable] || []
    default_limit = opts[:default_limit] || @default_limit

    # Parse pagination params
    limit = parse_limit(params["limit"], default_limit)
    page = parse_page(params["page"])
    offset = (page - 1) * limit

    # Build base query
    query = queryable

    # Apply sorting
    {query, order} = apply_sorts(query, params, sortable)

    # Apply filters
    {query, filters} = apply_filters(query, params["filters"], filterable)

    # Execute query with pagination
    result =
      Ash.read!(query,
        domain: domain,
        page: [limit: limit, offset: offset, count: true],
        actor: actor
      )

    records = result.results
    count = result.count || 0
    total_pages = ceil(count / limit)

    # Build metadata
    meta = %{
      count: count,
      limit: limit,
      offset: offset,
      page: page,
      total_pages: total_pages,
      order: order,
      filters: filters
    }

    {records, meta}
  end

  ## Private functions

  defp infer_domain(%Ash.Query{resource: resource}) do
    infer_domain(resource)
  end

  defp infer_domain(queryable) do
    case Ash.Resource.Info.domain(queryable) do
      nil ->
        raise ArgumentError,
              "Could not infer domain for #{inspect(queryable)}. Pass :domain option."

      domain ->
        domain
    end
  end

  defp parse_limit(nil, default), do: min(default, @max_limit)

  defp parse_limit(limit, default) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, _} when num > 0 -> min(num, @max_limit)
      _ -> min(default, @max_limit)
    end
  end

  defp parse_limit(limit, _default) when is_integer(limit) and limit > 0,
    do: min(limit, @max_limit)

  defp parse_limit(_, default), do: min(default, @max_limit)

  defp parse_page(nil), do: 1

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {num, _} when num > 0 -> num
      _ -> 1
    end
  end

  defp parse_page(page) when is_integer(page) and page > 0, do: page
  defp parse_page(_), do: 1

  defp apply_sorts(query, params, sortable) do
    order_by = parse_order_by(params["order_by"])
    order_directions = parse_order_directions(params["order_directions"], length(order_by))

    # Combine and filter to sortable fields
    sorts =
      Enum.zip(order_by, order_directions)
      |> Enum.filter(fn {field, _} -> field in sortable end)

    case sorts do
      [] ->
        {query, []}

      _ ->
        query = Ash.Query.sort(query, sorts)
        {query, sorts}
    end
  end

  defp parse_order_by(nil), do: []

  defp parse_order_by(order_by) when is_list(order_by) do
    Enum.map(order_by, fn
      field when is_binary(field) -> String.to_existing_atom(field)
      field when is_atom(field) -> field
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_order_by(order_by) when is_binary(order_by) do
    parse_order_by([order_by])
  end

  defp parse_order_by(_), do: []

  defp parse_order_directions(nil, count), do: List.duplicate(:asc, count)

  defp parse_order_directions(directions, count) when is_list(directions) do
    parsed =
      Enum.map(directions, fn
        "asc" -> :asc
        "desc" -> :desc
        :asc -> :asc
        :desc -> :desc
        _ -> :asc
      end)

    # Pad with :asc if needed
    if length(parsed) < count do
      parsed ++ List.duplicate(:asc, count - length(parsed))
    else
      Enum.take(parsed, count)
    end
  end

  defp parse_order_directions(direction, count) when is_binary(direction) do
    parse_order_directions([direction], count)
  end

  defp parse_order_directions(_, count), do: List.duplicate(:asc, count)

  defp apply_filters(query, nil, _filterable), do: {query, %{}}

  defp apply_filters(query, filters, filterable) when is_map(filters) do
    active_filters =
      filters
      |> Enum.filter(fn {key, value} ->
        field = parse_filter_field(key)
        field in filterable and not is_nil(value) and value != ""
      end)
      |> Map.new()

    query =
      Enum.reduce(active_filters, query, fn {key, value}, acc ->
        field = parse_filter_field(key)
        apply_filter(acc, field, value)
      end)

    {query, active_filters}
  end

  defp apply_filters(query, _, _), do: {query, %{}}

  defp parse_filter_field(field) when is_binary(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> nil
  end

  defp parse_filter_field(field) when is_atom(field), do: field
  defp parse_filter_field(_), do: nil

  defp apply_filter(query, :id, value) when is_binary(value) do
    Ash.Query.filter(query, id == ^value)
  end

  defp apply_filter(query, :username, value) when is_binary(value) do
    Ash.Query.filter(query, contains(username, ^value))
  end

  defp apply_filter(query, :email, value) when is_binary(value) do
    Ash.Query.filter(query, contains(email, ^value))
  end

  defp apply_filter(query, :slug, value) when is_binary(value) do
    Ash.Query.filter(query, contains(slug, ^value))
  end

  defp apply_filter(query, :name, value) when is_binary(value) do
    Ash.Query.filter(query, contains(name, ^value))
  end

  defp apply_filter(query, :title, value) when is_binary(value) do
    Ash.Query.filter(query, contains(title, ^value))
  end

  defp apply_filter(query, :is_suspended, value) do
    bool_value = parse_boolean(value)
    Ash.Query.filter(query, is_suspended == ^bool_value)
  end

  defp apply_filter(query, :is_deleted, value) do
    bool_value = parse_boolean(value)
    Ash.Query.filter(query, is_deleted == ^bool_value)
  end

  defp apply_filter(query, :is_active, value) do
    bool_value = parse_boolean(value)
    Ash.Query.filter(query, is_active == ^bool_value)
  end

  defp apply_filter(query, :is_admin, value) do
    bool_value = parse_boolean(value)
    Ash.Query.filter(query, is_admin == ^bool_value)
  end

  defp apply_filter(query, :inserted_at, %{"from" => from_date, "to" => to_date}) do
    query =
      if from_date && from_date != "" do
        case parse_date(from_date) do
          {:ok, date} -> Ash.Query.filter(query, inserted_at >= ^date)
          _ -> query
        end
      else
        query
      end

    if to_date && to_date != "" do
      case parse_date(to_date) do
        {:ok, date} ->
          end_datetime = DateTime.new!(date, ~T[23:59:59])
          Ash.Query.filter(query, inserted_at <= ^end_datetime)

        _ ->
          query
      end
    else
      query
    end
  end

  defp apply_filter(query, :updated_at, %{"from" => from_date, "to" => to_date}) do
    query =
      if from_date && from_date != "" do
        case parse_date(from_date) do
          {:ok, date} -> Ash.Query.filter(query, updated_at >= ^date)
          _ -> query
        end
      else
        query
      end

    if to_date && to_date != "" do
      case parse_date(to_date) do
        {:ok, date} ->
          end_datetime = DateTime.new!(date, ~T[23:59:59])
          Ash.Query.filter(query, updated_at <= ^end_datetime)

        _ ->
          query
      end
    else
      query
    end
  end

  defp apply_filter(query, :confirmed_at, %{"from" => from_date, "to" => to_date}) do
    query =
      if from_date && from_date != "" do
        case parse_date(from_date) do
          {:ok, date} -> Ash.Query.filter(query, confirmed_at >= ^date)
          _ -> query
        end
      else
        query
      end

    if to_date && to_date != "" do
      case parse_date(to_date) do
        {:ok, date} ->
          end_datetime = DateTime.new!(date, ~T[23:59:59])
          Ash.Query.filter(query, confirmed_at <= ^end_datetime)

        _ ->
          query
      end
    else
      query
    end
  end

  defp apply_filter(query, field, value)
       when field in [:inserted_at, :updated_at, :confirmed_at] do
    apply_filter(query, field, %{"from" => value, "to" => nil})
  end

  defp apply_filter(query, _field, _value), do: query

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: false

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> {:ok, date}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error
end
