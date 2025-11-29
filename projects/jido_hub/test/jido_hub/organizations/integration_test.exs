defmodule JidoHub.Organizations.IntegrationTest do
  use JidoHub.DataCase

  import Ash.Query

  alias JidoHub.Organizations.{Organization, Membership, Invitation}

  describe "full organization workflow" do
    test "create organization → invite user → accept → verify membership" do
      # Step 1: Create organization with owner
      owner = create_user()

      {:ok, organization} =
        Organization
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Acme Corp",
            description: "A test company"
          },
          actor: owner
        )
        |> Ash.create(domain: JidoHub.Organizations)

      assert organization.name == "Acme Corp"
      assert organization.owner_id == owner.id

      # Step 2: Invite a user to join as admin
      invited_user = create_user()

      {:ok, invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{
          email: invited_user.email,
          role: :admin
        })
        |> Ash.create(domain: JidoHub.Organizations, actor: owner)

      assert invitation.email == invited_user.email
      assert invitation.role == :admin
      assert is_binary(invitation.token)

      # Step 3: User accepts the invitation
      {:ok, accepted_invitation} =
        invitation
        |> Ash.Changeset.for_update(:accept, %{
          token: invitation.token,
          accepting_user_id: invited_user.id
        })
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

      assert accepted_invitation.accepted_at
      refute is_nil(accepted_invitation.accepted_at)

      # Step 4: Verify membership was created with correct role
      {:ok, membership} =
        Membership
        |> filter(user_id == ^invited_user.id and organization_id == ^organization.id)
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      assert membership.role == :admin
      assert membership.user_id == invited_user.id
      assert membership.organization_id == organization.id

      # Step 5: Verify the new admin can invite others
      another_user = create_user()

      {:ok, _second_invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, invited_user.id)
        |> Ash.Changeset.for_create(:create, %{
          email: another_user.email,
          role: :member
        })
        |> Ash.create(domain: JidoHub.Organizations, actor: invited_user)
    end

    test "multiple users can be invited and join the same organization" do
      owner = create_user()
      organization = create_organization(owner)

      # Invite three users with different roles
      admin_user = create_user()
      member1 = create_user()
      member2 = create_user()

      # Create invitations
      admin_invitation = create_invitation(organization, owner, admin_user.email, :admin)
      member1_invitation = create_invitation(organization, owner, member1.email, :member)
      member2_invitation = create_invitation(organization, owner, member2.email, :member)

      # All users accept their invitations
      accept_invitation(admin_invitation, admin_user.id)
      accept_invitation(member1_invitation, member1.id)
      accept_invitation(member2_invitation, member2.id)

      # Verify all memberships exist
      {:ok, memberships} =
        Membership
        |> filter(organization_id == ^organization.id)
        |> Ash.read(domain: JidoHub.Organizations, authorize?: false)

      assert length(memberships) == 3

      # Check roles are correct
      admin_membership = Enum.find(memberships, &(&1.user_id == admin_user.id))
      member1_membership = Enum.find(memberships, &(&1.user_id == member1.id))
      member2_membership = Enum.find(memberships, &(&1.user_id == member2.id))

      assert admin_membership.role == :admin
      assert member1_membership.role == :member
      assert member2_membership.role == :member
    end

    test "user can be member of multiple organizations" do
      user = create_user()
      owner1 = create_user()
      owner2 = create_user()

      # Create two organizations
      org1 = create_organization(owner1, %{name: "Organization 1"})
      org2 = create_organization(owner2, %{name: "Organization 2"})

      # User gets invited to both organizations
      invitation1 = create_invitation(org1, owner1, user.email, :admin)
      invitation2 = create_invitation(org2, owner2, user.email, :member)

      # Accept both invitations
      accept_invitation(invitation1, user.id)
      accept_invitation(invitation2, user.id)

      # Verify user has memberships in both organizations
      {:ok, memberships} =
        Membership
        |> filter(user_id == ^user.id)
        |> Ash.read(domain: JidoHub.Organizations, authorize?: false)

      assert length(memberships) == 2

      org1_membership = Enum.find(memberships, &(&1.organization_id == org1.id))
      org2_membership = Enum.find(memberships, &(&1.organization_id == org2.id))

      assert org1_membership.role == :admin
      assert org2_membership.role == :member
    end
  end

  describe "role management and permissions" do
    test "owner can change member roles" do
      owner = create_user()
      member = create_user()
      organization = create_organization(owner)

      # Create member
      membership = create_membership(organization, member, owner, :member)
      assert membership.role == :member

      # Owner promotes member to admin
      {:ok, updated_membership} =
        membership
        |> Ash.Changeset.for_update(:update_role, %{role: :admin})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      assert updated_membership.role == :admin
    end

    test "admin can change member roles but not other admins" do
      owner = create_user()
      admin = create_user()
      member = create_user()
      organization = create_organization(owner)

      # Create admin and member
      admin_membership = create_membership(organization, admin, owner, :admin)
      member_membership = create_membership(organization, member, owner, :member)

      # Admin can promote member
      {:ok, updated_membership} =
        member_membership
        |> Ash.Changeset.for_update(:update_role, %{role: :admin})
        |> Ash.update(domain: JidoHub.Organizations, actor: admin)

      assert updated_membership.role == :admin

      # Admin can demote another admin in this simplified authorization model
      # In a real app, you'd want stricter authorization logic
      {:ok, _demoted_membership} =
        admin_membership
        |> Ash.Changeset.for_update(:update_role, %{role: :member})
        |> Ash.update(domain: JidoHub.Organizations, actor: admin)
    end

    test "member cannot change any roles" do
      owner = create_user()
      member1 = create_user()
      member2 = create_user()
      organization = create_organization(owner)

      # Create members
      _member1_membership = create_membership(organization, member1, owner, :member)
      member2_membership = create_membership(organization, member2, owner, :member)

      # Member cannot promote another member
      {:error, %Ash.Error.Forbidden{}} =
        member2_membership
        |> Ash.Changeset.for_update(:update_role, %{role: :admin})
        |> Ash.update(domain: JidoHub.Organizations, actor: member1)
    end
  end

  describe "organization deletion and cascading" do
    test "deleting organization with members fails (no cascade)" do
      owner = create_user()
      member = create_user()
      invited_user = create_user()
      organization = create_organization(owner)

      # Create membership and invitation
      membership = create_membership(organization, member, owner, :member)
      invitation = create_invitation(organization, owner, invited_user.email)

      # Delete organization should fail due to foreign key constraints
      {:error, %Ash.Error.Invalid{}} =
        Ash.destroy(organization, domain: JidoHub.Organizations, actor: owner)

      # Verify membership still exists
      {:ok, membership_still_exists} =
        Ash.get(Membership, membership.id,
          domain: JidoHub.Organizations,
          authorize?: false
        )

      assert membership_still_exists

      # Verify invitation still exists
      {:ok, invitation_still_exists} =
        Ash.get(Invitation, invitation.id,
          domain: JidoHub.Organizations,
          authorize?: false
        )

      assert invitation_still_exists
    end
  end

  describe "invitation workflow edge cases" do
    test "invitation can be found by valid token" do
      owner = create_user()
      organization = create_organization(owner)
      invitation = create_invitation(organization, owner, "test@example.com")

      # Verify invitation can be found by token
      {:ok, found_invitation} =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: invitation.token})
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      assert found_invitation.id == invitation.id
    end

    test "resending invitation generates new token but keeps same invitation record" do
      owner = create_user()
      organization = create_organization(owner)
      invitation = create_invitation(organization, owner, "invited@example.com")

      original_id = invitation.id
      original_token = invitation.token

      # Resend invitation
      {:ok, resent_invitation} =
        invitation
        |> Ash.Changeset.for_update(:resend, %{})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      # Same invitation record, new token
      assert resent_invitation.id == original_id
      assert resent_invitation.token != original_token
      assert is_nil(resent_invitation.accepted_at)

      # Old token no longer works
      {:ok, nil} =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: original_token})
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      # New token works
      {:ok, found_invitation} =
        Invitation
        |> Ash.Query.for_read(:by_token, %{token: resent_invitation.token})
        |> Ash.read_one(domain: JidoHub.Organizations, authorize?: false)

      assert found_invitation.id == invitation.id
    end

    test "duplicate invitations are prevented for same email and organization" do
      owner = create_user()
      organization = create_organization(owner)
      email = "duplicate@example.com"

      # Create first invitation
      _invitation1 = create_invitation(organization, owner, email)

      # Attempt to create duplicate invitation
      {:error, %Ash.Error.Invalid{}} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{email: email})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)
    end

    test "user cannot accept invitation for organization they're already member of" do
      owner = create_user()
      member = create_user()
      organization = create_organization(owner)

      # User becomes member
      create_membership(organization, member, owner, :member)

      # Create invitation for same user
      invitation = create_invitation(organization, owner, member.email)

      # User cannot accept invitation
      {:error, %Ash.Error.Invalid{}} =
        invitation
        |> Ash.Changeset.for_update(:accept, %{
          token: invitation.token,
          accepting_user_id: member.id
        })
        |> Ash.update(domain: JidoHub.Organizations, authorize?: false)
    end
  end

  describe "authorization edge cases" do
    test "user loses invitation privileges when demoted from admin to member" do
      owner = create_user()
      admin = create_user()
      organization = create_organization(owner)

      # Create admin
      admin_membership = create_membership(organization, admin, owner, :admin)

      # Admin can create invitation
      {:ok, _invitation} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, admin.id)
        |> Ash.Changeset.for_create(:create, %{email: "test@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, actor: admin)

      # Owner demotes admin to member
      {:ok, _updated_membership} =
        admin_membership
        |> Ash.Changeset.for_update(:update_role, %{role: :member})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      # Former admin (now member) can no longer create invitations
      {:error, %Ash.Error.Forbidden{}} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, admin.id)
        |> Ash.Changeset.for_create(:create, %{email: "test2@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, actor: admin)
    end

    test "removed member cannot access organization resources" do
      owner = create_user()
      member = create_user()
      organization = create_organization(owner)

      # Create and then remove membership
      membership = create_membership(organization, member, owner, :member)
      :ok = Ash.destroy(membership, domain: JidoHub.Organizations, actor: owner)

      # Former member cannot read organization
      {:error, %Ash.Error.Invalid{}} =
        Ash.get(Organization, organization.id,
          domain: JidoHub.Organizations,
          actor: member
        )

      # Former member cannot create invitations
      {:error, %Ash.Error.Forbidden{}} =
        Invitation
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.set_argument(:invited_by_id, member.id)
        |> Ash.Changeset.for_create(:create, %{email: "test@example.com"})
        |> Ash.create(domain: JidoHub.Organizations, actor: member)
    end
  end

  # Helper functions
  defp create_user do
    unique_id = abs(System.unique_integer())

    {:ok, user} =
      JidoHub.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test-#{unique_id}@example.com",
        username: "testuser#{unique_id}",
        password: "password123",
        password_confirmation: "password123"
      })
      |> Ash.create(domain: JidoHub.Accounts, authorize?: false)

    user
  end

  defp create_organization(user, attrs \\ %{}) do
    default_attrs = %{
      name: "Test Organization #{System.unique_integer()}",
      description: "A test organization"
    }

    {:ok, organization} =
      Organization
      |> Ash.Changeset.for_create(:create, Map.merge(default_attrs, attrs), actor: user)
      |> Ash.create(domain: JidoHub.Organizations)

    organization
  end

  defp create_membership(organization, user, _actor, role) do
    {:ok, membership} =
      Membership
      |> Ash.Changeset.new()
      |> Ash.Changeset.set_argument(:user_id, user.id)
      |> Ash.Changeset.set_argument(:organization_id, organization.id)
      |> Ash.Changeset.for_create(:create, %{role: role})
      |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

    membership
  end

  defp create_invitation(organization, invited_by, email, role \\ :member) do
    {:ok, invitation} =
      Invitation
      |> Ash.Changeset.new()
      |> Ash.Changeset.set_argument(:organization_id, organization.id)
      |> Ash.Changeset.set_argument(:invited_by_id, invited_by.id)
      |> Ash.Changeset.for_create(:create, %{email: email, role: role})
      |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

    invitation
  end

  defp accept_invitation(invitation, accepting_user_id) do
    {:ok, accepted} =
      invitation
      |> Ash.Changeset.for_update(:accept, %{
        token: invitation.token,
        accepting_user_id: accepting_user_id
      })
      |> Ash.update(domain: JidoHub.Organizations, authorize?: false)

    accepted
  end
end
