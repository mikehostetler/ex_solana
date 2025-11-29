defmodule JidoHubWeb.IconRail do
  @moduledoc """
  Icon rail navigation component for the dashboard layout.
  Renders a vertical list of icon buttons for primary navigation.
  """
  use Phoenix.Component

  import JidoHubWeb.CoreComponents
  import JidoHubWeb.Layouts, only: [theme_toggle: 1]

  alias JidoHubWeb.Menus

  attr :active_nav, :atom, default: nil
  attr :items, :list, default: nil

  def render(assigns) do
    items = assigns[:items] || Menus.dashboard_items()
    grouped = Menus.group_by_location(items)

    assigns =
      assigns
      |> assign(:top_items, Map.get(grouped, :top, []))
      |> assign(:bottom_items, Map.get(grouped, :bottom, []))

    ~H"""
    <div class="flex flex-col h-full items-center">
      <div class="icon-rail-logo">
        <div class="logo-avatar">Ji</div>
      </div>

      <div class="flex-1 flex flex-col items-center gap-1 pt-4">
        <.nav_item :for={item <- @top_items} item={item} active={@active_nav == item.id} />
      </div>

      <div class="flex flex-col items-center gap-1 pb-4">
        <.theme_toggle icon_only position="top" />
        <.nav_item :for={item <- @bottom_items} item={item} active={@active_nav == item.id} />
      </div>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@item.to}
      class={[
        "icon-rail-btn",
        @active && "active"
      ]}
      title={@item.label}
      aria-label={@item.aria_label || @item.label}
      aria-current={if @active, do: "page"}
    >
      <.icon name={@item.icon} class="w-5 h-5" />
    </.link>
    """
  end
end
