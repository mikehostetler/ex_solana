defmodule JidoHubWeb.RegisterLiveTest do
  use JidoHubWeb.ConnCase

  import JidoHub.Fixtures
  import Phoenix.LiveViewTest

  describe "RegisterLive page structure" do
    test "renders registration form with all required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "#register-form")
      assert has_element?(view, "#user_email")
      assert has_element?(view, "#user_username")
      assert has_element?(view, "#user_password")
      assert has_element?(view, "#user_password_confirmation")
    end

    test "form posts to correct endpoint", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "form[action='/auth/user/password/register']")
      assert has_element?(view, "form[method='post']")
    end

    test "all form fields have proper attributes", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "input[type='email'][name='user[email]'][required]")
      assert has_element?(view, "input[type='text'][name='user[username]'][required]")
      assert has_element?(view, "input[type='password'][name='user[password]'][required]")

      assert has_element?(
               view,
               "input[type='password'][name='user[password_confirmation]'][required]"
             )
    end

    test "shows link to login page", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "a[href='/login']")
    end

    test "shows password toggle buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "#password-toggle-button")
      assert has_element?(view, "#password-confirmation-toggle-button")
    end
  end

  describe "RegisterLive magic link toggle" do
    test "toggles to magic link registration form", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Initially shows password form
      assert has_element?(view, "#register-form")
      refute has_element?(view, "#magic-link-register-form")

      # Click toggle button
      view
      |> element("button", "Register with Magic Link")
      |> render_click()

      # Should now show magic link form instead
      refute has_element?(view, "#register-form")
      assert has_element?(view, "#magic-link-register-form")
      assert has_element?(view, "#magic_email")
    end

    test "toggles back to password form from magic link", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Toggle to magic link form
      view
      |> element("button", "Register with Magic Link")
      |> render_click()

      assert has_element?(view, "#magic-link-register-form")

      # Toggle back
      view
      |> element("button", "Back to password registration")
      |> render_click()

      # Should be back to password form
      assert has_element?(view, "#register-form")
      refute has_element?(view, "#magic-link-register-form")
    end
  end

  describe "RegisterLive magic link submission" do
    test "sends magic link with valid email", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Toggle to magic link form
      view
      |> element("button", "Register with Magic Link")
      |> render_click()

      # Submit magic link form
      view
      |> element("#magic-link-register-form")
      |> render_submit(%{"email" => "user@example.com"})

      # Should show success message
      assert has_element?(view, ".alert-success")
      assert render(view) =~ "Magic link sent"
    end

    test "shows success alert and hides forms after magic link sent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Toggle to magic link and submit
      view
      |> element("button", "Register with Magic Link")
      |> render_click()

      view
      |> element("#magic-link-register-form")
      |> render_submit(%{"email" => "test@example.com"})

      # After sending, should hide forms and show success state
      assert has_element?(view, ".alert-success")
      refute has_element?(view, "#magic-link-register-form")
      refute has_element?(view, "#register-form")
    end

    test "handles magic link send failure gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # Toggle to magic link form
      view
      |> element("button", "Register with Magic Link")
      |> render_click()

      # Submit with potentially problematic data
      # Note: The actual validation happens server-side
      view
      |> element("#magic-link-register-form")
      |> render_submit(%{"email" => "invalid-email"})

      # Should either show error or success (depends on backend validation)
      # At minimum, page should still render
      assert render(view)
    end
  end

  describe "RegisterLive form validation scenarios (integration with controller)" do
    test "attempting registration with duplicate username requires controller test", %{
      conn: conn
    } do
      # Create existing user
      create_user!("existing@example.com", "existinguser", "password123")

      # Note: Form validation happens on POST to /auth/user/password/register
      # This LiveView test verifies the form exists with correct structure
      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "#register-form")
      assert has_element?(view, "input[name='user[username]']")

      # Actual duplicate username validation testing should be done in controller test
      # or as an integration test that posts directly to the endpoint
    end

    test "attempting registration with duplicate email requires controller test", %{conn: conn} do
      # Create existing user
      create_user!("existing@example.com", "existinguser", "password123")

      {:ok, view, _html} = live(conn, "/signup")

      assert has_element?(view, "#register-form")
      assert has_element?(view, "input[name='user[email]']")

      # Actual duplicate email validation testing should be done in controller test
    end

    test "form has HTML5 validation for required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # HTML5 required attribute prevents empty submission client-side
      assert has_element?(view, "input[required][name='user[email]']")
      assert has_element?(view, "input[required][name='user[username]']")
      assert has_element?(view, "input[required][name='user[password]']")
      assert has_element?(view, "input[required][name='user[password_confirmation]']")
    end

    test "email field has HTML5 email type validation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/signup")

      # HTML5 email type provides client-side format validation
      assert has_element?(view, "input[type='email'][name='user[email]']")
    end
  end
end
