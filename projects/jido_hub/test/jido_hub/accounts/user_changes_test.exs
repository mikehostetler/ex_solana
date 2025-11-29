defmodule JidoHub.Accounts.UserChangesTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Accounts.User
  alias JidoHub.Accounts.User.Changes.{NormalizeUsername, EnsureUniqueUsername}

  require Ash.Query

  describe "NormalizeUsername - downcasing" do
    test "downcases username" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test@example.com",
          username: "Foo_Bar",
          password: "password123",
          password_confirmation: "password123"
        })

      {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == "foo_bar"
    end

    test "handles mixed case" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "mixed@example.com",
          username: "TeSt_UsEr123",
          password: "password123",
          password_confirmation: "password123"
        })

      {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == "test_user123"
    end
  end

  describe "NormalizeUsername - nil passthrough" do
    test "allows nil username through without changes" do
      # Create initial changeset without username
      changeset = Ash.Changeset.new(User)

      # Apply the change directly
      result = NormalizeUsername.change(changeset, [], %{})

      # Should pass through without errors
      refute result.valid? == false
      assert Ash.Changeset.get_attribute(result, :username) == nil
    end
  end

  describe "NormalizeUsername - length boundaries" do
    test "rejects usernames shorter than 4 characters" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "short@example.com",
          username: "abc",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "at least 4")
             end)
    end

    test "accepts minimum valid length (4 chars)" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "min@example.com",
          username: "abcd",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == "abcd"
    end

    test "accepts maximum valid length (30 chars)" do
      max_username = String.duplicate("a", 30)

      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "max@example.com",
          username: max_username,
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == max_username
    end

    test "rejects usernames longer than 30 characters" do
      long_username = String.duplicate("a", 31)

      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "long@example.com",
          username: long_username,
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "at most 30")
             end)
    end
  end

  describe "NormalizeUsername - format rules (GitHub-like)" do
    test "rejects username starting with hyphen" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "start-hyphen@example.com",
          username: "-username",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "must start and end with a letter or number")
             end)
    end

    test "rejects username ending with hyphen" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "end-hyphen@example.com",
          username: "username-",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "must start and end with a letter or number")
             end)
    end

    test "rejects username starting with underscore" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "start-underscore@example.com",
          username: "_username",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "must start and end with a letter or number")
             end)
    end

    test "rejects username ending with underscore" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "end-underscore@example.com",
          username: "username_",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "must start and end with a letter or number")
             end)
    end

    test "rejects username with spaces" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "space@example.com",
          username: "user name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(
                   e.message,
                   "can only contain letters, numbers, hyphens, and underscores"
                 )
             end)
    end

    test "rejects username with @ symbol" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "at@example.com",
          username: "user@name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(
                   e.message,
                   "can only contain letters, numbers, hyphens, and underscores"
                 )
             end)
    end

    test "rejects username with period" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "period@example.com",
          username: "user.name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(
                   e.message,
                   "can only contain letters, numbers, hyphens, and underscores"
                 )
             end)
    end

    test "accepts valid single-character alphanumeric username (would fail on length)" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "single@example.com",
          username: "a",
          password: "password123",
          password_confirmation: "password123"
        })

      # Should fail on length, not format
      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "at least 4")
             end)
    end

    test "rejects single-character non-alphanumeric username" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "single-special@example.com",
          username: "_",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 (String.contains?(e.message, "Single character") ||
                    String.contains?(e.message, "at least 4"))
             end)
    end
  end

  describe "NormalizeUsername - reserved words" do
    test "rejects 'admin'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "admin@example.com",
          username: "admin",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end

    test "rejects 'api'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "api@example.com",
          username: "api",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      # Should fail on either reserved or length (api is 3 chars)
      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 (String.contains?(e.message, "reserved") ||
                    String.contains?(e.message, "at least 4"))
             end)
    end

    test "rejects 'login'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "login@example.com",
          username: "login",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end

    test "rejects 'org'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "org@example.com",
          username: "org",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      # Should fail on either reserved or length (org is 3 chars)
      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 (String.contains?(e.message, "reserved") ||
                    String.contains?(e.message, "at least 4"))
             end)
    end

    test "rejects 'pods'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "pods@example.com",
          username: "pods",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end

    test "rejects 'jido'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "jido@example.com",
          username: "jido",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end

    test "rejects 'agent'" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "agent@example.com",
          username: "agent",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end

    test "case-insensitive reserved word rejection" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "admin-upper@example.com",
          username: "ADMIN",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "reserved")
             end)
    end
  end

  describe "NormalizeUsername - consecutive special characters" do
    test "rejects double underscore" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "double-underscore@example.com",
          username: "user__name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "consecutive special characters")
             end)
    end

    test "rejects double hyphen" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "double-hyphen@example.com",
          username: "user--name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "consecutive special characters")
             end)
    end

    test "rejects hyphen-underscore" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "hyphen-underscore@example.com",
          username: "user-_name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "consecutive special characters")
             end)
    end

    test "rejects underscore-hyphen" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "underscore-hyphen@example.com",
          username: "user_-name",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username &&
                 String.contains?(e.message, "consecutive special characters")
             end)
    end

    test "accepts single hyphens and underscores" do
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "valid-special@example.com",
          username: "user_name-test",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:ok, user} = Ash.create(changeset, domain: Accounts, authorize?: false)
      assert user.username == "user_name-test"
    end
  end

  describe "EnsureUniqueUsername - duplicate detection" do
    test "rejects duplicate username from different user" do
      # Create first user
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user1@example.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try to create second user with same username
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "user2@example.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "already taken")
             end)
    end

    test "case-insensitive duplicate detection" do
      # Create first user with lowercase
      {:ok, _user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "lower@example.com",
          username: "testuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Try uppercase version
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "upper@example.com",
          username: "TESTUSER",
          password: "password123",
          password_confirmation: "password123"
        })

      assert {:error, error} = Ash.create(changeset, domain: Accounts, authorize?: false)

      assert Enum.any?(error.errors, fn e ->
               e.field == :username && String.contains?(e.message, "already taken")
             end)
    end
  end

  describe "EnsureUniqueUsername - nil username" do
    test "allows nil username without uniqueness check" do
      # Create changeset without username
      changeset = Ash.Changeset.new(User)

      # Apply the change directly
      result = EnsureUniqueUsername.change(changeset, [], %{})

      # Should not add any uniqueness errors
      username_errors =
        Enum.filter(result.errors, fn e ->
          e.field == :username && String.contains?(e.message || "", "taken")
        end)

      assert username_errors == []
    end
  end

  describe "EnsureUniqueUsername - authorize?: false" do
    test "query uses authorize?: false internally" do
      # Create first user
      {:ok, user1} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "first@example.com",
          username: "firstuser",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Create changeset for duplicate (this will fail but we're testing the query path)
      changeset =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "second@example.com",
          username: "firstuser",
          password: "password123",
          password_confirmation: "password123"
        })

      # The change should detect the duplicate
      # The implementation uses authorize?: false internally for the query
      result = EnsureUniqueUsername.change(changeset, [], %{})

      # Should have a username error
      assert Enum.any?(result.errors, fn e ->
               e.field == :username && String.contains?(e.message, "already taken")
             end)

      # Verify the existing user can still be read
      assert {:ok, found} =
               User
               |> Ash.Query.filter(id == ^user1.id)
               |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.id == user1.id
    end
  end

  describe "Direct change module unit tests" do
    test "NormalizeUsername directly on changeset" do
      changeset =
        User
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:username, "TestUser")

      result = NormalizeUsername.change(changeset, [], %{})

      assert Ash.Changeset.get_attribute(result, :username) == "testuser"
    end

    test "NormalizeUsername with invalid format" do
      changeset =
        User
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:username, "user name")

      result = NormalizeUsername.change(changeset, [], %{})

      assert Enum.any?(result.errors, fn e ->
               e.field == :username &&
                 String.contains?(
                   e.message,
                   "can only contain letters, numbers, hyphens, and underscores"
                 )
             end)
    end

    test "EnsureUniqueUsername directly on changeset" do
      # Create existing user
      {:ok, _existing} =
        User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "existing@example.com",
          username: "existing",
          password: "password123",
          password_confirmation: "password123"
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      # Create new changeset with same username
      changeset =
        User
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:username, "existing")
        |> Map.put(:domain, Accounts)

      result = EnsureUniqueUsername.change(changeset, [], %{})

      assert Enum.any?(result.errors, fn e ->
               e.field == :username && String.contains?(e.message, "already taken")
             end)
    end
  end
end
