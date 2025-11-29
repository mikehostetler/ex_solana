defmodule JidoHubWeb.AdminChartDataHelper do
  @moduledoc false
  import Ecto.Query, warn: false

  alias JidoHub.Billing
  alias JidoHub.Repo

  def get_active_subscriptions do
    subscriptions =
      from(s in Billing.list_subscriptions_query(), where: s.status == "active")
      |> Repo.all()
      |> Enum.group_by(& &1.plan_id)

    labels = Enum.map(subscriptions, fn {plan_id, _} -> plan_id end)

    data =
      Enum.map(subscriptions, fn {_plan_id, subscriptions} ->
        Enum.count(subscriptions)
      end)

    label_count = Enum.count(labels)

    colors =
      ~w(0ea5e9 22c55e f59e0b ef4444 8b5cf6 06b6d4 84cc16 14b8a6)
      |> Stream.cycle()
      |> Enum.take(label_count)
      |> Enum.map(&"##{&1}")

    datasets = [
      %{
        data: data,
        backgroundColor: colors,
        hoverBackgroundColor: colors,
        borderColor: "transparent"
      }
    ]

    %{
      labels: labels,
      datasets: datasets,
      empty?: empty?(datasets)
    }
  end

  def get_this_month_and_last_months_data(query_or_resource) do
    {resource, filters} = normalize_to_resource_and_filters(query_or_resource)
    table = get_table_name(resource)

    beginning_of_month = beginning_of_month(DateTime.utc_now())
    end_of_month = end_of_month(DateTime.utc_now())

    {this_months_data, this_months_labels} =
      get_insertion_counts_by_day(table, filters, beginning_of_month, end_of_month)

    last_month_start = shift_months(DateTime.utc_now(), -1) |> beginning_of_month()
    last_month_end = shift_months(DateTime.utc_now(), -1) |> end_of_month()

    {last_months_data, _} =
      get_insertion_counts_by_day(table, filters, last_month_start, last_month_end)

    datasets = [
      %{
        data: this_months_data,
        labels: this_months_labels,
        borderColor: "#10b981"
      },
      %{
        data: last_months_data,
        borderColor: "rgb(0 0 0 / 15%)"
      }
    ]

    total_for_this_month = Enum.reduce(this_months_data, 0, fn x, acc -> (x || 0) + acc end)
    total_for_last_month = Enum.reduce(last_months_data, 0, fn x, acc -> (x || 0) + acc end)

    day_of_the_month = DateTime.utc_now().day

    total_at_this_day_last_month =
      last_months_data
      |> Enum.with_index()
      |> Enum.reduce(0, fn {x, i}, acc ->
        if i <= day_of_the_month, do: acc + x, else: acc
      end)

    percentage_change =
      if total_at_this_day_last_month > 0 do
        increase = total_for_this_month - total_at_this_day_last_month
        round(increase / total_at_this_day_last_month * 100)
      else
        if total_for_this_month > 0 do
          100
        else
          0
        end
      end

    %{
      labels: this_months_labels,
      datasets: datasets,
      empty?: empty?(datasets),
      total_for_this_month: total_for_this_month,
      total_for_last_month: total_for_last_month,
      percentage_change: percentage_change
    }
  end

  def get_this_year_and_last_years_data(query_or_resource) do
    {resource, filters} = normalize_to_resource_and_filters(query_or_resource)
    table = get_table_name(resource)

    beginning_of_year = beginning_of_year(DateTime.utc_now())
    end_of_year = end_of_year(DateTime.utc_now())

    {this_years_data, this_years_labels} =
      get_insertion_counts_by_month(table, filters, beginning_of_year, end_of_year)

    last_year_start = shift_years(DateTime.utc_now(), -1) |> beginning_of_year()
    last_year_end = shift_years(DateTime.utc_now(), -1) |> end_of_year()

    {last_years_data, _} =
      get_insertion_counts_by_month(table, filters, last_year_start, last_year_end)

    datasets = [
      %{
        data: this_years_data,
        label: "This year",
        backgroundColor: "rgba(3, 105, 161, 0.9)",
        hoverBackgroundColor: "rgba(3, 105, 161, 1)",
        barPercentage: 0.66,
        categoryPercentage: 0.66,
        borderWidth: 2,
        borderColor: "rgba(3, 105, 161, 0.9)",
        useGradient: true,
        fill: true,
        gradientFrom: "rgba(3, 105, 161, 0.9)",
        gradientTo: "rgba(3, 105, 161, 0)"
      },
      %{
        data: last_years_data,
        label: "Last year",
        backgroundColor: "rgba(125, 211, 252, 0.9)",
        hoverBackgroundColor: "rgba(125, 211, 252, 1)",
        barPercentage: 0.66,
        categoryPercentage: 0.66,
        borderWidth: 2,
        borderColor: "rgba(125, 211, 252, 0.9)",
        useGradient: true,
        fill: true,
        gradientFrom: "rgba(125, 211, 252, 0.9)",
        gradientTo: "rgba(125, 211, 252, 0)"
      }
    ]

    total_for_this_year = Enum.reduce(this_years_data, 0, fn x, acc -> (x || 0) + acc end)
    total_for_last_year = Enum.reduce(last_years_data, 0, fn x, acc -> (x || 0) + acc end)

    month_of_the_year = DateTime.utc_now().month

    total_at_this_month_last_year =
      last_years_data
      |> Enum.with_index()
      |> Enum.reduce(0, fn {x, i}, acc ->
        if i <= month_of_the_year, do: acc + x, else: acc
      end)

    percentage_change =
      if total_at_this_month_last_year > 0 do
        increase = total_for_this_year - total_at_this_month_last_year
        round(increase / total_at_this_month_last_year * 100)
      else
        if total_for_this_year > 0 do
          100
        else
          0
        end
      end

    %{
      labels: this_years_labels,
      datasets: datasets,
      empty?: empty?(datasets),
      total_for_this_year: total_for_this_year,
      total_for_last_year: total_for_last_year,
      percentage_change: percentage_change
    }
  end

  defp normalize_to_resource_and_filters(%Ash.Query{resource: resource, filter: filter}) do
    filters = extract_filters(filter)
    {resource, filters}
  end

  defp normalize_to_resource_and_filters(resource) when is_atom(resource) do
    {resource, []}
  end

  defp extract_filters(nil), do: []

  defp extract_filters(filter) do
    case filter do
      %Ash.Filter{expression: expression} ->
        extract_expression_filters(expression)

      _ ->
        []
    end
  end

  defp extract_expression_filters(expression) when is_struct(expression) do
    case expression do
      %Ash.Query.BooleanExpression{op: :and, left: left, right: right} ->
        extract_expression_filters(left) ++ extract_expression_filters(right)

      %Ash.Query.Ref{attribute: %{name: name}, relationship_path: []} ->
        [{name, :exists}]

      %{
        __struct__: Ash.Query.Function.Eq,
        arguments: [%Ash.Query.Ref{attribute: %{name: name}}, value]
      } ->
        [{name, value}]

      _ ->
        []
    end
  end

  defp extract_expression_filters(_), do: []

  defp get_table_name(resource) do
    AshPostgres.DataLayer.Info.table(resource)
  end

  defp get_insertion_counts_by_day(table, filters, start_date, end_date) do
    daily_counts =
      insertion_counts_grouped_by_day(table, filters, start_date, end_date) |> Repo.all()

    number_of_days = Date.diff(DateTime.to_date(end_date), DateTime.to_date(start_date))

    data =
      Enum.map(0..number_of_days, fn day ->
        day_as_date = DateTime.to_date(shift_days(start_date, day))

        case Enum.find(daily_counts, fn {daily_count_date, _count} ->
               daily_count_date == day_as_date
             end) do
          nil ->
            if Date.before?(day_as_date, DateTime.to_date(DateTime.utc_now())), do: 0

          {_, count} ->
            count
        end
      end)

    labels =
      Enum.map(0..number_of_days, fn day ->
        date = DateTime.to_date(shift_days(start_date, day))
        "Day #{date.day}/#{number_of_days}"
      end)

    {data, labels}
  end

  defp get_insertion_counts_by_month(table, filters, start_date, end_date) do
    monthly_counts =
      insertion_counts_grouped_by_month(table, filters, start_date, end_date) |> Repo.all()

    number_of_months = 11

    data =
      Enum.map(0..number_of_months, fn month ->
        month_as_date = DateTime.to_date(shift_months(start_date, month))

        case Enum.find(monthly_counts, fn {_, monthly_count_date, _count} ->
               monthly_count_date == month_as_date
             end) do
          nil ->
            if Date.before?(month_as_date, DateTime.to_date(DateTime.utc_now())), do: 0

          {_, _, count} ->
            count
        end
      end)

    labels =
      Enum.map(0..number_of_months, fn month ->
        date = DateTime.to_date(shift_months(start_date, month))
        "#{String.pad_leading(to_string(date.month), 2, "0")}-#{date.year}"
      end)

    {data, labels}
  end

  defp insertion_counts_grouped_by_day(table, filters, start_date, end_date) do
    base_query =
      from u in table,
        select: {
          fragment("date_trunc('day', ?)::date", u.inserted_at),
          count(u.id)
        },
        group_by: fragment("date_trunc('day', ?)::date", u.inserted_at),
        where: u.inserted_at >= ^start_date,
        where: u.inserted_at <= ^end_date,
        order_by: [asc: fragment("date_trunc('day', ?)::date", u.inserted_at)]

    apply_filters(base_query, filters)
  end

  defp insertion_counts_grouped_by_month(table, filters, start_date, end_date) do
    base_query =
      from u in table,
        select: {
          fragment("date_trunc('year', ?)::date", u.inserted_at),
          fragment("date_trunc('month', ?)::date", u.inserted_at),
          count(u.id)
        },
        group_by: [
          fragment("date_trunc('year', ?)::date", u.inserted_at),
          fragment("date_trunc('month', ?)::date", u.inserted_at)
        ],
        where: u.inserted_at >= ^start_date,
        where: u.inserted_at <= ^end_date,
        order_by: [asc: fragment("date_trunc('month', ?)::date", u.inserted_at)]

    apply_filters(base_query, filters)
  end

  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{field, value} | rest]) do
    filtered_query =
      case value do
        false -> where(query, [u], field(u, ^field) == false)
        true -> where(query, [u], field(u, ^field) == true)
        _ -> query
      end

    apply_filters(filtered_query, rest)
  end

  defp empty?(datasets) when is_list(datasets) do
    Enum.empty?(datasets) or
      Enum.all?(datasets, fn dataset ->
        Enum.empty?(dataset.data) or Enum.all?(dataset.data, fn value -> value in [nil, 0] end)
      end)
  end

  defp empty?(_), do: true

  defp beginning_of_month(datetime) do
    date = DateTime.to_date(datetime)
    {:ok, dt} = DateTime.new(Date.new!(date.year, date.month, 1), ~T[00:00:00], "Etc/UTC")
    dt
  end

  defp end_of_month(datetime) do
    date = DateTime.to_date(datetime)
    last_day = Date.days_in_month(date)
    {:ok, dt} = DateTime.new(Date.new!(date.year, date.month, last_day), ~T[23:59:59], "Etc/UTC")
    dt
  end

  defp beginning_of_year(datetime) do
    date = DateTime.to_date(datetime)
    {:ok, dt} = DateTime.new(Date.new!(date.year, 1, 1), ~T[00:00:00], "Etc/UTC")
    dt
  end

  defp end_of_year(datetime) do
    date = DateTime.to_date(datetime)
    {:ok, dt} = DateTime.new(Date.new!(date.year, 12, 31), ~T[23:59:59], "Etc/UTC")
    dt
  end

  defp shift_days(datetime, days) do
    datetime
    |> DateTime.to_date()
    |> Date.add(days)
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp shift_months(datetime, months) do
    date = DateTime.to_date(datetime)
    new_month = date.month + months

    {year_offset, adjusted_month} =
      cond do
        new_month > 12 -> {div(new_month - 1, 12), rem(new_month - 1, 12) + 1}
        new_month < 1 -> {div(new_month - 12, 12), rem(new_month - 12, 12) + 12}
        true -> {0, new_month}
      end

    new_year = date.year + year_offset
    last_day_of_new_month = Date.days_in_month(Date.new!(new_year, adjusted_month, 1))
    new_day = min(date.day, last_day_of_new_month)

    Date.new!(new_year, adjusted_month, new_day)
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp shift_years(datetime, years) do
    date = DateTime.to_date(datetime)
    new_year = date.year + years

    new_day =
      if date.month == 2 and date.day == 29 and not Date.leap_year?(Date.new!(new_year, 1, 1)) do
        28
      else
        date.day
      end

    Date.new!(new_year, date.month, new_day)
    |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end
end
