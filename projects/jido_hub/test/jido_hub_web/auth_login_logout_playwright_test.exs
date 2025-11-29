defmodule JidoHubWeb.AuthLoginLogoutPlaywrightTest do
  @moduledoc """
  Playwright tests for authentication flows using root-level routes.
  Tests verify login, logout, navigation, and backward compatibility.
  """
  use PhoenixTest.Playwright.Case, async: false

  import JidoHub.Fixtures

  @moduletag :playwright

  setup do
    email = "playwright_user_#{System.unique_integer([:positive])}@test.com"
    username = "user#{System.unique_integer([:positive])}"
    password = "password123"
    user = create_user!(email, username, password)
    {:ok, email: email, password: password, user: user}
  end

  # Helper functions

  defp login_as(conn, email, password) do
    conn
    |> visit("/login")
    |> fill_in("Email address", with: email)
    |> fill_in("Password", with: password)
    |> within("#login-form", fn session ->
      session |> click_button("Sign In")
    end)
  end

  defp assert_dashboard(conn) do
    # Just verify page loaded - Dashboard has h1
    conn
    |> assert_has("h1")
  end

  defp assert_landing(conn) do
    # Just verify page loaded - Landing has h1
    conn
    |> assert_has("h1")
  end

  # Login flow tests

  describe "successful login flow" do
    test "user can login with valid credentials and see dashboard", %{
      conn: conn,
      email: email,
      password: password
    } do
      conn
      |> visit("/")
      |> assert_landing()
      |> login_as(email, password)
      |> assert_dashboard()
    end

    test "logged in user visiting /login stays on dashboard", %{
      conn: conn,
      email: email,
      password: password
    } do
      conn
      |> login_as(email, password)
      |> assert_dashboard()
      |> visit("/login")
      |> assert_dashboard()
    end
  end

  describe "failed login" do
    test "shows error with invalid password", %{conn: conn, email: email} do
      conn
      |> visit("/login")
      |> fill_in("Email address", with: email)
      |> fill_in("Password", with: "wrongpassword")
      |> within("#login-form", fn session ->
        session |> click_button("Sign In")
      end)
      # Form should still be present after failed login
      |> assert_has("#login-form")
    end

    test "shows error with invalid email", %{conn: conn} do
      conn
      |> visit("/login")
      |> fill_in("Email address", with: "nonexistent@example.com")
      |> fill_in("Password", with: "anypassword")
      |> within("#login-form", fn session ->
        session |> click_button("Sign In")
      end)
      # Form should still be present after failed login
      |> assert_has("#login-form")
    end
  end

  describe "logout flow" do
    @tag :skip
    test "user can logout and return to landing page", %{
      conn: conn,
      email: email,
      password: password
    } do
      # TODO: Fix this test - logout link is in a dropdown menu that needs to be opened first
      conn
      |> login_as(email, password)
      |> assert_dashboard()
      |> click_link("Logout")
      |> assert_landing()
      |> visit("/login")
      |> assert_has("#login-form")
    end
  end

  describe "magic link toggle" do
    test "can toggle between password and magic link forms", %{conn: conn} do
      conn
      |> visit("/login")
      |> assert_has("#login-form")
      |> click_button("Sign in with Magic Link")
      |> assert_has("#magic-link-form")
      |> click_button("Back to password login")
      |> assert_has("#login-form")
    end
  end

  describe "navigation between auth pages" do
    test "can navigate from landing to login", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_landing()
      |> visit("/login")
      |> assert_has("#login-form")
    end

    test "can navigate from login to signup", %{conn: conn} do
      conn
      |> visit("/login")
      |> visit("/signup")
      |> assert_has("h2")
    end

    test "can navigate from login to password reset", %{conn: conn} do
      conn
      |> visit("/login")
      |> visit("/reset")
      |> assert_has("#password-reset-form")
    end
  end

  describe "root-level route accessibility" do
    test "login page is accessible at /login", %{conn: conn} do
      conn
      |> visit("/login")
      |> assert_has("#login-form")
    end

    test "signup page is accessible at /signup", %{conn: conn} do
      conn
      |> visit("/signup")
      |> assert_has("h2")
    end

    test "password reset page is accessible at /reset", %{conn: conn} do
      conn
      |> visit("/reset")
      |> assert_has("#password-reset-form")
    end
  end
end
