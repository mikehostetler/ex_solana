defmodule JidoHubWeb.Dashboard.TopNav do
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  attr :title, :string, default: nil
  attr :class, :string, default: nil
  attr :show_console_toggle, :boolean, default: true
  attr :show_sidebar_toggle, :boolean, default: true
  attr :show_left_toggle, :boolean, default: true

  slot :left
  slot :center
  slot :actions

  def top_nav(assigns) do
    ~H"""
    <div class={["flex items-center justify-between w-full px-3", @class]}>
      <div class="flex items-center gap-2 flex-1">
        <%= if @show_left_toggle do %>
          <button
            class="btn btn-ghost btn-sm btn-square lg:hidden"
            x-on:click="toggleLeft()"
            title="Toggle sidebar"
          >
            <.icon name="hero-bars-3" class="w-4 h-4" />
          </button>
        <% end %>

        <%= if @left != [] do %>
          {render_slot(@left)}
        <% else %>
          <%= if @title do %>
            <h1 class="text-page-title">{@title}</h1>
          <% end %>
        <% end %>
      </div>

      <%= if @center != [] do %>
        <div class="flex items-center gap-2 flex-shrink-0">
          {render_slot(@center)}
        </div>
      <% end %>

      <div
        class="flex items-center gap-1 flex-1 justify-end"
        phx-update="ignore"
        id="dashboard-actions"
      >
        <%= if @actions != [] do %>
          {render_slot(@actions)}
        <% end %>

        <%= if @show_sidebar_toggle do %>
          <button
            class="btn btn-ghost btn-sm btn-square"
            x-on:click="toggleRight()"
            title="Toggle details panel"
          >
            <.icon name="hero-view-columns" class="w-4 h-4" />
          </button>
        <% end %>

        <%= if @show_console_toggle do %>
          <button
            class="btn btn-ghost btn-sm btn-square"
            x-on:click="toggleBottom()"
            title="Toggle console (Cmd+J)"
          >
            <.icon name="hero-command-line" class="w-4 h-4" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
