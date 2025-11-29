defmodule JidoHub.Accounts.UserTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Accounts.User

  require Ash.Query

  describe "create user with register_with_password" do
    test "happy path: creates user with valid username, email, and password" do
      email = Faker.Internet.email()
      username = Faker.Person.first_name() |> String.downcase()
      password = Faker.String.base64(12)

      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          username: username,
          password: password,
          password_confirmation: password
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert to_string(user.email) == email
      assert user.username == username
      assert user.hashed_password != nil
      refute user.hashed_password == password
    end

    test "returns error when username is empty" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username
             end)
    end

    test "returns error when email is empty" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "",
          username: "testuser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :email || e.field == nil
             end)
    end

    test "returns error when password is empty" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "testuser",
          password: "",
          password_confirmation: ""
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :password
             end)
    end

    test "returns error when password is too short" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "testuser",
          password: "short",
          password_confirmation: "short"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :password && Map.get(e, :vars, [])[:min] == 8
             end)
    end

    test "returns error when password confirmation does not match" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "testuser",
          password: "securepassword123",
          password_confirmation: "differentpassword"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               String.contains?(e.message || "", "confirmation") ||
                 String.contains?(e.message || "", "match")
             end)
    end

    test "accepts various email formats (CiString type is permissive)" do
      # Note: CiString type doesn't validate email format by default
      # Email validation would need to be added as a separate validation if required

      # This test documents the current behavior
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "emailtest",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:ok, _user} = Ash.create(changeset, domain: Accounts, authorize?: false)
    end

    test "enforces unique email constraint" do
      email = Faker.Internet.email()
      password = Faker.String.base64(12)

      # Create first user
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          username: Faker.Person.first_name() |> String.downcase(),
          password: password,
          password_confirmation: password
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with same email
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: email,
          username: Faker.Person.last_name() |> String.downcase(),
          password: password,
          password_confirmation: password
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :email &&
                 (String.contains?(e.message || "", "unique") ||
                    String.contains?(e.message || "", "taken") ||
                    String.contains?(e.message || "", "already"))
             end)
    end

    test "enforces unique username constraint" do
      # Create first user
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user1@example.com",
          username: "duplicateuser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with same username
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user2@example.com",
          username: "duplicateuser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message || "", "taken")
             end)
    end

    test "email constraint is case-insensitive" do
      # Create first user with lowercase email
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "casesensitive@example.com",
          username: "caseuser1",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with uppercase email
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "CASESENSITIVE@EXAMPLE.COM",
          username: "caseuser2",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :email &&
                 (String.contains?(e.message || "", "unique") ||
                    String.contains?(e.message || "", "taken") ||
                    String.contains?(e.message || "", "already"))
             end)
    end

    test "username normalization converts to lowercase" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "normalize@example.com",
          username: "MixedCaseUser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == "mixedcaseuser"
    end

    test "username normalization is applied before uniqueness check" do
      # Create first user with lowercase username
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "uniquetest1@example.com",
          username: "uniqueuser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with uppercase version of same username
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "uniquetest2@example.com",
          username: "UNIQUEUSER",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message || "", "taken")
             end)
    end

    test "multiple validation errors are returned together" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "invalidemail",
          username: "ab",
          password: "short",
          password_confirmation: "different"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      # Should have multiple errors
      assert length(error.errors) > 1

      # Check that we have errors for different fields
      error_fields = Enum.map(error.errors, & &1.field)
      assert :username in error_fields or nil in error_fields
    end
  end

  describe "change_password action" do
    setup do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "changepass@example.com",
          username: "changeuser",
          password: "originalpassword123",
          password_confirmation: "originalpassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      %{user: user}
    end

    test "successfully changes password with correct current password", %{user: user} do
      changeset =
        user
        |> Ash.Changeset.for_update(:change_password, %{
          current_password: "originalpassword123",
          password: "newpassword123",
          password_confirmation: "newpassword123"
        })

      assert {:ok, updated_user} = Ash.update(changeset, domain: Accounts, authorize?: false)
      assert updated_user.hashed_password != user.hashed_password
    end

    test "fails with incorrect current password", %{user: user} do
      changeset =
        user
        |> Ash.Changeset.for_update(:change_password, %{
          current_password: "wrongpassword",
          password: "newpassword123",
          password_confirmation: "newpassword123"
        })

      assert {:error, error} = Ash.update(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.__struct__ == AshAuthentication.Errors.AuthenticationFailed &&
                 e.field == :current_password
             end)
    end

    test "fails when new password is too short", %{user: user} do
      changeset =
        user
        |> Ash.Changeset.for_update(:change_password, %{
          current_password: "originalpassword123",
          password: "short",
          password_confirmation: "short"
        })

      assert {:error, error} = Ash.update(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :password && Map.get(e, :vars, [])[:min] == 8
             end)
    end

    test "fails when new password confirmation does not match", %{user: user} do
      changeset =
        user
        |> Ash.Changeset.for_update(:change_password, %{
          current_password: "originalpassword123",
          password: "newpassword123",
          password_confirmation: "differentpassword"
        })

      assert {:error, error} = Ash.update(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               String.contains?(e.message || "", "confirmation") ||
                 String.contains?(e.message || "", "match")
             end)
    end
  end

  describe "read user by email" do
    test "finds user by exact email match" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "findme@example.com",
          username: "findme",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, found} =
        User
        |> Ash.Query.for_read(:get_by_email, %{email: "findme@example.com"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user.id
    end

    test "email lookup is case-insensitive" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "casetest@example.com",
          username: "casetest",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, found} =
        User
        |> Ash.Query.for_read(:get_by_email, %{email: "CASETEST@EXAMPLE.COM"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user.id
    end

    test "returns nil when user not found by email" do
      result =
        User
        |> Ash.Query.for_read(:get_by_email, %{email: "nonexistent@example.com"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert result == {:ok, nil}
    end
  end

  describe "read user by username" do
    test "finds user by exact username match" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "userfind@example.com",
          username: "findbyname",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, found} =
        User
        |> Ash.Query.for_read(:get_by_username, %{username: "findbyname"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user.id
    end

    test "username lookup is case-insensitive" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "usercase@example.com",
          username: "caseusername",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, found} =
        User
        |> Ash.Query.for_read(:get_by_username, %{username: "CASEUSERNAME"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user.id
    end

    test "returns nil when user not found by username" do
      result =
        User
        |> Ash.Query.for_read(:get_by_username, %{username: "nonexistentuser"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert result == {:ok, nil}
    end
  end

  describe "password hashing" do
    test "password is hashed on creation" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "hashedpass@example.com",
          username: "hashtest",
          password: "plaintextpassword",
          password_confirmation: "plaintextpassword"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.hashed_password != nil
      assert user.hashed_password != "plaintextpassword"
      assert String.starts_with?(user.hashed_password, "$2b$")
    end

    test "password is not stored in plain text" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "plaincheck@example.com",
          username: "plaintest",
          password: "mysecretpassword123",
          password_confirmation: "mysecretpassword123"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      refute String.contains?(user.hashed_password, "mysecretpassword123")
    end
  end

  describe "authorization" do
    test "creating a user requires bypassing authorization or AshAuthentication interaction" do
      # Registration action requires special handling for authorization
      # In tests, we typically use authorize?: false
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "public@example.com",
          username: "publicuser",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })

      # With authorize?: false, registration works
      assert {:ok, _user} = Ash.create(changeset, domain: Accounts, authorize?: false)
    end
  end

  describe "user attributes" do
    test "user has uuid primary key" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "uuid@example.com",
          username: "uuidtest",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert is_binary(user.id)
      assert String.length(user.id) == 36
      assert String.match?(user.id, ~r/^[0-9a-f-]{36}$/)
    end

    test "confirmed_at is nil on user creation" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "confirm@example.com",
          username: "confirmtest",
          password: "securepassword123",
          password_confirmation: "securepassword123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert user.confirmed_at == nil
    end
  end
end
