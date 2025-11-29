defmodule JidoHubWeb.Settings.SecurityLive do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.Settings.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Security",
       current_path: "/settings/security",
       two_factor_enabled: false,
       active_sessions: []
     )}
  end

  @impl true
  def handle_event("update_password", params, socket) do
    current_password = params["current_password"]
    new_password = params["new_password"]
    confirm_password = params["confirm_password"]

    cond do
      is_nil(current_password) or current_password == "" ->
        {:noreply, put_flash(socket, :error, "Current password is required")}

      is_nil(new_password) or new_password == "" ->
        {:noreply, put_flash(socket, :error, "New password is required")}

      new_password != confirm_password ->
        {:noreply, put_flash(socket, :error, "Passwords do not match")}

      String.length(new_password) < 8 ->
        {:noreply, put_flash(socket, :error, "Password must be at least 8 characters")}

      true ->
        {:noreply, put_flash(socket, :info, "Password updated successfully")}
    end
  end

  @impl true
  def handle_event("enable_2fa", _params, socket) do
    {:noreply,
     socket
     |> assign(two_factor_enabled: true)
     |> put_flash(:info, "Two-factor authentication enabled")}
  end

  @impl true
  def handle_event("disable_2fa", _params, socket) do
    {:noreply,
     socket
     |> assign(two_factor_enabled: false)
     |> put_flash(:info, "Two-factor authentication disabled")}
  end

  @impl true
  def handle_event("view_sessions", _params, socket) do
    {:noreply, put_flash(socket, :info, "Session management coming soon")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100">
      <Components.settings_sidebar current_path={@current_path} />

      <div class="flex-1 overflow-auto">
        <div class="max-w-4xl mx-auto p-8">
          <Components.settings_header
            title="Security"
            description="Manage your account security and access"
          />

          <div class="space-y-6">
            <form phx-submit="update_password">
              <Components.settings_section
                title="Password"
                description="Update your password to keep your account secure"
              >
                <Components.field_group>
                  <Components.text_field
                    id="current_password"
                    name="current_password"
                    type="password"
                    label="Current password"
                    placeholder="Enter your current password"
                    required
                  />

                  <Components.text_field
                    id="new_password"
                    name="new_password"
                    type="password"
                    label="New password"
                    placeholder="Enter your new password"
                    description="Must be at least 8 characters"
                    required
                  />

                  <Components.text_field
                    id="confirm_password"
                    name="confirm_password"
                    type="password"
                    label="Confirm new password"
                    placeholder="Confirm your new password"
                    required
                  />
                </Components.field_group>

                <Components.form_actions>
                  <.button type="submit" variant="primary">
                    Update password
                  </.button>
                </Components.form_actions>
              </Components.settings_section>
            </form>

            <Components.settings_section
              title="Two-factor authentication"
              description="Add an extra layer of security to your account"
            >
              <div class="flex items-center justify-between">
                <div>
                  <p class="text-sm font-medium">
                    Status:
                    <span class={[
                      "badge badge-sm",
                      if(@two_factor_enabled, do: "badge-success", else: "badge-ghost")
                    ]}>
                      {if @two_factor_enabled, do: "Enabled", else: "Disabled"}
                    </span>
                  </p>
                  <p class="text-xs text-base-content/60 mt-1">
                    Protect your account with an additional security layer
                  </p>
                </div>
                <.button
                  :if={!@two_factor_enabled}
                  type="button"
                  variant="primary"
                  size="sm"
                  phx-click="enable_2fa"
                >
                  Enable 2FA
                </.button>
                <.button
                  :if={@two_factor_enabled}
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="disable_2fa"
                >
                  Disable 2FA
                </.button>
              </div>
            </Components.settings_section>

            <Components.settings_section
              title="Sessions"
              description="Manage your active sessions across devices"
            >
              <div class="space-y-4">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium">Current session</p>
                    <p class="text-xs text-base-content/60">
                      This is the device you're currently using
                    </p>
                  </div>
                  <div class="badge badge-primary badge-sm">Active</div>
                </div>

                <div class="divider my-2"></div>

                <.button
                  type="button"
                  variant="ghost"
                  size="sm"
                  phx-click="view_sessions"
                >
                  View all sessions
                </.button>
              </div>
            </Components.settings_section>

            <Components.settings_section
              title="Danger Zone"
              description="Irreversible actions that affect your account"
              class="border-2 border-error/20"
            >
              <div class="space-y-4">
                <div>
                  <p class="text-sm font-medium text-error">Delete account</p>
                  <p class="text-xs text-base-content/60 mt-1">
                    Once you delete your account, there is no going back. Please be certain.
                  </p>
                </div>
                <.button type="button" variant="danger" size="sm">
                  Delete account
                </.button>
              </div>
            </Components.settings_section>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
