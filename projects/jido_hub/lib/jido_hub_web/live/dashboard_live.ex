defmodule JidoHubWeb.DashboardLive do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.Dashboard.{Commands, MenuSystem, Orgs}
  alias JidoHubWeb.WorkflowLive.IndexComponent

  @impl true
  def mount(_params, _session, socket) do
    orgs = Orgs.sample_list()
    commands = Commands.default()
    active_nav = :workflows
    menu_tree = MenuSystem.menu_tree()
    expanded_items = auto_expand_active_section(menu_tree, active_nav)

    {:ok,
     socket
     |> assign(
       page_title: "Workflows",
       active_nav: active_nav,
       sidebar_open: true,
       show_search_modal: false,
       search_query: "",
       orgs: orgs,
       current_org: Orgs.default(orgs),
       commands: commands,
       menu_tree: menu_tree,
       keyboard_shortcuts: MenuSystem.keyboard_shortcuts(),
       expanded_nav_items: expanded_items,
       keyboard_sequence: "",
       sequence_timeout_ref: nil
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

  @impl true
  def handle_info({:ui_command_execute, cmd}, socket) do
    socket =
      case cmd.action do
        {:navigate, path} ->
          push_navigate(socket, to: path)

        {:live_event, event} ->
          send(self(), {:command_action, event})
          socket

        {:live_event, event, params} ->
          send(self(), {:command_action, event, params})
          socket

        {:js, _js_command} ->
          socket

        nil ->
          put_flash(socket, :info, "Command: #{cmd.label}")
      end

    {:noreply, assign(socket, show_search_modal: false, search_query: "")}
  end

  @impl true
  def handle_info(:close_command_palette, socket) do
    {:noreply, assign(socket, show_search_modal: false, search_query: "")}
  end

  @impl true
  def handle_info({:command_action, action}, socket) do
    socket =
      case action do
        "new_workflow" ->
          put_flash(socket, :info, "Create new workflow")

        "open_search" ->
          assign(socket, show_search_modal: true)

        "toggle_theme" ->
          put_flash(socket, :info, "Theme switcher - use the icon in sidebar")

        "show_help" ->
          put_flash(socket, :info, "Help documentation coming soon")

        _ ->
          put_flash(socket, :info, "Unknown action: #{action}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:command_action, action, _params}, socket) do
    handle_info({:command_action, action}, socket)
  end

  @impl true
  def handle_info({:nav_item_toggled, expanded_items}, socket) do
    {:noreply, assign(socket, :expanded_nav_items, expanded_items)}
  end

  @impl true
  def handle_info(:open_command_palette, socket) do
    {:noreply, assign(socket, show_search_modal: true, search_query: "")}
  end

  @impl true
  def handle_info(:reset_keyboard_sequence, socket) do
    {:noreply, assign(socket, keyboard_sequence: "")}
  end

  @impl true
  def handle_info({:execute_keyboard_command, cmd}, socket) do
    handle_info({:ui_command_execute, cmd}, socket)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Workflows")
  end

  defp auto_expand_active_section(menu_tree, active_nav) do
    menu_tree
    |> Enum.filter(fn item -> !Enum.empty?(item.items) end)
    |> Enum.filter(fn item ->
      Enum.any?(item.items, fn child -> child.id == active_nav end)
    end)
    |> MapSet.new(fn item -> item.id end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <IndexComponent.workflows_content
      show_search_modal={@show_search_modal}
      commands={@commands}
      search_query={@search_query}
      keyboard_shortcuts={@keyboard_shortcuts}
      keyboard_sequence={@keyboard_sequence}
      page_title={@page_title}
      active_nav={@active_nav}
      current_org={@current_org}
      current_user={@current_user}
      orgs={@orgs}
      menu_tree={@menu_tree}
      expanded_nav_items={@expanded_nav_items}
    />
    """
  end
end
