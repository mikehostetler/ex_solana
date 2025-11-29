defmodule JidoHubWeb.BottomDrawer do
  @moduledoc """
  Bottom drawer component for logs, terminal, debug output, etc.
  """
  use Phoenix.Component

  import JidoHubWeb.CoreComponents

  attr :class, :string, default: ""

  def render(assigns) do
    ~H"""
    <div class={["flex flex-col h-full", @class]}>
      <!-- Drawer Header with Tabs -->
      <div class="flex items-center justify-between border-b border-base-content/10 bg-base-300">
        <div role="tablist" class="tabs tabs-boxed tabs-sm bg-transparent p-2">
          <button role="tab" class="tab tab-active gap-2">
            <.icon name="hero-rectangle-stack" class="w-4 h-4" /> Logs
          </button>
          <button role="tab" class="tab gap-2">
            <.icon name="hero-command-line" class="w-4 h-4" /> Terminal
          </button>
          <button role="tab" class="tab gap-2">
            <.icon name="hero-bug-ant" class="w-4 h-4" /> Debug
          </button>
        </div>
        
    <!-- Drawer Actions -->
        <div class="flex items-center gap-1 px-2">
          <button class="btn btn-ghost btn-xs btn-square" title="Clear">
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
          <button
            class="btn btn-ghost btn-xs btn-square"
            title="Close drawer"
            @click="toggleBottom()"
          >
            <.icon name="hero-chevron-down" class="w-4 h-4" />
          </button>
        </div>
      </div>
      
    <!-- Drawer Content -->
      <div class="flex-1 overflow-auto p-4 font-mono text-sm bg-base-100">
        <!-- Sample log entries -->
        <div class="space-y-1">
          <div class="text-success">[INFO] Workflow started: workflow_123</div>
          <div class="text-info">[DEBUG] Step 1: Initialize environment</div>
          <div class="text-base-content/60">[DEBUG] Loading configuration...</div>
          <div class="text-success">[INFO] Configuration loaded successfully</div>
          <div class="text-warning">[WARN] Deprecated API usage detected</div>
          <div class="text-base-content/60">[DEBUG] Step 2: Execute workflow</div>
          <div class="text-success">[INFO] Workflow completed successfully</div>
        </div>
      </div>
    </div>
    """
  end
end
