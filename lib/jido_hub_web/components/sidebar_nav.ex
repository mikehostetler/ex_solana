defmodule JidoHubWeb.Components.SidebarNav do
  @moduledoc """
  Shared sidebar navigation component for dashboard and admin layouts.
  Matches the visual style of WorkspaceNav for consistency.
  """
  use Phoenix.Component

  import JidoHubWeb.Components.SidebarComponents
  import JidoHubWeb.CoreComponents

  alias JidoHubWeb.Menus

  attr :items, :list, required: true, doc: "List of MenuItem structs"
  attr :current_path, :string, required: true, doc: "Current request path for active highlighting"
  attr :context, :atom, default: :admin, doc: "Context for the sidebar (:admin, :dashboard, etc.)"

  def sidebar(assigns) do
    assigns = assign(assigns, :groups, Menus.group_by_location(assigns.items))

    ~H"""
    <div class="flex flex-col h-full">
      <.sidebar_dropdown
        name={sidebar_name(@context)}
        icon={sidebar_icon(@context)}
        show_dashboard={@context == :admin}
        show_profile={true}
        show_logout={true}
      />

      <div class="flex-1 overflow-y-auto px-2 py-2">
        <nav class="menu menu-sm p-0 gap-0.5">
          <li :for={item <- Map.get(@groups, :top, [])}>
            <.nav_link item={item} active={Menus.active?(@current_path, item)} />
          </li>
        </nav>

        <div :if={Map.get(@groups, :bottom, []) != []} class="mt-4">
          <nav class="menu menu-sm p-0 gap-0.5">
            <li :for={item <- Map.get(@groups, :bottom, [])}>
              <.nav_link item={item} active={Menus.active?(@current_path, item)} />
            </li>
          </nav>
        </div>
      </div>
    </div>
    """
  end

  attr :item, :map, required: true, doc: "MenuItem struct"
  attr :active, :boolean, default: false

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@item.to}
      class={[
        "flex items-center gap-2 rounded-md",
        @active && "active"
      ]}
      aria-label={@item.aria_label}
    >
      <.icon :if={@item.icon} name={@item.icon} class="w-4 h-4" />
      <span>{@item.label}</span>
    </.link>
    """
  end

  defp sidebar_name(:admin), do: "Admin"
  defp sidebar_name(:dashboard), do: "Dashboard"
  defp sidebar_name(_), do: "Menu"

  defp sidebar_icon(:admin), do: "hero-shield-check"
  defp sidebar_icon(:dashboard), do: nil
  defp sidebar_icon(_), do: nil
end
