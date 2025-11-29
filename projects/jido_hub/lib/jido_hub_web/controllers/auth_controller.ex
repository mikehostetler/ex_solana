defmodule JidoHubWeb.AuthController do
  use JidoHubWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def failure(conn, activity, reason) do
    message =
      case {activity, reason} do
        {_,
         %AshAuthentication.Errors.AuthenticationFailed{
           caused_by: %Ash.Error.Forbidden{
             errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
           }
         }} ->
          """
          You have already signed in another way, but have not confirmed your account.
          You can confirm your account using the link we sent to you, or by resetting your password.
          """

        _ ->
          "Incorrect email or password"
      end

    conn
    |> put_flash(:error, message)
    # Route to your custom login page
    |> redirect(to: ~p"/login")
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> clear_session(:jido_hub)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end

  def sign_in_with_token(conn, %{"token" => token}) do
    # Use the proper AshAuthentication flow
    case JidoHub.Accounts.User
         |> Ash.Changeset.for_action(:sign_in_with_token, %{token: token})
         |> Ash.read_one() do
      {:ok, user} ->
        conn
        |> store_in_session(user)
        |> assign(:current_user, user)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/")

      {:error, _error} ->
        conn
        |> put_flash(:error, "Invalid or expired sign-in token")
        |> redirect(to: ~p"/login")
    end
  end

  def password_sign_in(conn, %{"user" => user_params}) do
    case JidoHub.Accounts.User
         |> Ash.Query.for_read(:sign_in_with_password, user_params)
         |> Ash.Query.set_context(%{private: %{ash_authentication?: true}})
         |> Ash.read_one() do
      {:ok, user} ->
        success(conn, {:password, :sign_in}, user, nil)

      {:error, error} ->
        failure(conn, {:password, :sign_in}, error)
    end
  end

  def password_register(conn, %{"user" => user_params}) do
    case JidoHub.Accounts.User
         |> Ash.Changeset.for_create(:register_with_password, user_params)
         |> Ash.Changeset.set_context(%{private: %{ash_authentication?: true}})
         |> Ash.create() do
      {:ok, user} ->
        success(conn, {:password, :register}, user, nil)

      {:error, error} ->
        failure(conn, {:password, :register}, error)
    end
  end
end
