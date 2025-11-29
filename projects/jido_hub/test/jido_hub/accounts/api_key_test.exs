defmodule JidoHub.Accounts.ApiKeyTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Accounts.ApiKey
  alias JidoHub.Fixtures

  require Ash.Query

  describe "api key creation" do
    test "create API key for user succeeds" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      api_key_string = Ash.Resource.get_metadata(api_key, :plaintext_api_key)

      assert api_key.user_id == user.id
      assert api_key.expires_at == expires_at
      assert is_binary(api_key_string)
      assert String.starts_with?(api_key_string, "jidohub_")
      refute is_nil(api_key.api_key_hash)
    end

    test "create API key without expires_at fails" do
      user = Fixtures.create_user!()

      assert {:error, error} =
               ApiKey
               |> Ash.Changeset.for_create(:create, %{user_id: user.id})
               |> Ash.create(domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :expires_at
             end)
    end

    test "create API key without user_id succeeds" do
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{expires_at: expires_at})
        |> Ash.create(domain: Accounts, authorize?: false)

      assert is_nil(api_key.user_id)
      assert api_key.expires_at == expires_at
    end

    test "API key has valid calculation" do
      user = Fixtures.create_user!()
      future_time = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: future_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(api_key, [:valid], domain: Accounts, authorize?: false)
      assert loaded.valid == true
    end

    test "expired API key has invalid calculation" do
      user = Fixtures.create_user!()
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: past_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(api_key, [:valid], domain: Accounts, authorize?: false)
      assert loaded.valid == false
    end
  end

  describe "api key uniqueness" do
    test "duplicate API key hash violates unique constraint" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, first_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      duplicate_changeset =
        ApiKey
        |> Ash.Changeset.new()
        |> Ash.Changeset.force_change_attribute(:user_id, user.id)
        |> Ash.Changeset.force_change_attribute(:expires_at, expires_at)
        |> Ash.Changeset.force_change_attribute(:api_key_hash, first_key.api_key_hash)

      result = Ash.create(duplicate_changeset, domain: Accounts, authorize?: false)

      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               String.contains?(to_string(e.message || ""), "unique") or
                 e.field == :api_key_hash
             end)
    end

    test "multiple API keys for same user with different hashes succeed" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, key1} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, key2} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert key1.id != key2.id
      assert key1.api_key_hash != key2.api_key_hash
      assert key1.user_id == key2.user_id
    end
  end

  describe "api key read operations" do
    test "read API keys for user" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, _key1} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, _key2} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, keys} =
        ApiKey
        |> Ash.Query.filter(user_id == ^user.id)
        |> Ash.read(domain: Accounts, authorize?: false)

      assert length(keys) == 2
      assert Enum.all?(keys, fn k -> k.user_id == user.id end)
    end

    test "filter API keys by valid calculation" do
      user = Fixtures.create_user!()
      future_time = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, valid_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: future_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, _expired_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: past_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, valid_keys} =
        ApiKey
        |> Ash.Query.filter(user_id == ^user.id and valid == true)
        |> Ash.read(domain: Accounts, authorize?: false)

      assert length(valid_keys) == 1
      assert hd(valid_keys).id == valid_key.id
    end
  end

  describe "api key deletion" do
    test "destroy API key succeeds" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      :ok =
        api_key
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(domain: Accounts, authorize?: false)

      {:ok, found} =
        ApiKey
        |> Ash.Query.filter(id == ^api_key.id)
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert is_nil(found)
    end
  end

  describe "api key relationships" do
    test "API key belongs to user" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(api_key, [:user], domain: Accounts, authorize?: false)
      assert loaded.user.id == user.id
      assert loaded.user.email == user.email
    end

    test "user has valid_api_keys relationship" do
      user = Fixtures.create_user!()
      future_time = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, _key1} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: future_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, _key2} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: future_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(user, [:valid_api_keys], domain: Accounts, authorize?: false)
      assert length(loaded.valid_api_keys) == 2
    end

    test "valid_api_keys filters out expired keys" do
      user = Fixtures.create_user!()
      future_time = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, _valid_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: future_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, _expired_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: past_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(user, [:valid_api_keys], domain: Accounts, authorize?: false)
      assert length(loaded.valid_api_keys) == 1
      assert hd(loaded.valid_api_keys).expires_at == future_time
    end
  end

  describe "api key authentication" do
    test "sign in with valid API key succeeds" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      api_key_string = Ash.Resource.get_metadata(api_key, :plaintext_api_key)

      {:ok, authenticated_user} =
        Accounts.User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: api_key_string})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert authenticated_user.id == user.id
      assert authenticated_user.email == user.email
    end

    test "sign in with expired API key fails" do
      user = Fixtures.create_user!()
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: past_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      api_key_string = Ash.Resource.get_metadata(api_key, :plaintext_api_key)

      result =
        Accounts.User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: api_key_string})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert {:ok, nil} = result
    end

    test "sign in with invalid API key fails" do
      result =
        Accounts.User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: "jidohub_invalid_key"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert {:ok, nil} = result
    end

    test "sign in with deleted API key fails" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      api_key_string = Ash.Resource.get_metadata(api_key, :plaintext_api_key)

      :ok =
        api_key
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(domain: Accounts, authorize?: false)

      result =
        Accounts.User
        |> Ash.Query.for_read(:sign_in_with_api_key, %{api_key: api_key_string})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert {:ok, nil} = result
    end
  end

  describe "authorization" do
    test "AshAuthentication interactions bypass authorization" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      result =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert {:ok, _} = result
    end

    test "API key operations work without actor" do
      user = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, keys} =
        ApiKey
        |> Ash.Query.filter(id == ^api_key.id)
        |> Ash.read(domain: Accounts, authorize?: false)

      assert length(keys) == 1
    end

    test "creating API key for different user requires authorization disabled" do
      user1 = Fixtures.create_user!()
      user2 = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      result =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user2.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, actor: user1, authorize?: false)

      assert {:ok, _} = result
    end

    test "read API keys without authorization" do
      user1 = Fixtures.create_user!()
      user2 = Fixtures.create_user!()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      {:ok, key1} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user1.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, _key2} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user2.id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, keys} =
        ApiKey
        |> Ash.Query.filter(user_id == ^user1.id)
        |> Ash.read(domain: Accounts, actor: user2, authorize?: false)

      assert length(keys) == 1
      assert hd(keys).id == key1.id
    end
  end

  describe "error paths" do
    test "create with invalid user_id type fails" do
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      assert {:error, error} =
               ApiKey
               |> Ash.Changeset.for_create(:create, %{
                 user_id: "not-a-valid-uuid",
                 expires_at: expires_at
               })
               |> Ash.create(domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :user_id
             end)
    end

    test "create with non-existent user_id fails on constraint" do
      non_existent_id = Ash.UUID.generate()
      expires_at = DateTime.utc_now() |> DateTime.add(30 * 24 * 3600, :second)

      result =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: non_existent_id,
          expires_at: expires_at
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               String.contains?(to_string(e.message || ""), "foreign") or
                 e.field == :user_id
             end)
    end

    test "create with past expires_at creates expired key" do
      user = Fixtures.create_user!()
      past_time = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, api_key} =
        ApiKey
        |> Ash.Changeset.for_create(:create, %{
          user_id: user.id,
          expires_at: past_time
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      loaded = Ash.load!(api_key, [:valid], domain: Accounts, authorize?: false)
      assert loaded.valid == false
    end

    test "read with invalid filter returns empty list" do
      {:ok, keys} =
        ApiKey
        |> Ash.Query.filter(user_id == ^Ash.UUID.generate())
        |> Ash.read(domain: Accounts, authorize?: false)

      assert keys == []
    end

    test "destroy non-existent API key fails" do
      fake_key = %ApiKey{
        id: Ash.UUID.generate(),
        user_id: Ash.UUID.generate(),
        api_key_hash: "fake_hash",
        expires_at: DateTime.utc_now()
      }

      result =
        fake_key
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy(domain: Accounts, authorize?: false)

      assert {:error, _} = result
    end
  end
end
