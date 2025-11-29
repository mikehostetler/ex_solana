defmodule JidoHub.Authorization.MembershipAuthorizationTest do
  @moduledoc """
  Tests membership authorization policies including self-access and admin management.
  """
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User
  alias JidoHub.Organizations.{Organization, Membership}

  describe "membership creation" do
    test "organization owner can create memberships" do
      owner = create_user!()
      new_member = create_user!()
      org = create_org!(owner)

      assert {:ok, membership} =
               Membership
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 user_id: new_member.id,
                 role: :member
               })
               |> Ash.create(actor: owner, authorize?: true, domain: JidoHub.Organizations)

      assert membership.user_id == new_member.id
      assert membership.organization_id == org.id
    end

    test "organization admin can create memberships" do
      owner = create_user!()
      admin = create_user!()
      new_member = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)

      assert {:ok, membership} =
               Membership
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 user_id: new_member.id,
                 role: :member
               })
               |> Ash.create(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert membership.user_id == new_member.id
    end

    test "regular members cannot create memberships" do
      owner = create_user!()
      member = create_user!()
      new_member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Membership
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 user_id: new_member.id,
                 role: :member
               })
               |> Ash.create(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end

    test "non-members cannot create memberships" do
      owner = create_user!()
      non_member = create_user!()
      target_user = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Membership
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org.id,
                 user_id: target_user.id,
                 role: :member
               })
               |> Ash.create(actor: non_member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "membership read access" do
    test "users can view their own memberships" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member)

      assert {:ok, memberships} =
               Ash.read(Membership,
                 actor: member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      assert Enum.any?(memberships, &(&1.id == membership.id))
    end

    test "organization owner can view all org memberships" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      org = create_org!(owner)
      m1 = create_membership!(org, member1)
      m2 = create_membership!(org, member2)

      assert {:ok, memberships} =
               Ash.read(Membership, actor: owner, authorize?: true, domain: JidoHub.Organizations)

      membership_ids = Enum.map(memberships, & &1.id)
      assert m1.id in membership_ids
      assert m2.id in membership_ids
    end

    test "organization members can view other members in same org" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      org = create_org!(owner)
      m1 = create_membership!(org, member1)
      m2 = create_membership!(org, member2)

      assert {:ok, memberships} =
               Ash.read(Membership,
                 actor: member1,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      membership_ids = Enum.map(memberships, & &1.id)
      assert m1.id in membership_ids
      assert m2.id in membership_ids
    end

    test "users cannot view memberships from orgs they don't belong to" do
      owner1 = create_user!()
      owner2 = create_user!()
      member1 = create_user!()
      org1 = create_org!(owner1)
      _org2 = create_org!(owner2)
      _m1 = create_membership!(org1, member1)

      assert {:ok, memberships} =
               Ash.read(Membership,
                 actor: owner2,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      membership_ids = Enum.map(memberships, & &1.id)
      refute _m1.id in membership_ids
    end
  end

  describe "membership update access" do
    test "organization owner can update member roles" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member, :member)

      assert {:ok, updated} =
               membership
               |> Ash.Changeset.for_update(:update_role, %{role: :admin})
               |> Ash.update(actor: owner, authorize?: true, domain: JidoHub.Organizations)

      assert updated.role == :admin
    end

    test "organization admin can update member roles" do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)
      membership = create_membership!(org, member, :member)

      assert {:ok, updated} =
               membership
               |> Ash.Changeset.for_update(:update_role, %{role: :admin})
               |> Ash.update(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert updated.role == :admin
    end

    test "regular members cannot update roles" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      org = create_org!(owner)
      create_membership!(org, member1, :member)
      membership2 = create_membership!(org, member2, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership2
               |> Ash.Changeset.for_update(:update_role, %{role: :admin})
               |> Ash.update(actor: member1, authorize?: true, domain: JidoHub.Organizations)
    end

    test "non-members cannot update roles" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_update(:update_role, %{role: :admin})
               |> Ash.update(actor: non_member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "membership destroy access" do
    test "organization owner can remove members" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member)

      assert :ok =
               membership
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: owner, authorize?: true, domain: JidoHub.Organizations)
    end

    test "organization admin can remove members" do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, admin, :admin)
      membership = create_membership!(org, member)

      assert :ok =
               membership
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: admin, authorize?: true, domain: JidoHub.Organizations)
    end

    test "regular members cannot remove other members" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      org = create_org!(owner)
      create_membership!(org, member1, :member)
      membership2 = create_membership!(org, member2)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership2
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: member1, authorize?: true, domain: JidoHub.Organizations)
    end

    test "non-members cannot remove members" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: non_member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "membership isolation" do
    test "users only see memberships from their organizations" do
      user1 = create_user!()
      user2 = create_user!()
      org1 = create_org!(user1)
      org2 = create_org!(user2)
      m1 = create_membership!(org1, user1)
      _m2 = create_membership!(org2, user2)

      {:ok, memberships} =
        Ash.read(Membership, actor: user1, authorize?: true, domain: JidoHub.Organizations)

      membership_ids = Enum.map(memberships, & &1.id)
      assert m1.id in membership_ids
      refute _m2.id in membership_ids
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

  defp create_membership!(org, user, role \\ :member) do
    Membership
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      user_id: user.id,
      role: role
    })
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
  end
end
