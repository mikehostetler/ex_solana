defmodule JidoHub.Integration.OrganizationInvitationTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Organizations

  require Ash.Query

  describe "end-to-end invitation flow" do
    test "owner creates invitation, invitee accepts and becomes member" do
      owner = create_user!()
      invitee = create_user!("invitee@example.com", "invitee", "password123")
      org = create_org!(owner)

      {:ok, invitation} =
        Organizations.Invitation
        |> Ash.Changeset.for_create(
          :create,
          %{
            organization_id: org.id,
            invited_by_id: owner.id,
            email: "invitee@example.com",
            role: :admin
          },
          actor: owner
        )
        |> Ash.create(domain: Organizations)

      assert invitation.role == :admin
      assert is_binary(invitation.token)

      {:ok, updated_invitation} =
        invitation
        |> Ash.Changeset.for_update(
          :accept,
          %{
            token: invitation.token,
            accepting_user_id: invitee.id
          },
          actor: invitee
        )
        |> Ash.update(domain: Organizations)

      assert updated_invitation.accepted_at

      {:ok, membership} =
        Organizations.Membership
        |> Ash.Query.filter(user_id == ^invitee.id and organization_id == ^org.id)
        |> Ash.read_one(domain: Organizations, authorize?: false)

      assert membership.role == :admin
      assert membership.user_id == invitee.id
      assert membership.organization_id == org.id
    end

    test "admin can create and manage invitations" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      {:ok, invitation} =
        Organizations.Invitation
        |> Ash.Changeset.for_create(
          :create,
          %{
            organization_id: org.id,
            invited_by_id: admin.id,
            email: "new@example.com",
            role: :member
          },
          actor: admin
        )
        |> Ash.create(domain: Organizations)

      assert invitation.invited_by_id == admin.id

      {:ok, _updated} =
        invitation
        |> Ash.Changeset.for_update(:resend, %{}, actor: admin)
        |> Ash.update(domain: Organizations)

      invitation
      |> Ash.Changeset.for_destroy(:destroy, %{}, actor: admin)
      |> Ash.destroy!(domain: Organizations)

      refute Organizations.Invitation
             |> Ash.Query.filter(id == ^invitation.id)
             |> Ash.exists?(domain: Organizations, authorize?: false)
    end

    test "member cannot create or manage invitations" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      assert {:error, %Ash.Error.Invalid{}} =
               Organizations.Invitation
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   organization_id: org.id,
                   invited_by_id: member.id,
                   email: "new@example.com",
                   role: :member
                 },
                 actor: member
               )
               |> Ash.create(domain: Organizations)

      invitation = create_invitation!(org, owner, "destroy@example.com", :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               invitation
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: member)
               |> Ash.destroy(domain: Organizations)

      {:ok, invitations} =
        Organizations.Invitation
        |> Ash.Query.filter(organization_id == ^org.id)
        |> Ash.read(domain: Organizations, actor: member)

      assert invitations == []
    end

    test "cannot accept with wrong user email" do
      owner = create_user!()
      wrong_user = create_user!("wrong@example.com", "wrong", "password123")
      org = create_org!(owner)

      invitation = create_invitation!(org, owner, "invitee@example.com", :member)

      assert {:error, _error} =
               invitation
               |> Ash.Changeset.for_update(
                 :accept,
                 %{
                   token: invitation.token,
                   accepting_user_id: wrong_user.id
                 },
                 actor: wrong_user
               )
               |> Ash.update(domain: Organizations)
    end

    test "resend rotates token and extends expiration" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner, "resend@example.com", :member)

      original_token = invitation.token

      {:ok, updated} =
        invitation
        |> Ash.Changeset.for_update(:resend, %{}, actor: owner)
        |> Ash.update(domain: Organizations)

      refute updated.token == original_token
      assert DateTime.after?(updated.expires_at, DateTime.utc_now())

      {:ok, nil} =
        Organizations.Invitation
        |> Ash.Query.for_read(:by_token, %{token: original_token})
        |> Ash.read_one(domain: Organizations)
    end

    test "can create new invitation after previous was accepted" do
      owner = create_user!()
      invitee = create_user!("invitee@example.com", "invitee", "password123")
      org = create_org!(owner)

      invitation = create_invitation!(org, owner, "invitee@example.com", :member)

      {:ok, _updated} =
        invitation
        |> Ash.Changeset.for_update(
          :accept,
          %{
            token: invitation.token,
            accepting_user_id: invitee.id
          }
        )
        |> Ash.update(domain: Organizations)

      {:ok, new_invitation} =
        Organizations.Invitation
        |> Ash.Changeset.for_create(
          :create,
          %{
            organization_id: org.id,
            invited_by_id: owner.id,
            email: "invitee@example.com",
            role: :member
          },
          actor: owner
        )
        |> Ash.create(domain: Organizations)

      assert to_string(new_invitation.email) == "invitee@example.com"
    end
  end
end
