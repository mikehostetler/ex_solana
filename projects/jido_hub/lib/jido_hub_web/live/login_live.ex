defmodule JidoHubWeb.LoginLive do
  use JidoHubWeb, :live_view

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:show_magic_link, false)
      |> assign(:magic_link_email, "")
      |> assign(:magic_link_sent, false)

    {:ok, socket}
  end

  def handle_event("toggle_magic_link", _params, socket) do
    {:noreply, assign(socket, :show_magic_link, !socket.assigns.show_magic_link)}
  end

  def handle_event("send_magic_link", %{"email" => email}, socket) do
    case JidoHub.Accounts.User
         |> Ash.ActionInput.for_action(:request_magic_link, %{email: email})
         |> Ash.run_action(authorize?: false) do
      :ok ->
        {:noreply,
         socket
         |> assign(:magic_link_sent, true)
         |> put_flash(:info, "Magic link sent! Check your email.")}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to send magic link. Please try again.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col items-center justify-center bg-base-200 p-4">
      <div class="card w-full max-w-md bg-base-100 shadow-xl">
        <div class="card-body">
          <div class="flex flex-col items-center mb-6">
            <.icon name="hero-rocket-launch" class="w-12 h-12 text-primary mb-2" />
            <h1 class="text-3xl font-bold">JidoHub</h1>
          </div>

          <h2 class="card-title text-2xl font-bold justify-center mb-4">Sign In</h2>

          <%= if @magic_link_sent do %>
            <div class="alert alert-success">
              <.icon name="hero-check-circle" class="w-5 h-5" />
              <span>Magic link sent! Check your email to sign in.</span>
            </div>
          <% else %>
            <%= if @show_magic_link do %>
              <form phx-submit="send_magic_link" class="space-y-4" id="magic-link-form">
                <div class="form-control">
                  <label for="magic_email" class="label">
                    <span class="label-text">Email address</span>
                  </label>
                  <input
                    type="email"
                    name="email"
                    id="magic_email"
                    required
                    placeholder="you@example.com"
                    class="input input-bordered w-full"
                    value={@magic_link_email}
                  />
                </div>

                <button type="submit" class="btn btn-primary w-full">
                  <.icon name="hero-paper-airplane" class="w-5 h-5 mr-2" /> Send Magic Link
                </button>

                <button
                  type="button"
                  phx-click="toggle_magic_link"
                  class="btn btn-ghost w-full"
                >
                  Back to password login
                </button>
              </form>
            <% else %>
              <form
                action="/auth/user/password/sign_in"
                method="post"
                class="space-y-4"
                id="login-form"
              >
                <input
                  name="_csrf_token"
                  type="hidden"
                  value={Plug.CSRFProtection.get_csrf_token()}
                />

                <div class="form-control">
                  <label for="user_email" class="label">
                    <span class="label-text">Email address</span>
                  </label>
                  <input
                    type="email"
                    name="user[email]"
                    id="user_email"
                    required
                    placeholder="you@example.com"
                    class="input input-bordered w-full"
                  />
                </div>

                <div class="form-control">
                  <label for="user_password" class="label">
                    <span class="label-text">Password</span>
                  </label>
                  <div class="relative">
                    <input
                      type="password"
                      name="user[password]"
                      id="user_password"
                      required
                      placeholder="••••••••"
                      class="input input-bordered w-full pr-10"
                    />
                    <button
                      type="button"
                      phx-hook="PasswordToggle"
                      class="absolute inset-y-0 right-0 flex items-center pr-3 text-base-content opacity-60 hover:opacity-100"
                      aria-label="Show password"
                      id="password-toggle-button"
                    >
                      <.icon name="hero-eye" class="w-5 h-5" />
                      <.icon name="hero-eye-slash" class="w-5 h-5 hidden" />
                    </button>
                  </div>
                </div>

                <button type="submit" class="btn btn-primary w-full">
                  Sign In
                </button>
              </form>

              <div class="divider">OR</div>

              <button
                phx-click="toggle_magic_link"
                class="btn btn-outline w-full"
              >
                <.icon name="hero-envelope" class="w-5 h-5 mr-2" /> Sign in with Magic Link
              </button>

              <%!-- OAuth providers (disabled until configured) --%>
              <div class="divider text-xs opacity-50">Social Login (Coming Soon)</div>

              <div class="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  disabled
                  class="btn btn-outline btn-disabled"
                  title="Configure GitHub OAuth to enable"
                >
                  <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                  </svg>
                  GitHub
                </button>

                <button
                  type="button"
                  disabled
                  class="btn btn-outline btn-disabled"
                  title="Configure Google OAuth to enable"
                >
                  <svg class="w-5 h-5" viewBox="0 0 24 24">
                    <path
                      fill="#4285F4"
                      d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                    />
                    <path
                      fill="#34A853"
                      d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                    />
                    <path
                      fill="#FBBC05"
                      d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                    />
                    <path
                      fill="#EA4335"
                      d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                    />
                  </svg>
                  Google
                </button>
              </div>
            <% end %>
          <% end %>

          <div class="divider"></div>

          <div class="text-center space-y-2">
            <p class="text-sm">
              Don't have an account?
              <.link navigate="/signup" class="link link-primary font-medium">
                Sign up here
              </.link>
            </p>
            <p class="text-sm">
              <.link navigate="/reset" class="link link-primary">
                Forgot your password?
              </.link>
            </p>
          </div>
        </div>
      </div>

      <%!-- Dev Quick Login --%>
      <div
        :if={JidoHub.config(:env) == :dev}
        class="card w-full max-w-md bg-warning/10 shadow-xl mt-4"
      >
        <div class="card-body p-4">
          <h3 class="text-sm font-semibold text-center mb-2">Quick Login (Dev Only)</h3>
          <div class="grid grid-cols-3 gap-2">
            <form action="/auth/user/password/sign_in" method="post">
              <input
                name="_csrf_token"
                type="hidden"
                value={Plug.CSRFProtection.get_csrf_token()}
              />
              <input type="hidden" name="user[email]" value="alice@example.com" />
              <input type="hidden" name="user[password]" value="password123" />
              <button type="submit" class="btn btn-sm btn-warning w-full">
                Alice<br /><span class="text-xs">Owner</span>
              </button>
            </form>
            <form action="/auth/user/password/sign_in" method="post">
              <input
                name="_csrf_token"
                type="hidden"
                value={Plug.CSRFProtection.get_csrf_token()}
              />
              <input type="hidden" name="user[email]" value="bob@example.com" />
              <input type="hidden" name="user[password]" value="password123" />
              <button type="submit" class="btn btn-sm btn-warning w-full">
                Bob<br /><span class="text-xs">Admin</span>
              </button>
            </form>
            <form action="/auth/user/password/sign_in" method="post">
              <input
                name="_csrf_token"
                type="hidden"
                value={Plug.CSRFProtection.get_csrf_token()}
              />
              <input type="hidden" name="user[email]" value="charlie@example.com" />
              <input type="hidden" name="user[password]" value="password123" />
              <button type="submit" class="btn btn-sm btn-warning w-full">
                Charlie<br /><span class="text-xs">Hub Admin</span>
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
