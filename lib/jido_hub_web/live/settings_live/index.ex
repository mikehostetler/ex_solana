defmodule JidoHubWeb.SettingsLive.Index do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.DashboardLayout

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Settings")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard data_layout_key="jidohub:settings:v1" default_right_open={false}>
      <:header>
        <.navbar title={@page_title} />
      </:header>

      <:left>
        <div class="h-12 border-b border-[var(--hairline)] flex items-center px-4">
          <h2 class="font-semibold text-sm">Settings</h2>
        </div>
        <.sidebar_nav
          items={[
            %{id: "profile", label: "Profile", path: "/settings"},
            %{id: "account", label: "Account", path: "/settings/account"},
            %{id: "security", label: "Security", path: "/settings/security"},
            %{id: "billing", label: "Billing", path: "/settings/billing"},
            %{id: "teams", label: "Teams", path: "/settings/teams"}
          ]}
          active="profile"
        />
      </:left>

      <:main>
        <div class="flex-1 overflow-y-auto p-6 space-y-6">
          <.card>
            <h3 class="text-lg font-semibold mb-4">Profile Settings</h3>
            <form class="space-y-4">
              <.input type="text" name="full_name" label="Full Name" value="John Doe" />
              <.input type="email" name="email" label="Email" value="john@example.com" />
              <.input
                type="textarea"
                name="bio"
                label="Bio"
                placeholder="Tell us about yourself..."
              />

              <div class="flex gap-3">
                <.button variant="primary">Save Changes</.button>
                <.button variant="ghost">Cancel</.button>
              </div>
            </form>
          </.card>

          <.card>
            <h3 class="text-lg font-semibold mb-4">Preferences</h3>
            <div class="space-y-3">
              <.input
                type="checkbox"
                name="email_notifications"
                label="Enable email notifications"
                checked={true}
              />
              <.input type="checkbox" name="dark_mode" label="Enable dark mode" checked={true} />
              <.input
                type="checkbox"
                name="keyboard_shortcuts"
                label="Show keyboard shortcuts"
                checked={true}
              />
            </div>
          </.card>

          <.card>
            <h3 class="text-lg font-semibold mb-4 text-error">Danger Zone</h3>
            <div class="space-y-3">
              <div class="flex items-center justify-between">
                <div>
                  <p class="font-medium">Delete Account</p>
                  <p class="text-sm text-base-content/70">
                    Permanently delete your account and all data
                  </p>
                </div>
                <.button variant="danger">Delete</.button>
              </div>
            </div>
          </.card>
        </div>
      </:main>
    </DashboardLayout.dashboard>
    """
  end
end
