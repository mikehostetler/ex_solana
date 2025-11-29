defmodule JidoHubWeb.Dashboard.Header do
  @moduledoc """
  Dashboard header component with page title and action buttons.
  """

  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  attr :title, :string, required: true
  attr :active_nav, :atom, required: true
  attr :current_org, :map, required: true
  attr :orgs, :list, required: true

  def header(assigns) do
    ~H"""
    <div class="flex items-center justify-between w-full px-3">
      <div class="flex items-center gap-2">
        <button
          class="btn btn-ghost btn-sm btn-square lg:hidden"
          x-on:click="toggleLeft()"
          title="Toggle sidebar"
        >
          <.icon name="hero-bars-3" class="w-4 h-4" />
        </button>
        <h1 class="text-page-title">{@title}</h1>
      </div>
      <div class="flex items-center gap-3">
        <div class="dropdown dropdown-end">
          <div
            tabindex="0"
            role="button"
            class="btn btn-ghost btn-sm gap-2"
            title="Switch organization"
          >
            <div class="w-5 h-5 rounded bg-primary flex items-center justify-center text-primary-content text-xs font-bold">
              <%= if @current_org do %>
                {String.first(@current_org.name)}
              <% else %>
                ?
              <% end %>
            </div>
            <span class="hidden sm:inline text-sm font-medium">
              {(@current_org && @current_org.name) || "Select Org"}
            </span>
            <.icon name="hero-chevron-down" class="w-3 h-3" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-200 rounded-box z-[1] w-56 p-2 shadow-lg border border-base-content/10 mt-2"
          >
            <%= for org <- @orgs do %>
              <li>
                <a
                  phx-click="switch_org"
                  phx-value-id={org.id}
                  class={[
                    "text-sm",
                    @current_org && @current_org.id == org.id && "active"
                  ]}
                >
                  <div class="w-5 h-5 rounded bg-primary flex items-center justify-center text-primary-content text-xs font-bold">
                    {String.first(org.name)}
                  </div>
                  {org.name}
                </a>
              </li>
            <% end %>
          </ul>
        </div>
        <div class="flex items-center gap-1" phx-update="ignore" id="dashboard-actions">
          <button
            class="btn btn-ghost btn-sm btn-square"
            x-on:click="toggleRight()"
            title="Toggle details panel"
          >
            <.icon name="hero-view-columns" class="w-4 h-4" />
          </button>
          <button
            class="btn btn-ghost btn-sm btn-square"
            x-on:click="toggleBottom()"
            title="Toggle console (Cmd+J)"
          >
            <.icon name="hero-command-line" class="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
    """
  end
end
