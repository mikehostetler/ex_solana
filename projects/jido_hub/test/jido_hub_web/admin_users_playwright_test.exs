defmodule JidoHubWeb.AdminUsersPlaywrightTest do
  use PhoenixTest.Playwright.Case, async: false

  import JidoHub.Fixtures

  @moduletag :playwright

  defp login_as(conn, email, password) do
    conn
    |> visit("/login")
    |> fill_in("Email address", with: email)
    |> fill_in("Password", with: password)
    |> within("#login-form", fn session ->
      session |> click_button("Sign In")
    end)
  end

  setup do
    admin = create_admin_user!()
    {:ok, admin: admin}
  end

  describe "admin can create users" do
    @tag :skip
    test "create user via /admin/users/new", %{conn: conn, admin: admin} do
      email = "new_user_#{System.unique_integer([:positive])}@test.com"
      username = "newuser#{System.unique_integer([:positive])}"
      password = "password123"

      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users/new")
      |> assert_has("h1")
      |> fill_in("Username", with: username)
      |> fill_in("Email", with: email)
      |> fill_in("Password", with: password)
      |> fill_in("Confirm Password", with: password)
      |> click_button("Save User")
      |> assert_has("User created successfully")
      |> assert_has(username)
      |> assert_has(email)
    end
  end

  describe "admin can edit users" do
    @tag :skip
    test "edit username and email via edit modal", %{conn: conn, admin: admin} do
      user = create_user!()

      new_email = "edited_#{System.unique_integer([:positive])}@test.com"
      new_username = "edited#{System.unique_integer([:positive])}"

      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users/#{user.id}/edit")
      |> fill_in("Username", with: new_username)
      |> fill_in("Email", with: new_email)
      |> click_button("Save User")
      |> assert_has("User updated successfully")
      |> assert_has(new_username)
      |> assert_has(new_email)
    end
  end

  describe "admin can view users" do
    @tag :skip
    test "view users list shows username and email", %{conn: conn, admin: admin} do
      user = create_user!()

      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users")
      |> assert_has(user.username)
      |> assert_has(user.email)
    end
  end

  describe "datatable interactions" do
    @tag :skip
    test "filter by username via URL params", %{conn: conn, admin: admin} do
      user1 = create_user_with_username!("alice#{System.unique_integer([:positive])}")
      _user2 = create_user_with_username!("bob#{System.unique_integer([:positive])}")

      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users?filters[username]=#{user1.username}")
      |> assert_has(user1.username)
      |> refute_has("bob")
    end

    @tag :skip
    test "sorting via URL params", %{conn: conn, admin: admin} do
      u1 = create_user_with_username!("sorta#{System.unique_integer([:positive])}")
      :timer.sleep(20)
      u2 = create_user_with_username!("sortb#{System.unique_integer([:positive])}")

      conn = conn |> login_as(admin.email, "password123")

      conn = conn |> visit("/admin/users?order_by[]=inserted_at&order_directions[]=desc")
      conn |> assert_has(u2.username)

      conn = conn |> visit("/admin/users?order_by[]=inserted_at&order_directions[]=asc")
      conn |> assert_has(u1.username)
    end

    @tag :skip
    test "pagination via limit/page URL params", %{conn: conn, admin: admin} do
      _ = for _ <- 1..3, do: create_user!()

      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users?limit=1&page=2")
      |> assert_has("Users")
    end

    @tag :skip
    test "base filters form is present", %{conn: conn, admin: admin} do
      conn
      |> login_as(admin.email, "password123")
      |> visit("/admin/users")
      |> assert_has("#base-filters-form")
    end
  end
end
