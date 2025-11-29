defmodule JidoHub.Organizations.InvitationTest do
  use JidoHub.DataCase

  import Ash.Query
  import JidoHub.Fixtures

  alias JidoHub.Organizations.{Membership, Invitation}

  describe "create/2" do
    test "creates invitation with valid attributes" do
      owner = create_user!()
      organization = create_organization!(owner)

      {:ok, invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{
          email: "invited@example.com",
          role: :member
        })
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert "#{invitation.email}" == "invited@example.com"
      assert invitation.role == :member
      assert invitation.organization_id == organization.id
      assert invitation.invited_by_id == owner.id
      assert is_binary(invitation.token)
      assert byte_size(invitation.token) == 32
      assert invitation.expires_at
      assert is_nil(invitation.accepted_at)
    end

    test "defaults role to member when not specified" do
      owner = create_user!()
      organization = create_organization!(owner)

      {:ok, invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: "invited@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert invitation.role == :member
    end

    test "generates unique tokens for different invitations" do
      owner = create_user!()
      organization = create_organization!(owner)

      {:ok, invitation1} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: "user1@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      {:ok, invitation2} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: "user2@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert invitation1.token != invitation2.token
    end

    test "sets expiration date to 7 days in the future" do
      owner = create_user!()
      organization = create_organization!(owner)

      now = DateTime.utc_now()

      {:ok, invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: "invited@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      expected_expiry = DateTime.add(now, 7 * 24 * 60 * 60, :second)
      diff = DateTime.diff(invitation.expires_at, expected_expiry, :second)
      assert abs(diff) <= 60
    end

    test "requires valid email address" do
      owner = create_user!()
      organization = create_organization!(owner)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
               |> Ash.Changeset.for_create(:create, %{email: "invalid-email"})
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert Enum.any?(errors, &(&1.field == :email))
    end

    test "validates role is valid" do
      owner = create_user!()
      organization = create_organization!(owner)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
               |> Ash.Changeset.for_create(:create, %{
                 email: "invited@example.com",
                 role: :invalid_role
               })
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert Enum.any?(errors, &(&1.field == :role))
    end

    test "enforces unique pending invitation constraint" do
      owner = create_user!()
      organization = create_organization!(owner)
      email = "invited@example.com"

      _invitation1 =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: email})
        |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
               |> Ash.Changeset.for_create(:create, %{email: email})
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
    end
  end

  describe "accept/2" do
    test "accepts valid invitation and creates membership" do
      owner = create_user!()
      accepting_user = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, accepting_user.email, :admin)

      {:ok, accepted_invitation} =
        invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:token, invitation.token)
        |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
        |> Ash.Changeset.for_update(:accept, %{})
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      assert accepted_invitation.accepted_at
      refute is_nil(accepted_invitation.accepted_at)

      {:ok, membership} =
        Membership
        |> filter(user_id == ^accepting_user.id and organization_id == ^organization.id)
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      assert membership.role == :admin
      assert membership.user_id == accepting_user.id
      assert membership.organization_id == organization.id
    end

    test "rejects invalid token" do
      owner = create_user!()
      accepting_user = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, accepting_user.email)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:token, "invalid-token")
               |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
               |> Ash.Changeset.for_update(:accept, %{})
               |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
    end

    test "rejects already accepted invitation" do
      owner = create_user!()
      accepting_user = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, accepting_user.email)

      {:ok, accepted_invitation} =
        invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:token, invitation.token)
        |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
        |> Ash.Changeset.for_update(:accept, %{})
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               accepted_invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:token, accepted_invitation.token)
               |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
               |> Ash.Changeset.for_update(:accept, %{})
               |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
    end

    test "rejects invitation when user is already a member" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)

      create_membership!(organization, member, :member)

      invitation = create_invitation!(organization, owner, member.email)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:token, invitation.token)
               |> Ash.Changeset.set_argument(:accepting_user_id, member.id)
               |> Ash.Changeset.for_update(:accept, %{})
               |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
    end
  end

  describe "resend/2" do
    test "generates new token and expiration date" do
      owner = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, "invited@example.com")

      original_token = invitation.token
      original_expires_at = invitation.expires_at

      {:ok, resent_invitation} =
        invitation
        |> Ash.Changeset.for_update(:resend, %{})
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      assert resent_invitation.token != original_token
      assert DateTime.compare(resent_invitation.expires_at, original_expires_at) in [:gt, :eq]
      assert byte_size(resent_invitation.token) == 32
    end
  end

  describe "by_token/1" do
    test "finds valid invitation by token, excludes invalid/accepted/expired" do
      owner = create_user!()
      accepting_user = create_user!()
      organization = create_organization!(owner)

      valid_invitation = create_invitation!(organization, owner, "valid@example.com")
      accepted_invitation = create_invitation!(organization, owner, accepting_user.email)

      {:ok, _accepted} =
        accepted_invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:token, accepted_invitation.token)
        |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
        |> Ash.Changeset.for_update(:accept, %{})
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      for {token, description, expected} <- [
            {valid_invitation.token, "valid token", {:ok, valid_invitation.id}},
            {"invalid-token", "invalid token", {:ok, nil}},
            {accepted_invitation.token, "accepted invitation", {:ok, nil}}
          ] do
        result =
          Invitation
          |> Ash.Query.for_read(:by_token, %{token: token})
          |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

        case expected do
          {:ok, nil} ->
            assert {:ok, nil} = result, "#{description} should not be found"

          {:ok, expected_id} ->
            assert {:ok, found} = result, "#{description} should be found"
            assert found.id == expected_id
        end
      end
    end
  end

  describe "authorization - create" do
    test "only owner and admins can create invitations" do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, admin, :admin)
      create_membership!(organization, member, :member)

      # Owner and admin can create invitations
      for {actor, description} <- [
            {owner, "owner"},
            {admin, "admin"}
          ] do
        assert {:ok, _invitation} =
                 Invitation
                 |> Ash.Changeset.new()
                 |> Ash.Changeset.set_argument(:organization_id, organization.id)
                 |> Ash.Changeset.set_argument(:invited_by_id, actor.id)
                 |> Ash.Changeset.for_create(:create, %{
                   email: "invited-#{System.unique_integer()}@example.com"
                 })
                 |> Ash.create(domain: JidoHub.Organizations, actor: actor),
               "#{description} should be able to create invitation"
      end

      # Member and non-member cannot create invitations
      for {actor, description} <- [
            {member, "member"},
            {non_member, "non-member"}
          ] do
        assert {:error, %Ash.Error.Forbidden{}} =
                 Invitation
                 |> Ash.Changeset.new()
                 |> Ash.Changeset.set_argument(:organization_id, organization.id)
                 |> Ash.Changeset.set_argument(:invited_by_id, actor.id)
                 |> Ash.Changeset.for_create(:create, %{
                   email: "invited-#{System.unique_integer()}@example.com"
                 })
                 |> Ash.create(domain: JidoHub.Organizations, actor: actor),
               "#{description} should not be able to create invitation"
      end
    end
  end

  describe "authorization - read" do
    test "owner and admins can read, non-members cannot" do
      owner = create_user!()
      admin = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, admin, :admin)
      invitation = create_invitation!(organization, owner, "invited@example.com")

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {admin, "admin", :ok},
            {non_member, "non-member", :error}
          ] do
        result =
          Ash.get(Invitation, invitation.id,
            domain: JidoHub.Organizations,
            actor: actor
          )

        case expected do
          :ok ->
            assert {:ok, fetched} = result, "#{description} should read invitation"
            assert fetched.id == invitation.id

          :error ->
            assert {:error, %Ash.Error.Invalid{}} = result,
                   "#{description} should not read invitation"
        end
      end
    end

    test "anyone can read invitation by token" do
      owner = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, "invited@example.com")

      {:ok, found_invitation} =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      assert found_invitation.id == invitation.id
    end
  end

  describe "authorization - update" do
    test "owner and admins can resend, non-members cannot" do
      owner = create_user!()
      admin = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, admin, :admin)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {admin, "admin", :ok},
            {non_member, "non-member", :forbidden}
          ] do
        invitation =
          create_invitation!(organization, owner, "test-#{System.unique_integer()}@example.com")

        result =
          invitation
          |> Ash.Changeset.for_update(:resend, %{})
          |> Ash.update(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert {:ok, _resent} = result, "#{description} should resend invitation"

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not resend invitation"
        end
      end
    end

    test "can accept invitation with valid token" do
      owner = create_user!()
      accepting_user = create_user!()
      organization = create_organization!(owner)
      invitation = create_invitation!(organization, owner, accepting_user.email)

      assert {:ok, _accepted} =
               invitation
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:token, invitation.token)
               |> Ash.Changeset.set_argument(:accepting_user_id, accepting_user.id)
               |> Ash.Changeset.for_update(:accept, %{})
               |> Ash.update(domain: JidoHub.Organizations, authorize?: false)
    end
  end

  describe "authorization - destroy" do
    test "owner and admins can delete, non-members cannot" do
      owner = create_user!()
      admin = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      create_membership!(organization, admin, :admin)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {admin, "admin", :ok},
            {non_member, "non-member", :forbidden}
          ] do
        invitation =
          create_invitation!(organization, owner, "test-#{System.unique_integer()}@example.com")

        result =
          invitation
          |> Ash.Changeset.for_destroy(:destroy)
          |> Ash.destroy(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert :ok = result, "#{description} should delete invitation"

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not delete invitation"
        end
      end
    end
  end
end
