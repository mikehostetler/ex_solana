defmodule JidoHubWeb.Admin.LogLive.Index do
  @moduledoc """
  A live view to view application logs with filtering and live updates.
  """
  use JidoHubWeb, :live_view

  alias JidoHub.Logs

  @page_length 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      JidoHub.Logs.subscribe()
    end

    {:ok,
     assign(socket,
       page_title: "Application Logs",
       logs: [],
       limit: @page_length,
       has_more: false,
       enable_live_logs: false
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    filters = parse_filters(params)
    enable_live_logs = Map.get(params, "enable_live_logs", "false") == "true"
    current_path = URI.parse(uri).path

    socket =
      socket
      |> assign(filters: filters, enable_live_logs: enable_live_logs, current_path: current_path)
      |> load_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"filters" => filter_params}, socket) do
    query_params =
      filter_params
      |> Map.put("enable_live_logs", to_string(socket.assigns.enable_live_logs))
      |> Map.reject(fn {_k, v} -> v == "" end)

    {:noreply, push_patch(socket, to: ~p"/admin/logs?#{query_params}")}
  end

  @impl true
  def handle_event("toggle_live_logs", %{"enable_live_logs" => value}, socket) do
    enable_live_logs = value == "true"

    query_params =
      socket.assigns.filters
      |> Map.put("enable_live_logs", to_string(enable_live_logs))

    {:noreply, push_patch(socket, to: ~p"/admin/logs?#{query_params}")}
  end

  @impl true
  def handle_event("reset_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/logs")}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    socket =
      socket
      |> assign(limit: socket.assigns.limit + @page_length)
      |> load_logs()

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "new-log", payload: log}, socket) do
    socket =
      if socket.assigns.enable_live_logs and matches_filters?(log, socket.assigns.filters) do
        logs = [log | socket.assigns.logs] |> Enum.take(socket.assigns.limit)
        assign(socket, logs: logs)
      else
        socket
      end

    {:noreply, socket}
  end

  defp load_logs(socket) do
    filters = socket.assigns.filters
    limit = socket.assigns.limit + 1

    result = Logs.list_logs(filters, actor: socket.assigns.current_user, limit: limit)

    case result do
      {:ok, logs} ->
        logs = JidoHub.Repo.preload(logs, [:user, :target_user, :organization])
        has_more = length(logs) > socket.assigns.limit
        logs = Enum.take(logs, socket.assigns.limit)
        assign(socket, logs: logs, has_more: has_more)

      {:error, _error} ->
        assign(socket, logs: [], has_more: false)
    end
  end

  defp parse_filters(params) do
    %{}
    |> maybe_put(:action, params["action"])
    |> maybe_put(:user_id, parse_uuid(params["user_id"]))
    |> maybe_put(:org_id, parse_uuid(params["org_id"]))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_uuid(nil), do: nil
  defp parse_uuid(""), do: nil

  defp parse_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp matches_filters?(log, filters) do
    Enum.all?(filters, fn
      {:action, action} -> log.action == action
      {:user_id, user_id} -> log.user_id == user_id or log.target_user_id == user_id
      {:org_id, org_id} -> log.org_id == org_id
      _ -> true
    end)
  end

  defp relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end

  defp format_metadata(metadata) when map_size(metadata) == 0, do: "-"

  defp format_metadata(metadata) do
    metadata
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> String.slice(0, 100)
  end
end
