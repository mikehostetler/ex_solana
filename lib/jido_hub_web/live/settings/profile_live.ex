defmodule JidoHubWeb.Settings.ProfileLive do
  use JidoHubWeb, :live_view

  alias JidoHubWeb.Settings.Components

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Profile",
       current_path: "/settings/profile",
       full_name: "",
       bio: "",
       location: "",
       website: ""
     )}
  end

  @impl true
  def handle_event("save_profile", params, socket) do
    full_name = params["full_name"] || ""
    bio = params["bio"] || ""
    location = params["location"] || ""
    website = params["website"] || ""

    {:noreply,
     socket
     |> assign(
       full_name: full_name,
       bio: bio,
       location: location,
       website: website
     )
     |> put_flash(:info, "Profile updated successfully")}
  end

  @impl true
  def handle_event("upload_avatar", _params, socket) do
    {:noreply, put_flash(socket, :info, "Avatar upload coming soon")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-100">
      <Components.settings_sidebar current_path={@current_path} />

      <div class="flex-1 overflow-auto">
        <div class="max-w-4xl mx-auto p-8">
          <Components.settings_header
            title="Profile"
            description="Manage your personal information and public profile"
          />

          <div class="space-y-6">
            <Components.settings_section
              title="Avatar"
              description="Update your profile picture"
            >
              <div class="flex items-center gap-4">
                <div class="avatar placeholder">
                  <div class="bg-neutral text-neutral-content rounded-full w-20 h-20">
                    <span class="text-2xl">{String.first(to_string(@current_user.email))}</span>
                  </div>
                </div>
                <div class="flex flex-col gap-2">
                  <.button
                    type="button"
                    variant="primary"
                    size="sm"
                    phx-click="upload_avatar"
                  >
                    Upload new avatar
                  </.button>
                  <p class="text-xs text-base-content/60">
                    JPG, GIF or PNG. Max size of 2MB.
                  </p>
                </div>
              </div>
            </Components.settings_section>

            <form phx-submit="save_profile">
              <Components.settings_section
                title="Personal Information"
                description="Update your personal details"
              >
                <Components.field_group>
                  <Components.text_field
                    id="full_name"
                    name="full_name"
                    label="Full name"
                    value={@full_name}
                    placeholder="Enter your full name"
                  />

                  <div class="form-control w-full">
                    <label class="label">
                      <span class="label-text font-medium">Email</span>
                    </label>
                    <input
                      type="email"
                      id="email"
                      name="email"
                      value={@current_user.email}
                      class="input input-bordered w-full"
                      disabled
                    />
                    <label class="label">
                      <span class="label-text-alt text-base-content/60">
                        Your email address is used for notifications and account recovery
                      </span>
                    </label>
                  </div>

                  <div class="form-control w-full">
                    <label class="label">
                      <span class="label-text font-medium">Bio</span>
                    </label>
                    <textarea
                      id="bio"
                      name="bio"
                      class="textarea textarea-bordered h-24"
                      placeholder="Tell us a bit about yourself"
                    >{@bio}</textarea>
                    <label class="label">
                      <span class="label-text-alt text-base-content/60">
                        Brief description for your profile
                      </span>
                    </label>
                  </div>

                  <Components.text_field
                    id="location"
                    name="location"
                    label="Location"
                    value={@location}
                    placeholder="City, Country"
                  />

                  <Components.text_field
                    id="website"
                    name="website"
                    type="url"
                    label="Website"
                    value={@website}
                    placeholder="https://example.com"
                  />
                </Components.field_group>

                <Components.form_actions>
                  <.button type="submit" variant="primary">
                    Save changes
                  </.button>
                  <.button type="button" variant="ghost" navigate={~p"/dashboard"}>
                    Cancel
                  </.button>
                </Components.form_actions>
              </Components.settings_section>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
