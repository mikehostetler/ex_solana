defmodule JidoHubWeb.Settings.PreferencesLive do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.Settings.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Preferences",
       current_path: "/settings",
       theme: "system",
       email_notifications: true,
       push_notifications: true,
       workflow_notifications: true
     )}
  end

  @impl true
  def handle_event("save_preferences", params, socket) do
    theme = params["theme"] || "system"
    email_notifications = params["email_notifications"] == "on"
    push_notifications = params["push_notifications"] == "on"
    workflow_notifications = params["workflow_notifications"] == "on"

    {:noreply,
     socket
     |> assign(
       theme: theme,
       email_notifications: email_notifications,
       push_notifications: push_notifications,
       workflow_notifications: workflow_notifications
     )
     |> put_flash(:info, "Preferences updated successfully")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100">
      <Components.settings_sidebar current_path={@current_path} />

      <div class="flex-1 overflow-auto">
        <div class="max-w-4xl mx-auto p-8">
          <Components.settings_header
            title="Preferences"
            description="Manage your application preferences and settings"
          />

          <form phx-submit="save_preferences" class="space-y-6">
            <Components.settings_section title="Appearance">
              <Components.field_group>
                <Components.select_field
                  id="theme"
                  name="theme"
                  label="Theme"
                  value={@theme}
                  options={[
                    {"System default", "system"},
                    {"Light", "light"},
                    {"Dark", "dark"}
                  ]}
                  description="Choose how JidoHub looks to you. Select a single theme, or sync with your system."
                />
              </Components.field_group>
            </Components.settings_section>

            <Components.settings_section
              title="Notifications"
              description="Manage how you receive notifications"
            >
              <Components.field_group>
                <Components.toggle_field
                  id="email_notifications"
                  name="email_notifications"
                  label="Email notifications"
                  description="Receive notifications via email"
                  checked={@email_notifications}
                />

                <Components.toggle_field
                  id="push_notifications"
                  name="push_notifications"
                  label="Push notifications"
                  description="Receive push notifications in your browser"
                  checked={@push_notifications}
                />

                <Components.toggle_field
                  id="workflow_notifications"
                  name="workflow_notifications"
                  label="Workflow updates"
                  description="Get notified when workflows complete or fail"
                  checked={@workflow_notifications}
                />
              </Components.field_group>
            </Components.settings_section>

            <Components.form_actions>
              <.button type="submit" variant="primary">
                Save changes
              </.button>
              <.button type="button" variant="ghost" navigate={~p"/dashboard"}>
                Cancel
              </.button>
            </Components.form_actions>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
