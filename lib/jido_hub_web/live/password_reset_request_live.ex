defmodule JidoHubWeb.PasswordResetRequestLive do
  use JidoHubWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, email_sent: false)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-base-200 p-4">
      <div class="card w-full max-w-md bg-base-100 shadow-xl">
        <div class="card-body">
          <%= if @email_sent do %>
            <h2 class="card-title text-2xl font-bold justify-center mb-4">Check Your Email</h2>
            <div class="alert alert-success">
              <.icon name="hero-check-circle" class="size-5" />
              <div>
                <p class="font-semibold">Password reset email sent!</p>
                <p class="text-sm">
                  If an account exists with that email, you'll receive password reset instructions.
                </p>
              </div>
            </div>
            <div class="text-center mt-4">
              <.link navigate="/login" class="link link-primary">
                Back to Sign In
              </.link>
            </div>
          <% else %>
            <h2 class="card-title text-2xl font-bold justify-center mb-4">Reset Password</h2>
            <p class="text-sm text-center mb-4">
              Enter your email address and we'll send you a link to reset your password.
            </p>
            <form phx-submit="request_reset" class="space-y-4" id="password-reset-form">
              <div class="form-control">
                <label for="email" class="label">
                  <span class="label-text">Email address</span>
                </label>
                <input
                  type="email"
                  name="email"
                  id="email"
                  required
                  placeholder="you@example.com"
                  class="input input-bordered w-full"
                />
              </div>

              <button type="submit" class="btn btn-primary w-full">
                Send Reset Link
              </button>
            </form>

            <div class="divider"></div>

            <div class="text-center space-y-2">
              <p class="text-sm">
                Remember your password?
                <.link navigate="/login" class="link link-primary font-medium">
                  Sign in
                </.link>
              </p>
              <p class="text-sm">
                Don't have an account?
                <.link navigate="/signup" class="link link-primary">
                  Sign up
                </.link>
              </p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("request_reset", %{"email" => email}, socket) do
    JidoHub.Accounts.User
    |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: email})
    |> Ash.run_action()

    {:noreply, assign(socket, email_sent: true)}
  end
end
