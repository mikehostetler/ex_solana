defmodule JidoHub.Accounts.User.SendersTest do
  use JidoHub.DataCase

  import Swoosh.TestAssertions

  alias JidoHub.Accounts.User

  alias JidoHub.Accounts.User.Senders.{
    SendNewUserConfirmationEmail,
    SendMagicLinkEmail,
    SendPasswordResetEmail
  }

  describe "SendNewUserConfirmationEmail.send/3" do
    test "sends confirmation email with valid user and token" do
      user = %User{email: "test@example.com", id: Ash.UUID.generate()}
      token = "test-token-123"

      SendNewUserConfirmationEmail.send(user, token, %{})

      assert_email_sent(
        subject: "Confirm your email address",
        to: {"", "test@example.com"}
      )
    end

    test "email contains confirmation URL with token" do
      user = %User{email: "confirm@example.com", id: Ash.UUID.generate()}
      token = "confirm-token-456"

      SendNewUserConfirmationEmail.send(user, token, %{})

      assert_email_sent(fn email ->
        assert email.html_body =~ "/confirm/#{token}"
        assert email.html_body =~ "Click this link to confirm your email"
      end)
    end

    test "email has correct from address" do
      user = %User{email: "user@example.com", id: Ash.UUID.generate()}
      token = "token-789"

      SendNewUserConfirmationEmail.send(user, token, %{})

      assert_email_sent(fn email ->
        assert email.from == {"noreply", "noreply@example.com"}
      end)
    end
  end

  describe "SendMagicLinkEmail.send/3" do
    test "sends magic link email with existing user" do
      user = %User{email: "magic@example.com", id: Ash.UUID.generate()}
      token = "magic-token-123"

      SendMagicLinkEmail.send(user, token, %{})

      assert_email_sent(
        subject: "Your login link",
        to: {"", "magic@example.com"}
      )
    end

    test "sends magic link email with email string (non-existent user)" do
      email = "newuser@example.com"
      token = "magic-token-456"

      SendMagicLinkEmail.send(email, token, %{})

      assert_email_sent(
        subject: "Your login link",
        to: {"", "newuser@example.com"}
      )
    end

    test "email contains magic link URL with token" do
      user = %User{email: "link@example.com", id: Ash.UUID.generate()}
      token = "magic-link-789"

      SendMagicLinkEmail.send(user, token, %{})

      assert_email_sent(fn email ->
        assert email.html_body =~ "/magic_link/#{token}"
        assert email.html_body =~ "Click this link to sign in"
        assert email.html_body =~ "Hello, link@example.com"
      end)
    end

    test "handles email string in body correctly" do
      email = "string-email@example.com"
      token = "token-abc"

      SendMagicLinkEmail.send(email, token, %{})

      assert_email_sent(fn sent_email ->
        assert sent_email.html_body =~ "Hello, string-email@example.com"
      end)
    end
  end

  describe "SendPasswordResetEmail.send/3" do
    test "sends password reset email with valid user and token" do
      user = %User{email: "reset@example.com", id: Ash.UUID.generate()}
      token = "reset-token-123"

      SendPasswordResetEmail.send(user, token, %{})

      assert_email_sent(
        subject: "Reset your password",
        to: {"", "reset@example.com"}
      )
    end

    test "email contains password reset URL with token" do
      user = %User{email: "password@example.com", id: Ash.UUID.generate()}
      token = "reset-token-456"

      SendPasswordResetEmail.send(user, token, %{})

      assert_email_sent(fn email ->
        assert email.html_body =~ "/reset/#{token}"
        assert email.html_body =~ "Click this link to reset your password"
      end)
    end

    test "email has correct from address" do
      user = %User{email: "test@example.com", id: Ash.UUID.generate()}
      token = "token-xyz"

      SendPasswordResetEmail.send(user, token, %{})

      assert_email_sent(fn email ->
        assert email.from == {"noreply", "noreply@example.com"}
      end)
    end
  end
end
