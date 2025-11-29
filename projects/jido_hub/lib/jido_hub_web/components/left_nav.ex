defmodule JidoHubWeb.LeftNav do
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  attr :orgs, :list, default: []
  attr :current_org, :map, default: nil
  attr :active_nav, :atom, default: nil

  def render(assigns) do
    ~H"""
    <div class="dashboard-panel">
      <%!-- Org Switcher --%>
      <div class="px-4 py-3 border-b border-base-300/40">
        <button class="w-full flex items-center justify-between px-3 py-2 rounded-md hover:bg-base-300/30 transition-colors">
          <span class="truncate text-sm font-medium">
            {(@current_org && @current_org.name) || "Select Org"}
          </span>
          <.icon name="hero-chevron-down" class="w-4 h-4 text-base-content/70" />
        </button>
      </div>

      <%!-- Search --%>
      <div class="px-4 py-3 border-b border-base-300/40">
        <input
          type="search"
          placeholder="Search..."
          class="w-full h-9 bg-base-200/60 border border-base-300/30 rounded-md px-3 text-sm placeholder:text-base-content/50 focus:outline-none focus:ring-2 focus:ring-primary/40 focus:border-primary/40 transition-all"
        />
      </div>

      <%!-- Navigation --%>
      <div class="flex-1 overflow-auto">
        <div class="section-label">Browse</div>
        <nav class="nav-list">
          <.link
            navigate="/"
            class="nav-item"
            aria-current={if @active_nav == :workflows, do: "page"}
          >
            <.icon name="hero-bolt" class="w-5 h-5" />
            <span class="text-sm">Workflows</span>
          </.link>

          <.link
            navigate="/agents"
            class="nav-item"
            aria-current={if @active_nav == :agents, do: "page"}
          >
            <.icon name="hero-cpu-chip" class="w-5 h-5" />
            <span class="text-sm">Agents</span>
          </.link>

          <.link
            navigate="/data"
            class="nav-item"
            aria-current={if @active_nav == :data, do: "page"}
          >
            <.icon name="hero-table-cells" class="w-5 h-5" />
            <span class="text-sm">Data</span>
          </.link>
        </nav>
      </div>
    </div>
    """
  end
end
