defmodule JidoHubWeb.Dashboard.LeftNav do
  @moduledoc """
  Sophisticated left navigation component that renders the menu hierarchy from MenuSystem.
  Replaces hardcoded navigation with a dynamic, data-driven approach.
  """
  use JidoHubWeb, :live_component

  import JidoHubWeb.CoreComponents

  alias JidoHubWeb.Dashboard.MenuSystem.MenuItem

  attr :id, :string, default: "left-nav"
  attr :menu_tree, :list, required: true
  attr :active_nav, :atom, required: true
  attr :expanded_items, :any, required: true
  attr :current_org, :map, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <nav class="flex flex-col h-full">
      <!-- Search -->
      <div class="p-4">
        <label class="input input-sm input-bordered flex items-center gap-2 bg-base-100">
          <.icon name="hero-magnifying-glass" class="w-4 h-4 opacity-70" />
          <input
            type="text"
            placeholder="Search..."
            class="grow text-sm"
            phx-keyup="search"
            phx-debounce="300"
          />
          <kbd class="kbd kbd-xs">⌘K</kbd>
        </label>
      </div>
      
    <!-- New Workflow Button -->
      <div class="px-4 pb-4">
        <button class="btn btn-primary btn-sm w-full gap-2">
          <.icon name="hero-plus" class="w-4 h-4" /> New Workflow
        </button>
      </div>
      
    <!-- Navigation Tree -->
      <div class="flex-1 overflow-y-auto px-2">
        <%= for item <- @menu_tree do %>
          <%= if item.separator do %>
            <div class="my-4 border-t border-base-content/10"></div>
          <% else %>
            {render_menu_item(assigns, item)}
          <% end %>
        <% end %>
      </div>
    </nav>
    """
  end

  @impl true
  def handle_event("toggle_nav_item", %{"id" => id}, socket) do
    id_atom = String.to_existing_atom(id)
    expanded = socket.assigns.expanded_items

    expanded =
      if MapSet.member?(expanded, id_atom) do
        MapSet.delete(expanded, id_atom)
      else
        MapSet.put(expanded, id_atom)
      end

    send(self(), {:nav_item_toggled, expanded})
    {:noreply, assign(socket, :expanded_items, expanded)}
  end

  defp render_menu_item(assigns, %MenuItem{} = item) do
    assigns = assign(assigns, :item, item)

    ~H"""
    <%= cond do %>
      <% !Enum.empty?(@item.items) -> %>
        {render_collapsible_item(assigns, @item)}
      <% @item.to -> %>
        {render_nav_link(assigns, @item)}
      <% @item.action -> %>
        {render_action_link(assigns, @item)}
      <% true -> %>
    <% end %>
    """
  end

  defp render_collapsible_item(assigns, %MenuItem{} = item) do
    assigns = assign(assigns, :collapsible_item, item)
    expanded? = MapSet.member?(assigns.expanded_items, item.id)
    is_active? = child_active?(assigns.active_nav, item)
    assigns = assign(assigns, :expanded, expanded? || is_active?)
    assigns = assign(assigns, :is_active, is_active?)

    ~H"""
    <div class="mb-2">
      <button
        type="button"
        class={[
          "w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors",
          "hover:bg-base-200",
          @is_active && "bg-base-200"
        ]}
        phx-click="toggle_nav_item"
        phx-value-id={@collapsible_item.id}
        phx-target={@myself}
      >
        <%= if @collapsible_item.icon do %>
          <.icon name={@collapsible_item.icon} class="w-4 h-4" />
        <% end %>
        <span class="flex-1 text-left">{@collapsible_item.label}</span>
        <%= if @collapsible_item.badge do %>
          <span class="badge badge-sm badge-primary">{@collapsible_item.badge}</span>
        <% end %>
        <.icon
          name="hero-chevron-down"
          class={
            if @expanded,
              do: "w-4 h-4 transition-transform duration-200 rotate-180",
              else: "w-4 h-4 transition-transform duration-200"
          }
        />
      </button>

      <div class={[
        "overflow-hidden transition-all duration-200 ease-in-out",
        @expanded && "max-h-96 opacity-100",
        !@expanded && "max-h-0 opacity-0"
      ]}>
        <ul class="menu menu-sm ml-6 mt-1 space-y-1">
          <%= for child <- @collapsible_item.items do %>
            {render_menu_item(assigns, child)}
          <% end %>
        </ul>
      </div>
    </div>
    """
  end

  defp child_active?(active_nav, %MenuItem{items: items}) do
    Enum.any?(items, fn child -> child.id == active_nav end)
  end

  defp render_nav_link(assigns, %MenuItem{} = item) do
    assigns = assign(assigns, :link_item, item)
    active? = assigns.active_nav == item.id
    assigns = assign(assigns, :is_active, active?)

    ~H"""
    <li>
      <.link patch={@link_item.to} class={["gap-2", @is_active && "active"]}>
        <%= if @link_item.icon do %>
          <.icon name={@link_item.icon} class="w-4 h-4" />
        <% end %>
        {@link_item.label}
        <%= if @link_item.badge do %>
          <span class="badge badge-sm badge-primary">{@link_item.badge}</span>
        <% end %>
      </.link>
    </li>
    """
  end

  defp render_action_link(assigns, %MenuItem{} = item) do
    assigns = assign(assigns, :action_item, item)

    ~H"""
    <li>
      <a class="gap-2" phx-click={@action_item.action}>
        <%= if @action_item.icon do %>
          <.icon name={@action_item.icon} class="w-4 h-4" />
        <% end %>
        {@action_item.label}
        <%= if @action_item.badge do %>
          <span class="badge badge-sm badge-primary">{@action_item.badge}</span>
        <% end %>
      </a>
    </li>
    """
  end
end
