defmodule JidoHubWeb.DashboardLayout do
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  attr :data_layout_key, :string, default: "jidohub:dashboard:v1"
  attr :default_right_open, :boolean, default: true
  attr :default_bottom_open, :boolean, default: true
  slot :header, required: true
  slot :left, required: true
  slot :main, required: true
  slot :right
  slot :bottom

  def dashboard(assigns) do
    ~H"""
    <div
      id="dashboard"
      x-data="dashboardLayout()"
      data-layout-key={@data_layout_key}
      data-default-right-open={to_string(@default_right_open)}
      data-default-bottom-open={to_string(@default_bottom_open)}
    >
      <div
        class="fixed inset-0 bg-black/50 z-35 lg:hidden"
        x-show="leftOpen && isMobile"
        x-transition:enter="transition-opacity ease-out duration-200"
        x-transition:enter-start="opacity-0"
        x-transition:enter-end="opacity-100"
        x-transition:leave="transition-opacity ease-in duration-150"
        x-transition:leave-start="opacity-100"
        x-transition:leave-end="opacity-0"
        @click="toggleLeft()"
        style="display: none;"
      >
      </div>

      <div class="dashboard-header">
        {render_slot(@header)}
      </div>

      <div class="dashboard-left" x-show="leftOpen" x-transition>
        {render_slot(@left)}
      </div>

      <div class="dashboard-main">
        {render_slot(@main)}
      </div>

      <%= if @right != [] do %>
        <div
          id="resize-right"
          class="resize-handle resize-right"
          phx-hook="ResizeVar"
          data-var="--right"
          data-axis="x"
          data-min="280"
          data-max="600"
          role="separator"
          aria-orientation="vertical"
          tabindex="0"
          x-show="rightOpen"
        >
        </div>

        <div class="dashboard-right" x-show="rightOpen" x-transition>
          {render_slot(@right)}
        </div>
      <% end %>

      <%= if @bottom != [] do %>
        <div
          id="resize-bottom"
          class="resize-handle"
          phx-hook="ResizeVar"
          data-var="--bottom"
          data-axis="y"
          data-min="150"
          data-max="600"
          role="separator"
          aria-orientation="horizontal"
          tabindex="0"
          x-show="bottomOpen"
        >
        </div>

        <div
          id="console-collapsed-handle"
          class="console-collapsed-handle"
          phx-hook="ConsoleCollapseHandle"
          x-bind:data-visible="!bottomOpen"
          @click="toggleBottom()"
          role="button"
          tabindex="0"
          @keydown.enter="toggleBottom()"
          @keydown.space.prevent="toggleBottom()"
        >
          <div class="console-collapsed-handle-content">
            <.icon name="hero-chevron-up" class="w-4 h-4" />
            <span class="text-xs font-medium">Console</span>
          </div>
        </div>

        <div class="dashboard-bottom" x-bind:data-closed="!bottomOpen ? 'true' : null">
          {render_slot(@bottom)}
        </div>
      <% end %>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def header(assigns) do
    ~H"""
    <div class={["flex items-center justify-between w-full", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
