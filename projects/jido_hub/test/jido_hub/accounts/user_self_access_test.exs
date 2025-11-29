defmodule JidoHub.Accounts.UserSelfAccessTest do
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User

  describe "user self-access" do
    setup do
      {:ok, user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user1@example.com",
          username: "user1",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(authorize?: false)

      {:ok, user2} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user2@example.com",
          username: "user2",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(authorize?: false)

      {:ok, admin} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "adminuser@example.com",
          username: "adminuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(authorize?: false)

      {:ok, admin} =
        admin
        |> Ash.Changeset.for_update(:update, %{role: :admin})
        |> Ash.update(authorize?: false)

      %{user1: user1, user2: user2, admin: admin}
    end

    test "user can read their own record", %{user1: user1} do
      assert {:ok, fetched_user} = Ash.get(User, user1.id, actor: user1)

      assert fetched_user.id == user1.id
      assert fetched_user.email == user1.email
    end

    test "user cannot read another user's record", %{user1: user1, user2: user2} do
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Ash.get(User, user2.id, actor: user1)
    end

    test "user can only see themselves in list queries", %{user1: user1} do
      assert {:ok, users} =
               User
               |> Ash.read(actor: user1)

      assert length(users) == 1
      assert hd(users).id == user1.id
    end

    test "admin can read all users", %{user1: user1, user2: user2, admin: admin} do
      assert {:ok, users} =
               User
               |> Ash.read(actor: admin)

      user_ids = Enum.map(users, & &1.id) |> Enum.sort()
      expected_ids = [user1.id, user2.id, admin.id] |> Enum.sort()

      assert Enum.all?(expected_ids, &(&1 in user_ids))
      assert length(users) >= 3
    end

    test "admin can read specific user by id", %{user1: user1, admin: admin} do
      assert {:ok, fetched_user} = Ash.get(User, user1.id, actor: admin)

      assert fetched_user.id == user1.id
      assert fetched_user.email == user1.email
    end

    test "unauthenticated request cannot read users" do
      assert {:ok, users} =
               User
               |> Ash.read()

      assert users == []
    end
  end
end
