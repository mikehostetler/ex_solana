defmodule JidoHubWeb.DashboardNav do
  @moduledoc """
  Left sidebar navigation for dashboard.
  Shows search, new workflow button, and navigation tree.
  """
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

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
        <!-- Workflows Section -->
        <div class="mb-4">
          <div class="px-2 py-1 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
            Workflows
          </div>
          <ul class="menu menu-sm">
            <li>
              <.link navigate="/" class="gap-2">
                <.icon name="hero-queue-list" class="w-4 h-4" /> All Workflows
              </.link>
            </li>
            <li>
              <.link navigate="/?filter=active" class="gap-2">
                <.icon name="hero-bolt" class="w-4 h-4" /> Active
              </.link>
            </li>
            <li>
              <.link navigate="/?filter=scheduled" class="gap-2">
                <.icon name="hero-clock" class="w-4 h-4" /> Scheduled
              </.link>
            </li>
            <li>
              <.link navigate="/?filter=paused" class="gap-2">
                <.icon name="hero-pause" class="w-4 h-4" /> Paused
              </.link>
            </li>
          </ul>
        </div>
        
    <!-- Views Section -->
        <div class="mb-4">
          <div class="px-2 py-1 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
            Views
          </div>
          <ul class="menu menu-sm">
            <li>
              <.link navigate="/?view=recent" class="gap-2">
                <.icon name="hero-clock" class="w-4 h-4" /> Recently Updated
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </nav>
    """
  end
end
