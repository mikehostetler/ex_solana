defmodule JidoHubWeb.OnMount.RequireAdmin do
  @moduledoc """
  Ensures the current user has admin privileges.
  Must be used in a live_session that also includes JidoHubWeb.LiveUserAuth :live_user_required.
  """
  import Phoenix.LiveView

  alias JidoHub.Accounts.User

  def on_mount(:admin, _params, _session, socket) do
    current_user = socket.assigns[:current_user]

    if current_user && User.has_role?(current_user, :admin) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "You are not authorized to access that page.")
       |> redirect(to: "/")}
    end
  end
end
