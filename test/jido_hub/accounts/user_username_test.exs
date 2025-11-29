defmodule JidoHub.Accounts.UserUsernameTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Accounts.User

  require Ash.Query

  describe "username validation" do
    test "accepts valid usernames" do
      valid_usernames = [
        "user",
        "user123",
        "user_name",
        "user-name",
        "123user",
        "u_s_e_r",
        "user-123-test"
      ]

      for {username, index} <- Enum.with_index(valid_usernames) do
        changeset =
          User
          |> Ash.Changeset.for_create(:register_with_password, %{
            email: "test#{index}@test.com",
            username: username,
            password: "password123",
            password_confirmation: "password123"
          })

        assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
        assert user.username == String.downcase(username)
      end
    end

    test "rejects invalid usernames" do
      invalid_usernames = [
        # too short
        "ab",
        # too long
        String.duplicate("a", 31),
        # starts with hyphen
        "-user",
        # ends with hyphen
        "user-",
        # starts with underscore
        "_user",
        # ends with underscore
        "user_",
        # consecutive hyphens
        "user--name",
        # consecutive underscores
        "user__name",
        # contains space
        "user name",
        # contains @
        "user@name",
        # contains period
        "user.name"
      ]

      for {username, index} <- Enum.with_index(invalid_usernames) do
        changeset =
          User
          |> Ash.Changeset.for_create(:register_with_password, %{
            email: "invalid#{index}@test.com",
            username: username,
            password: "password123",
            password_confirmation: "password123"
          })

        assert {:error, _} = Ash.create(changeset, domain: Accounts, authorize?: false)
      end
    end

    test "blocks reserved usernames" do
      reserved = ["admin", "api", "jido", "agent", "ai", "llm"]

      for {username, index} <- Enum.with_index(reserved) do
        changeset =
          User
          |> Ash.Changeset.for_create(:register_with_password, %{
            email: "reserved#{index}@test.com",
            username: username,
            password: "password123",
            password_confirmation: "password123"
          })

        result = Ash.create(changeset, domain: Accounts, authorize?: false)

        assert {:error, error} = result,
               "Expected error for reserved username '#{username}', got: #{inspect(result)}"

        # Reserved words that are too short will fail on length, but that's OK
        # as they're still rejected
        has_username_error =
          error.errors
          |> Enum.any?(fn e ->
            e.field == :username &&
              (String.contains?(e.message || "", "reserved") ||
                 String.contains?(e.message || "", "length") ||
                 String.contains?(e.message || "", "4"))
          end)

        assert has_username_error,
               "Expected username error for '#{username}', got errors: #{inspect(error.errors)}"
      end
    end

    test "enforces uniqueness" do
      # Create first user
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user1@test.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with same username
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user2@test.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :username && String.contains?(e.message || "", "taken")
             end)
    end

    test "enforces case-insensitive uniqueness" do
      # Create user with lowercase username
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "testunique1@test.com",
          username: "testuser123",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create another user with uppercase version of same username
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "testunique2@test.com",
          username: "TESTUSER123",
          password: "password123",
          password_confirmation: "password123"
        })

      result = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :username && String.contains?(e.message || "", "taken")
             end),
             "Expected unique_username error for 'ALICE' after 'alice', got errors: #{inspect(error.errors)}"
    end

    test "normalizes to lowercase" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "testcase@test.com",
          username: "TestUser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert user.username == "testuser"
    end

    test "get_by_username is case-insensitive" do
      {:ok, user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "lookup@test.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, found} =
        User
        |> Ash.Query.for_read(:get_by_username, %{username: "TestUser"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user.id
    end

    test "validates username length boundaries" do
      # Test minimum length (4 chars)
      {:ok, _user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "min@test.com",
          username: "abcd",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Test maximum length (30 chars)
      max_username = String.duplicate("a", 30)

      {:ok, _user} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "max@test.com",
          username: max_username,
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Test too short (3 chars) - verify error message
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "short@test.com",
          username: "abc",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :username &&
                 String.contains?(e.message || "", "at least 4 characters")
             end),
             "Expected clear minimum length error message, got: #{inspect(error.errors)}"

      # Test too long (31 chars) - verify error message
      long_username = String.duplicate("a", 31)

      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "long@test.com",
          username: long_username,
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :username &&
                 String.contains?(e.message || "", "at most 30 characters")
             end),
             "Expected clear maximum length error message, got: #{inspect(error.errors)}"
    end

    test "allows single character alphanumeric usernames with minimum 4 constraint" do
      # Note: Single char usernames would be valid format but fail min length
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "single@test.com",
          username: "a",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)
      # Should fail on length, not format
      has_length_error =
        error.errors
        |> Enum.any?(fn e ->
          # Check for any length-related error message
          e.field == :username &&
            (String.contains?(e.message || "", "at least") ||
               String.contains?(e.message || "", "length") ||
               String.contains?(e.message || "", "4"))
        end)

      assert has_length_error,
             "Expected length error for single char username, got errors: #{inspect(error.errors)}"
    end

    test "rejects consecutive special characters" do
      invalid = ["user--name", "user__name", "user-_name", "user_-name"]

      for {username, index} <- Enum.with_index(invalid) do
        changeset =
          User
          |> Ash.Changeset.for_create(:register_with_password, %{
            email: "consecutive#{index}@test.com",
            username: username,
            password: "password123",
            password_confirmation: "password123"
          })

        assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

        assert error.errors
               |> Enum.any?(fn e ->
                 e.field == :username &&
                   String.contains?(e.message || "", "consecutive special characters")
               end)
      end
    end
  end
end
