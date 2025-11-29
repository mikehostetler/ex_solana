defmodule JidoHub.Accounts.User.Senders.SendNewUserConfirmationEmail do
  @moduledoc """
  Sends an email for a new user to confirm their email address.
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
    |> subject("Confirm your email address")
    |> html_body(body(token: token))
    |> Mailer.deliver!()
  end

  defp body(params) do
    # Route created dynamically by AshAuthentication, use unverified_url for dynamic paths
    confirmation_url =
      Phoenix.VerifiedRoutes.unverified_url(
        JidoHubWeb.Endpoint,
        "/confirm/#{params[:token]}"
      )

    """
    <p>Click this link to confirm your email:</p>
    <p><a href="#{confirmation_url}">#{confirmation_url}</a></p>
    """
  end
end
