defmodule JidoHub.Authorization.InvitationAuthorizationTest do
  @moduledoc """
  Tests invitation authorization policies including admin-only creation and bypass validation.
  """
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User
  alias JidoHub.Organizations.{Organization, Invitation}

  describe "invitation creation" do
    test "organization owner can create invitations" do
      owner = create_user!()
      org = create_org!(owner)

      assert {:ok, invitation} =
               Invitation
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 invited_by_id: owner.id,
                 email: "newmember@example.com",
                 role: :member
               })
               |> Ash.create(actor: owner, authorize?: true, domain: JidoHub.Organizations)

      assert to_string(invitation.email) == "newmember@example.com"
      assert invitation.organization_id == org.id
    end

    test "organization admin can create invitations" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)

      assert {:ok, invitation} =
               Invitation
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 invited_by_id: admin.id,
                 email: "newmember@example.com",
                 role: :member
               })
               |> Ash.create(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert to_string(invitation.email) == "newmember@example.com"
    end

    test "regular members cannot create invitations" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Invitation
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 invited_by_id: member.id,
                 email: "newmember@example.com",
                 role: :member
               })
               |> Ash.create(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end

    test "non-members cannot create invitations" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Invitation
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 invited_by_id: non_member.id,
                 email: "newmember@example.com",
                 role: :member
               })
               |> Ash.create(actor: non_member, authorize?: true, domain: JidoHub.Organizations)
    end

    test "unauthenticated users cannot create invitations" do
      owner = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Invitation
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 invited_by_id: owner.id,
                 email: "newmember@example.com",
                 role: :member
               })
               |> Ash.create(actor: nil, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "invitation read access" do
    test "organization owner can view invitations" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)

      assert {:ok, invitations} =
               Ash.read(Invitation, actor: owner, authorize?: true, domain: JidoHub.Organizations)

      assert Enum.any?(invitations, &(&1.id == invitation.id))
    end

    test "organization admin can view invitations" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)
      invitation = create_invitation!(org, owner)

      assert {:ok, invitations} =
               Ash.read(Invitation, actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert Enum.any?(invitations, &(&1.id == invitation.id))
    end

    test "regular members cannot view invitations" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member, :member)
      _invitation = create_invitation!(org, owner)

      assert {:ok, []} =
               Ash.read(Invitation,
                 actor: member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )
    end

    test "non-members cannot view invitations" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)
      _invitation = create_invitation!(org, owner)

      assert {:ok, []} =
               Ash.read(Invitation,
                 actor: non_member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )
    end
  end

  describe "invitation by_token bypass" do
    test "unauthenticated users can read invitations by valid token" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)

      query =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})

      assert {:ok, found} =
               Ash.read_one(query, actor: nil, authorize?: true, domain: JidoHub.Organizations)

      assert found.id == invitation.id
    end

    test "authenticated users can read invitations by valid token" do
      owner = create_user!()
      other_user = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)

      query =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})

      assert {:ok, found} =
               Ash.read_one(query,
                 actor: other_user,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      assert found.id == invitation.id
    end

    test "by_token does not return expired invitations" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_expired_invitation!(org, owner)

      query =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})

      assert {:ok, nil} =
               Ash.read_one(query, actor: nil, authorize?: true, domain: JidoHub.Organizations)
    end

    test "by_token does not return accepted invitations" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_accepted_invitation!(org, owner)

      query =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})

      assert {:ok, nil} =
               Ash.read_one(query, actor: nil, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "invitation acceptance bypass" do
    test "unauthenticated users can accept invitations with valid token" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)
      new_user = create_user!(%{email: invitation.email})

      assert {:ok, updated} =
               invitation
               |> Ash.Changeset.for_update(:accept, %{
                 token: invitation.token,
                 accepting_user_id: new_user.id
               })
               |> Ash.update(actor: nil, authorize?: true, domain: JidoHub.Organizations)

      refute is_nil(updated.accepted_at)
    end

    test "accepting invitation creates membership" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)
      new_user = create_user!(%{email: invitation.email})

      invitation
      |> Ash.Changeset.for_update(:accept, %{
        token: invitation.token,
        accepting_user_id: new_user.id
      })
      |> Ash.update!(
        domain: JidoHub.Organizations,
        authorize?: false
      )

      assert {:ok, orgs} =
               Ash.read(Organization,
                 actor: new_user,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      org_ids = Enum.map(orgs, & &1.id)
      assert org.id in org_ids
    end
  end

  describe "invitation resend access" do
    test "organization owner can resend invitations" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)
      original_token = invitation.token

      assert {:ok, updated} =
               invitation
               |> Ash.Changeset.for_update(:resend, %{})
               |> Ash.update(actor: owner, authorize?: true, domain: JidoHub.Organizations)

      refute updated.token == original_token
    end

    test "organization admin can resend invitations" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)
      invitation = create_invitation!(org, owner)

      assert {:ok, _updated} =
               invitation
               |> Ash.Changeset.for_update(:resend, %{})
               |> Ash.update(actor: admin, authorize?: true, domain: JidoHub.Organizations)
    end

    test "regular members cannot resend invitations" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member, :member)
      invitation = create_invitation!(org, owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               invitation
               |> Ash.Changeset.for_update(:resend, %{})
               |> Ash.update(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "invitation destroy access" do
    test "organization owner can delete invitations" do
      owner = create_user!()
      org = create_org!(owner)
      invitation = create_invitation!(org, owner)

      assert :ok =
               invitation
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: owner, authorize?: true, domain: JidoHub.Organizations)
    end

    test "organization admin can delete invitations" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)
      invitation = create_invitation!(org, owner)

      assert :ok =
               invitation
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: admin, authorize?: true, domain: JidoHub.Organizations)
    end

    test "regular members cannot delete invitations" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member, :member)
      invitation = create_invitation!(org, owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               invitation
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  # Helper functions
  defp create_user!(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      email: "user-#{unique_id}@example.com",
      username: "user-#{unique_id}",
      password: "password123",
      password_confirmation: "password123"
    }

    attrs = Map.merge(default_attrs, Map.new(attrs))

    User
    |> Ash.Changeset.for_create(:register_with_password, attrs)
    |> Ash.create!(domain: JidoHub.Accounts, authorize?: false)
  end

  defp create_org!(owner, attrs \\ %{}) do
    default_attrs = %{
      name: "org-#{System.unique_integer([:positive])}"
    }

    attrs = Map.merge(default_attrs, Map.new(attrs))

    Organization
    |> Ash.Changeset.for_create(:create, attrs, actor: owner)
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
  end

  defp create_membership!(org, user, role) do
    alias JidoHub.Organizations.Membership

    Membership
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      user_id: user.id,
      role: role
    })
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
  end

  defp create_invitation!(org, invited_by, attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      email: "invite-#{unique_id}@example.com",
      role: :member
    }

    attrs = Map.merge(default_attrs, Map.new(attrs))

    Invitation
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{
        organization_id: org.id,
        invited_by_id: invited_by.id
      })
    )
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
  end

  defp create_expired_invitation!(org, invited_by) do
    invitation = create_invitation!(org, invited_by)
    expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

    invitation
    |> Ecto.Changeset.change(%{expires_at: expired_at})
    |> JidoHub.Repo.update!()
  end

  defp create_accepted_invitation!(org, invited_by) do
    invitation = create_invitation!(org, invited_by)
    accepted_at = DateTime.utc_now() |> DateTime.truncate(:second)

    invitation
    |> Ecto.Changeset.change(%{accepted_at: accepted_at})
    |> JidoHub.Repo.update!()
  end
end
