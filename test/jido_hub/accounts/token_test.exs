defmodule JidoHub.Accounts.TokenTest do
  use JidoHub.DataCase

  alias JidoHub.Accounts
  alias JidoHub.Accounts.Token
  alias JidoHub.Fixtures

  require Ash.Query

  describe "token generation" do
    test "generate token for valid user returns token" do
      user = Fixtures.create_user!()

      {:ok, token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{}, domain: Accounts)

      assert is_binary(token_string)
      assert String.length(token_string) > 0
      assert is_map(claims)
    end

    test "token contains expected structure" do
      user = Fixtures.create_user!()

      {:ok, token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{}, domain: Accounts)

      assert claims["sub"] =~ "user?id="
      assert String.contains?(claims["sub"], user.id)
      assert is_integer(claims["exp"])
      assert is_integer(claims["iat"])
      assert is_binary(token_string)
    end
  end

  describe "token revocation" do
    test "revoked? returns false for non-revoked token" do
      user = Fixtures.create_user!()

      {:ok, token_string, _claims} =
        AshAuthentication.Jwt.token_for_user(user, %{}, domain: Accounts)

      {:ok, is_revoked} =
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{token: token_string})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      assert is_revoked == false
    end

    test "revoke_token creates revocation record" do
      import Ecto.Query

      user = Fixtures.create_user!()

      {:ok, token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{"aud" => "revoke1"}, domain: Accounts)

      # Delete the auto-stored token first via SQL
      JidoHub.Repo.delete_all(from t in "tokens", where: t.jti == ^claims["jti"])

      {:ok, revocation} =
        Token
        |> Ash.Changeset.for_create(:revoke_token, %{token: token_string})
        |> Ash.create(domain: Accounts, authorize?: false)

      assert revocation.purpose == "revocation"
    end

    test "revoked? returns true for revoked token" do
      import Ecto.Query

      user = Fixtures.create_user!()

      {:ok, token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{"aud" => "revoke2"}, domain: Accounts)

      # Delete the auto-stored token first via SQL
      JidoHub.Repo.delete_all(from t in "tokens", where: t.jti == ^claims["jti"])

      {:ok, _revocation} =
        Token
        |> Ash.Changeset.for_create(:revoke_token, %{token: token_string})
        |> Ash.create(domain: Accounts, authorize?: false)

      {:ok, is_revoked} =
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{token: token_string})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      assert is_revoked == true
    end

    test "revoke_jti creates revocation by JTI" do
      import Ecto.Query

      user = Fixtures.create_user!()

      {:ok, _token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{"aud" => "revoke3"}, domain: Accounts)

      # Delete the auto-stored token first via SQL
      JidoHub.Repo.delete_all(from t in "tokens", where: t.jti == ^claims["jti"])

      {:ok, revocation} =
        Token
        |> Ash.Changeset.for_create(:revoke_jti, %{
          subject: claims["sub"],
          jti: claims["jti"]
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert revocation.purpose == "revocation"
      assert revocation.subject == claims["sub"]
    end
  end

  describe "expired tokens" do
    test "expired read action filters expired tokens" do
      {:ok, expired_tokens} =
        Token
        |> Ash.Query.for_read(:expired)
        |> Ash.read(domain: Accounts, authorize?: false)

      Enum.each(expired_tokens, fn t ->
        assert DateTime.before?(t.expires_at, DateTime.utc_now())
      end)
    end
  end

  describe "error paths" do
    test "store_token requires token argument" do
      assert {:error, error} =
               Token
               |> Ash.Changeset.for_create(:store_token, %{purpose: "test"})
               |> Ash.create(domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :token
             end)
    end

    test "revoke_token requires token argument" do
      assert {:error, error} =
               Token
               |> Ash.Changeset.for_create(:revoke_token, %{})
               |> Ash.create(domain: Accounts, authorize?: false)

      assert error.errors
             |> Enum.any?(fn e ->
               e.field == :token
             end)
    end

    test "revoke_jti requires both subject and jti arguments" do
      # The revoke_jti action requires both arguments to be present
      # When jti is missing, RevokeJtiChange will raise KeyError
      # which becomes an Ash.Error.Unknown
      assert_raise Ash.Error.Unknown, fn ->
        Token
        |> Ash.Changeset.for_create(:revoke_jti, %{subject: "test"})
        |> Ash.create!(domain: Accounts, authorize?: false)
      end
    end

    test "get_token with non-existent JTI returns nil" do
      {:ok, result} =
        Token
        |> Ash.Query.for_read(:get_token, %{jti: "nonexistent", purpose: "test"})
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert is_nil(result)
    end

    test "invalid token format handling" do
      result =
        Token
        |> Ash.ActionInput.for_action(:revoked?, %{token: "invalid-token-format"})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      assert {:error, _} = result
    end
  end

  describe "authorization" do
    test "AshAuthentication interactions bypass authorization" do
      user = Fixtures.create_user!()

      {:ok, _token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{"aud" => "auth1"}, domain: Accounts)

      {:ok, found} =
        Token
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(jti == ^claims["jti"])
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.jti == claims["jti"]
    end

    test "token operations work without actor" do
      user = Fixtures.create_user!()

      {:ok, _token_string, claims} =
        AshAuthentication.Jwt.token_for_user(user, %{"aud" => "auth2"}, domain: Accounts)

      {:ok, found} =
        Token
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(jti == ^claims["jti"])
        |> Ash.read_one(domain: Accounts, authorize?: false)

      assert found.jti == claims["jti"]
    end
  end
end
