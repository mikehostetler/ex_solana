defmodule JidoHubWeb.WorkflowLive.Index do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.Dashboard.{BottomConsole, Commands, Orgs}

  @impl true
  def mount(_params, _session, socket) do
    orgs = Orgs.sample_list()
    commands = Commands.default()

    {:ok,
     assign(socket,
       active_nav: :workflows,
       sidebar_open: true,
       show_search_modal: false,
       search_query: "",
       orgs: orgs,
       current_org: Orgs.default(orgs),
       commands: commands
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, sidebar_open: !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("open_search", _params, socket) do
    {:noreply, assign(socket, show_search_modal: true)}
  end

  @impl true
  def handle_event("toggle_command_palette", _params, socket) do
    new_value = !socket.assigns.show_search_modal

    IO.puts(
      "[WorkflowLive] Toggling command palette: #{socket.assigns.show_search_modal} -> #{new_value}"
    )

    socket =
      socket
      |> assign(show_search_modal: new_value)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_search", _params, socket) do
    {:noreply, assign(socket, show_search_modal: false, search_query: "")}
  end

  @impl true
  def handle_event("close_command_palette", _params, socket) do
    {:noreply, assign(socket, show_search_modal: false, search_query: "")}
  end

  @impl true
  def handle_event("search_filter", %{"value" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  @impl true
  def handle_event("execute_command", %{"id" => cmd_id}, socket) do
    socket =
      case cmd_id do
        "new-workflow" ->
          socket
          |> put_flash(:info, "Create new workflow action")

        "search" ->
          socket

        "settings" ->
          push_navigate(socket, to: "/settings")

        "theme" ->
          socket
          |> put_flash(:info, "Theme switcher - use the icon in sidebar")

        "help" ->
          socket
          |> put_flash(:info, "Help documentation coming soon")

        _ ->
          socket
      end

    {:noreply, assign(socket, show_search_modal: false, search_query: "")}
  end

  @impl true
  def handle_event("switch_org", %{"id" => id}, socket) do
    org = Orgs.find_by_id(socket.assigns.orgs, id)

    {:noreply, assign(socket, :current_org, org)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "UI Showcase")
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Workflow ##{id}")
    |> assign(:workflow_id, id)
  end
end
