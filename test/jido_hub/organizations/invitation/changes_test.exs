defmodule JidoHub.Organizations.Invitation.ChangesTest do
  use JidoHub.DataCase

  alias JidoHub.Organizations.Invitation

  alias JidoHub.Organizations.Invitation.Changes.{
    GenerateToken,
    SetExpiration
  }

  describe "GenerateToken.change/3" do
    test "generates a secure token" do
      changeset = Ash.Changeset.new(Invitation)
      result = GenerateToken.change(changeset, [], %{})

      token = Ash.Changeset.get_attribute(result, :token)
      assert token != nil
      assert is_binary(token)
      assert String.length(token) == 32
    end

    test "generates different tokens each time" do
      changeset1 = Ash.Changeset.new(Invitation)
      result1 = GenerateToken.change(changeset1, [], %{})
      token1 = Ash.Changeset.get_attribute(result1, :token)

      changeset2 = Ash.Changeset.new(Invitation)
      result2 = GenerateToken.change(changeset2, [], %{})
      token2 = Ash.Changeset.get_attribute(result2, :token)

      assert token1 != token2
    end

    test "generates URL-safe token" do
      changeset = Ash.Changeset.new(Invitation)
      result = GenerateToken.change(changeset, [], %{})

      token = Ash.Changeset.get_attribute(result, :token)
      assert token =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "token has no padding characters" do
      changeset = Ash.Changeset.new(Invitation)
      result = GenerateToken.change(changeset, [], %{})

      token = Ash.Changeset.get_attribute(result, :token)
      refute String.contains?(token, "=")
    end
  end

  describe "SetExpiration.change/3" do
    test "sets expiration 7 days from now by default" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      assert expires_at != nil

      expected_expiration = DateTime.add(now, 7 * 24 * 60 * 60, :second)
      diff_seconds = DateTime.diff(expires_at, expected_expiration, :second)

      assert abs(diff_seconds) < 5
    end

    test "accepts custom expiration days" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [days: 14], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      assert expires_at != nil

      expected_expiration = DateTime.add(now, 14 * 24 * 60 * 60, :second)
      diff_seconds = DateTime.diff(expires_at, expected_expiration, :second)

      assert abs(diff_seconds) < 5
    end

    test "handles 1 day expiration" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [days: 1], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      expected_expiration = DateTime.add(now, 24 * 60 * 60, :second)
      diff_seconds = DateTime.diff(expires_at, expected_expiration, :second)

      assert abs(diff_seconds) < 5
    end

    test "handles 30 day expiration" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [days: 30], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      expected_expiration = DateTime.add(now, 30 * 24 * 60 * 60, :second)
      diff_seconds = DateTime.diff(expires_at, expected_expiration, :second)

      assert abs(diff_seconds) < 5
    end

    test "expiration is always in the future" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      assert DateTime.after?(expires_at, now)
    end

    test "handles zero days (same day expiration)" do
      now = DateTime.utc_now()
      changeset = Ash.Changeset.new(Invitation)
      result = SetExpiration.change(changeset, [days: 0], %{})

      expires_at = Ash.Changeset.get_attribute(result, :expires_at)
      diff_seconds = DateTime.diff(expires_at, now, :second)

      assert abs(diff_seconds) < 5
    end
  end
end
