defmodule JidoHub.Authorization.OrganizationAuthorizationTest do
  @moduledoc """
  Tests organization authorization policies including member access and isolation.
  """
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User
  alias JidoHub.Organizations.{Organization, Membership}

  describe "organization creation" do
    test "authenticated users can create organizations" do
      user = create_user!()

      assert {:ok, org} =
               Organization
               |> Ash.Changeset.for_create(:create, %{name: "Test Org"}, actor: user)
               |> Ash.create(authorize?: true, domain: JidoHub.Organizations)

      assert org.name == "Test Org"
      assert org.owner_id == user.id
    end

    test "unauthenticated users cannot create organizations" do
      # Without an actor, the owner relationship fails validation (Invalid error)
      # rather than authorization (Forbidden error), but the end result is the same
      assert {:error, %Ash.Error.Invalid{}} =
               Organization
               |> Ash.Changeset.for_create(:create, %{name: "Test Org"})
               |> Ash.create(actor: nil, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "organization read access" do
    test "owner can read their organization" do
      owner = create_user!()
      org = create_org!(owner)

      assert {:ok, [found_org]} =
               Ash.read(Organization,
                 actor: owner,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      assert found_org.id == org.id
    end

    test "members can read their organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member)

      assert {:ok, [found_org]} =
               Ash.read(Organization,
                 actor: member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      assert found_org.id == org.id
    end

    test "non-members cannot read other organizations" do
      owner = create_user!()
      non_member = create_user!()
      _org = create_org!(owner)

      assert {:ok, []} =
               Ash.read(Organization,
                 actor: non_member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )
    end

    test "unauthenticated users cannot read organizations" do
      owner = create_user!()
      _org = create_org!(owner)

      assert {:ok, []} =
               Ash.read(Organization, actor: nil, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "organization update access" do
    test "owner can update their organization" do
      owner = create_user!()
      org = create_org!(owner)

      assert {:ok, updated} =
               org
               |> Ash.Changeset.for_update(:update, %{name: "Updated Name"})
               |> Ash.update(actor: owner, authorize?: true, domain: JidoHub.Organizations)

      assert updated.name == "Updated Name"
    end

    test "members cannot update organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(:update, %{name: "Hacked Name"})
               |> Ash.update(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end

    test "non-members cannot update organization" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(:update, %{name: "Hacked Name"})
               |> Ash.update(actor: non_member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "organization destroy access" do
    test "owner can destroy their organization" do
      owner = create_user!()
      org = create_org!(owner)

      assert :ok =
               org
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: owner, authorize?: true, domain: JidoHub.Organizations)
    end

    test "members cannot destroy organization" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      create_membership!(org, member)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "organization isolation" do
    test "user can only see organizations they own or are members of" do
      user1 = create_user!()
      user2 = create_user!()
      user3 = create_user!()

      org1 = create_org!(user1)
      org2 = create_org!(user2)
      create_membership!(org2, user1)
      _org3 = create_org!(user3)

      {:ok, orgs} =
        Ash.read(Organization, actor: user1, authorize?: true, domain: JidoHub.Organizations)

      org_ids = Enum.map(orgs, & &1.id)

      assert org1.id in org_ids
      assert org2.id in org_ids
      refute _org3.id in org_ids
      assert length(org_ids) == 2
    end

    test "removing membership revokes read access" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      membership = create_membership!(org, member)

      assert {:ok, [_]} =
               Ash.read(Organization,
                 actor: member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )

      Ash.destroy!(membership, domain: JidoHub.Organizations, authorize?: false)

      assert {:ok, []} =
               Ash.read(Organization,
                 actor: member,
                 authorize?: true,
                 domain: JidoHub.Organizations
               )
    end
  end

  describe "admin role enforcement" do
    test "admin users can list all organizations" do
      admin = create_admin!()
      user1 = create_user!()
      user2 = create_user!()

      org1 = create_org!(user1)
      org2 = create_org!(user2)

      assert {:ok, orgs} =
               Organization
               |> Ash.Query.for_read(:admin_index)
               |> Ash.read(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      org_ids = Enum.map(orgs, & &1.id)
      assert org1.id in org_ids
      assert org2.id in org_ids
    end

    test "non-admin users cannot use admin_index" do
      regular_user = create_user!()
      _org = create_org!(regular_user)

      assert {:error, %Ash.Error.Forbidden{}} =
               Organization
               |> Ash.Query.for_read(:admin_index)
               |> Ash.read(actor: regular_user, authorize?: true, domain: JidoHub.Organizations)
    end

    test "admin users can create organizations for other users" do
      admin = create_admin!()
      target_user = create_user!()

      assert {:ok, org} =
               Organization
               |> Ash.Changeset.for_create(:admin_create, %{
                 name: "Admin Created Org",
                 owner_id: target_user.id
               })
               |> Ash.create(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert org.owner_id == target_user.id
    end

    test "non-admin users cannot use admin_create" do
      regular_user = create_user!()
      target_user = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Organization
               |> Ash.Changeset.for_create(:admin_create, %{
                 name: "Hacked Org",
                 owner_id: target_user.id
               })
               |> Ash.create(actor: regular_user, authorize?: true, domain: JidoHub.Organizations)
    end

    test "admin users can update any organization" do
      admin = create_admin!()
      user = create_user!()
      org = create_org!(user)

      assert {:ok, updated} =
               org
               |> Ash.Changeset.for_update(:admin_update, %{name: "Admin Updated"})
               |> Ash.update(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert updated.name == "Admin Updated"
    end

    test "non-admin users cannot use admin_update" do
      regular_user = create_user!()
      target_user = create_user!()
      org = create_org!(target_user)

      assert {:error, %Ash.Error.Forbidden{}} =
               org
               |> Ash.Changeset.for_update(:admin_update, %{name: "Hacked"})
               |> Ash.update(actor: regular_user, authorize?: true, domain: JidoHub.Organizations)
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

  defp create_admin! do
    user = create_user!()

    user
    |> Ash.Changeset.for_update(:update, %{})
    |> Ash.Changeset.force_change_attribute(:role, :admin)
    |> Ash.update!(domain: JidoHub.Accounts, authorize?: false)
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
