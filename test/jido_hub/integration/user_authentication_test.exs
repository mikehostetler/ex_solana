defmodule JidoHub.Integration.UserAuthenticationTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Accounts
  alias JidoHub.Accounts.User

  require Ash.Query

  describe "magic link flow" do
    test "request_magic_link for existing user sends email" do
      user = create_user!()

      :ok =
        User
        |> Ash.ActionInput.for_action(:request_magic_link, %{email: user.email})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      assert_received {:email, email}
      assert email.to == [{"", to_string(user.email)}]
      assert email.subject in ["Your login link", "Confirm your email address"]
    end

    test "magic link registration flow creates new user" do
      new_email = "newuser-#{System.unique_integer([:positive])}@test.com"
      new_username = "newuser#{System.unique_integer([:positive])}"

      :ok =
        User
        |> Ash.ActionInput.for_action(:request_magic_link, %{email: new_email})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      token = extract_magic_link_token(new_email)

      {:ok, new_user} =
        User
        |> Ash.Changeset.for_create(:sign_in_with_magic_link, %{
          token: token,
          username: new_username
        })
        |> Ash.create(domain: Accounts, authorize?: false)

      assert to_string(new_user.email) == new_email
      assert new_user.username == new_username
      refute is_nil(new_user.confirmed_at)
    end

    test "invalid magic link token fails with clear error" do
      invalid_token = "invalid-token-12345"

      {:error, error} =
        User
        |> Ash.Changeset.for_create(:sign_in_with_magic_link, %{token: invalid_token})
        |> Ash.create(domain: Accounts, authorize?: false)

      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "password reset flow" do
    test "request_password_reset_token for existing user sends email" do
      user = create_user!()

      :ok =
        User
        |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: user.email})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      assert_received {:email, email}
      assert email.to == [{"", to_string(user.email)}]
      assert email.subject in ["Reset your password", "Confirm your email address"]
    end

    test "reset_password_with_token with valid token updates password" do
      user = create_user!()
      original_hashed_password = user.hashed_password

      :ok =
        User
        |> Ash.ActionInput.for_action(:request_password_reset_token, %{email: user.email})
        |> Ash.run_action(domain: Accounts, authorize?: false)

      reset_token = extract_password_reset_token(user.email)
      new_password = "newpassword123"

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: reset_token,
          password: new_password,
          password_confirmation: new_password
        })
        |> Ash.update(domain: Accounts, authorize?: false)

      assert updated_user.hashed_password != original_hashed_password

      {:ok, _signed_in_user} =
        User
        |> Ash.Query.for_read(:sign_in_with_password, %{
          email: user.email,
          password: new_password
        })
        |> Ash.read_one(domain: Accounts, authorize?: false)
    end

    test "invalid password reset token fails" do
      user = create_user!()
      invalid_token = "invalid-reset-token-12345"
      new_password = "newpassword123"

      {:error, error} =
        user
        |> Ash.Changeset.for_update(:reset_password_with_token, %{
          reset_token: invalid_token,
          password: new_password,
          password_confirmation: new_password
        })
        |> Ash.update(domain: Accounts, authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "no email sent for non-existent user to prevent information leakage" do
      non_existent_email = "nonexistent-#{System.unique_integer([:positive])}@test.com"

      before_count = count_sent_emails()

      :ok =
        User
        |> Ash.ActionInput.for_action(:request_password_reset_token, %{
          email: non_existent_email
        })
        |> Ash.run_action(domain: Accounts, authorize?: false)

      after_count = count_sent_emails()
      assert before_count == after_count
    end
  end

  describe "authentication token flow" do
    test "sign_in_with_password returns authentication token" do
      user = create_user!()

      {:ok, signed_in_user} =
        User
        |> Ash.Query.for_read(:sign_in_with_password, %{
          email: user.email,
          password: "password123"
        })
        |> Ash.read_one(domain: Accounts, authorize?: false)

      auth_token = signed_in_user.__metadata__.token
      assert is_binary(auth_token)
      assert String.length(auth_token) > 0
    end
  end
end
