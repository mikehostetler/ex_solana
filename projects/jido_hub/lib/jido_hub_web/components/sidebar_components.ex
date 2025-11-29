defmodule JidoHubWeb.Components.SidebarComponents do
  @moduledoc """
  Shared components for sidebar navigation used across Dashboard and Admin layouts.
  Ensures visual consistency and code reusability.
  """
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  @doc """
  Workspace/context dropdown header for sidebars.
  Used in both Dashboard and Admin layouts.
  """
  attr :name, :string, required: true, doc: "Display name (e.g., 'JidoHub', 'Admin')"
  attr :icon, :string, default: nil, doc: "Optional icon name"
  attr :show_logout, :boolean, default: true, doc: "Show logout option"
  attr :show_dashboard, :boolean, default: false, doc: "Show 'Back to Dashboard' option"
  attr :show_admin, :boolean, default: false, doc: "Show 'Admin' option"
  attr :show_profile, :boolean, default: true, doc: "Show profile option"
  attr :class, :string, default: "", doc: "Additional classes"

  def sidebar_dropdown(assigns) do
    ~H"""
    <div class={["flex-shrink-0 p-3", @class]}>
      <details class="dropdown">
        <summary class="btn btn-ghost btn-sm px-2 h-8 min-h-0 w-full justify-start">
          <.icon :if={@icon} name={@icon} class="w-4 h-4" />
          <span class="font-semibold text-sm flex-1 text-left">{@name}</span>
          <.icon name="hero-chevron-down" class="w-3 h-3 opacity-60" />
        </summary>
        <ul class="menu dropdown-content bg-base-200 rounded-box z-50 w-52 p-1.5 shadow mt-2 border border-base-300">
          <li :if={@show_dashboard}>
            <.link
              navigate="/dashboard"
              class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
            >
              <.icon name="hero-home" class="w-4 h-4" />
              <span>Back to Dashboard</span>
            </.link>
          </li>

          <li :if={@show_admin}>
            <.link
              navigate="/admin"
              class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
            >
              <.icon name="hero-shield-check" class="w-4 h-4" />
              <span>Admin</span>
            </.link>
          </li>

          <li :if={@show_profile}>
            <.link
              navigate="/settings/profile"
              class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
            >
              <.icon name="hero-user-circle" class="w-4 h-4" />
              <span>Profile</span>
            </.link>
          </li>

          <li :if={@show_dashboard || @show_admin || @show_profile} class="divider my-1"></li>

          <li :if={@show_logout}>
            <.link
              navigate="/logout"
              class="flex items-center gap-2 text-sm px-3 py-2 rounded-md hover:bg-base-300"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="w-4 h-4" />
              <span>Log out</span>
            </.link>
          </li>
        </ul>
      </details>
    </div>
    """
  end

  @doc """
  Navigation section with optional title for grouping menu items.
  """
  attr :title, :string, default: nil, doc: "Section title"
  attr :class, :string, default: "", doc: "Additional classes"
  slot :inner_block, required: true

  def nav_section(assigns) do
    ~H"""
    <div class={["mt-4", @class]}>
      <div :if={@title} class="px-2 py-1 text-xs font-medium opacity-50">{@title}</div>
      <nav class="menu menu-sm p-0 gap-0.5 mt-1">
        {render_slot(@inner_block)}
      </nav>
    </div>
    """
  end

  @doc """
  Dismissible alert card for sidebar notifications.
  """
  attr :id, :string, required: true
  attr :type, :string, default: "info", values: ["info", "success", "warning", "error"]
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true

  def dismissible_card(assigns) do
    ~H"""
    <div
      role="alert"
      class={[
        "alert p-2.5 gap-2",
        @type == "info" && "alert-info",
        @type == "success" && "alert-success",
        @type == "warning" && "alert-warning",
        @type == "error" && "alert-error"
      ]}
      id={@id}
      phx-hook="DismissCard"
    >
      <.icon name={@icon} class="w-4 h-4 shrink-0" />
      <div class="flex-1 min-w-0">
        <h4 class="text-xs font-semibold leading-tight">{@title}</h4>
        <p class="text-xs leading-tight">{@description}</p>
      </div>
      <button class="btn btn-ghost btn-xs btn-circle" title="Dismiss" data-dismiss>
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  @doc """
  More dropdown menu for navigation items.
  """
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def nav_more_dropdown(assigns) do
    assigns = assign_new(assigns, :id, fn -> "dropdown-#{System.unique_integer([:positive])}" end)

    ~H"""
    <details
      class="dropdown"
      phx-hook="DropdownMenu"
      id={@id}
    >
      <summary class="flex items-center gap-2 rounded-md cursor-pointer list-none">
        <.icon name="hero-ellipsis-horizontal" class="w-4 h-4" />
        <span>More</span>
      </summary>
      <ul class="menu dropdown-content bg-base-200 rounded-box z-50 w-48 p-2 shadow mt-1 border border-base-300">
        {render_slot(@inner_block)}
      </ul>
    </details>
    """
  end
end
