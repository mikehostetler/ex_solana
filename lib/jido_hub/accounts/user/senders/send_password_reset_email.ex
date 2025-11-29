defmodule JidoHub.Accounts.User.Senders.SendPasswordResetEmail do
  @moduledoc """
  Sends a password reset email
  """

  use AshAuthentication.Sender
  use JidoHubWeb, :verified_routes

  import Swoosh.Email

  alias JidoHub.Mailer

  @impl true
  def send(user, token, _) do
    new()
    # TODO: Replace with your email
    |> from({"noreply", "noreply@example.com"})
    |> to(to_string(user.email))
    |> subject("Reset your password")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    # Route created dynamically by AshAuthentication, use unverified_url for dynamic paths
    reset_url =
      Phoenix.VerifiedRoutes.unverified_url(
        JidoHubWeb.Endpoint,
        "/reset/#{params[:token]}"
      )

    """
    <p>Click this link to reset your password:</p>
    <p><a href="#{reset_url}">#{reset_url}</a></p>
    """
  end
end
