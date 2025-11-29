defmodule JidoHub.Authorization.TenantIsolationTest do
  @moduledoc """
  Tests tenant isolation ensuring cross-user and cross-org data isolation.
  """
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User
  alias JidoHub.Organizations.{Organization, Membership}
  alias JidoHub.Pods.Pod

  describe "cross-user isolation" do
    test "user cannot see another user's private pods" do
      user1 = create_user!()
      user2 = create_user!()

      pod1 = create_pod!(user1, :user, visibility: :private)
      _pod2 = create_pod!(user2, :user, visibility: :private)

      {:ok, user1_pods} = Ash.read(Pod, actor: user1, authorize?: true)
      pod_ids = Enum.map(user1_pods, & &1.id)

      assert pod1.id in pod_ids
      refute _pod2.id in pod_ids
    end

    test "user cannot update another user's pod" do
      user1 = create_user!()
      user2 = create_user!()
      pod2 = create_pod!(user2, :user, visibility: :private)

      assert {:error, %Ash.Error.Forbidden{}} =
               pod2
               |> Ash.Changeset.for_update(:update, %{})
               |> Ash.update(actor: user1, authorize?: true, domain: JidoHub.Pods)
    end

    test "user cannot delete another user's pod" do
      user1 = create_user!()
      user2 = create_user!()
      pod2 = create_pod!(user2, :user, visibility: :private)

      assert {:error, %Ash.Error.Forbidden{}} =
               pod2
               |> Ash.Changeset.for_destroy(:destroy)
               |> Ash.destroy(actor: user1, authorize?: true, domain: JidoHub.Pods)
    end
  end

  describe "cross-organization isolation" do
    test "org members cannot see other org's private pods" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      pod1 = create_pod!(org1.org, :organization, visibility: :private)
      _pod2 = create_pod!(org2.org, :organization, visibility: :private)

      {:ok, member1_pods} = Ash.read(Pod, actor: org1.member, authorize?: true)
      pod_ids = Enum.map(member1_pods, & &1.id)

      assert pod1.id in pod_ids
      refute _pod2.id in pod_ids
    end

    test "org members cannot update other org's pods" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      pod2 = create_pod!(org2.org, :organization, visibility: :private)

      assert {:error, %Ash.Error.Forbidden{}} =
               pod2
               |> Ash.Changeset.for_update(:update, %{})
               |> Ash.update(actor: org1.member, authorize?: true, domain: JidoHub.Pods)
    end

    test "org members cannot see other org's organizations" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      {:ok, member1_orgs} =
        Ash.read(Organization,
          actor: org1.member,
          authorize?: true,
          domain: JidoHub.Organizations
        )

      org_ids = Enum.map(member1_orgs, & &1.id)

      assert org1.org.id in org_ids
      refute org2.org.id in org_ids
    end

    test "org members cannot see other org's memberships" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      {:ok, member1_memberships} =
        Ash.read(Membership, actor: org1.member, authorize?: true, domain: JidoHub.Organizations)

      membership_org_ids = Enum.map(member1_memberships, & &1.organization_id)

      assert org1.org.id in membership_org_ids
      refute org2.org.id in membership_org_ids
    end

    test "org members cannot update other org's organizations" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      assert {:error, %Ash.Error.Forbidden{}} =
               org2.org
               |> Ash.Changeset.for_update(:update, %{name: "Hacked Name"})
               |> Ash.update(actor: org1.member, authorize?: true, domain: JidoHub.Organizations)
    end

    test "org members cannot add members to other orgs" do
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()
      new_user = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Membership
               |> Ash.Changeset.for_create(:create, %{
                 organization_id: org2.org.id,
                 user_id: new_user.id,
                 role: :member
               })
               |> Ash.create(actor: org1.member, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "public resource visibility across tenants" do
    test "users can see public pods from other users" do
      user1 = create_user!()
      user2 = create_user!()

      _pod1_private = create_pod!(user1, :user, visibility: :private)
      pod1_public = create_pod!(user1, :user, visibility: :public)

      {:ok, user2_pods} = Ash.read(Pod, actor: user2, authorize?: true)
      pod_ids = Enum.map(user2_pods, & &1.id)

      assert pod1_public.id in pod_ids
      refute _pod1_private.id in pod_ids
    end

    test "users can see public pods from other orgs" do
      org = create_org_with_member!()
      other_user = create_user!()

      _pod_private = create_pod!(org.org, :organization, visibility: :private)
      pod_public = create_pod!(org.org, :organization, visibility: :public)

      {:ok, other_user_pods} = Ash.read(Pod, actor: other_user, authorize?: true)
      pod_ids = Enum.map(other_user_pods, & &1.id)

      assert pod_public.id in pod_ids
      refute _pod_private.id in pod_ids
    end
  end

  describe "admin override capabilities" do
    test "admin users can list all organizations via admin_index" do
      admin = create_admin!()
      org1 = create_org_with_member!()
      org2 = create_org_with_member!()

      assert {:ok, orgs} =
               Organization
               |> Ash.Query.for_read(:admin_index)
               |> Ash.read(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      org_ids = Enum.map(orgs, & &1.id)
      assert org1.org.id in org_ids
      assert org2.org.id in org_ids
    end

    test "admin users can create organizations for other users" do
      admin = create_admin!()
      target_user = create_user!()

      assert {:ok, org} =
               Organization
               |> Ash.Changeset.for_create(:admin_create, %{
                 name: "Admin Created",
                 owner_id: target_user.id
               })
               |> Ash.create(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert org.owner_id == target_user.id
    end

    test "admin users can update any organization" do
      admin = create_admin!()
      org = create_org_with_member!()

      assert {:ok, updated} =
               org.org
               |> Ash.Changeset.for_update(:admin_update, %{name: "Admin Updated"})
               |> Ash.update(actor: admin, authorize?: true, domain: JidoHub.Organizations)

      assert updated.name == "Admin Updated"
    end

    test "regular users cannot use admin actions" do
      regular_user = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Organization
               |> Ash.Query.for_read(:admin_index)
               |> Ash.read(actor: regular_user, authorize?: true, domain: JidoHub.Organizations)
    end
  end

  describe "unauthenticated access isolation" do
    test "unauthenticated users can only see public pods" do
      user = create_user!()
      org = create_org_with_member!()

      _user_private = create_pod!(user, :user, visibility: :private)
      user_public = create_pod!(user, :user, visibility: :public)
      _org_private = create_pod!(org.org, :organization, visibility: :private)
      org_public = create_pod!(org.org, :organization, visibility: :public)

      {:ok, public_pods} = Ash.read(Pod, actor: nil, authorize?: true)
      pod_ids = Enum.map(public_pods, & &1.id)

      assert user_public.id in pod_ids
      assert org_public.id in pod_ids
      refute _user_private.id in pod_ids
      refute _org_private.id in pod_ids
    end

    test "unauthenticated users cannot see organizations" do
      org = create_org_with_member!()

      {:ok, orgs} =
        Ash.read(Organization, actor: nil, authorize?: true, domain: JidoHub.Organizations)

      org_ids = Enum.map(orgs, & &1.id)
      refute org.org.id in org_ids
    end

    test "unauthenticated users cannot create pods" do
      user = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Pod
               |> Ash.Changeset.for_create(:create, %{
                 name: "Unauthorized Pod",
                 owner_type: :user,
                 owner_id: user.id
               })
               |> Ash.create(actor: nil, authorize?: true, domain: JidoHub.Pods)
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

  defp create_org_with_member! do
    owner = create_user!()
    member = create_user!()

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "org-#{System.unique_integer([:positive])}"},
        actor: owner
      )
      |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)

    Membership
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      user_id: member.id,
      role: :member
    })
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)

    %{org: org, owner: owner, member: member}
  end

  defp create_pod!(owner, owner_type, attrs) do
    visibility = Keyword.get(attrs, :visibility, :private)
    name_value = Keyword.get(attrs, :name, "pod-#{System.unique_integer([:positive])}")

    create_attrs = %{
      name: name_value,
      owner_type: owner_type,
      owner_id: owner.id
    }

    pod =
      Pod
      |> Ash.Changeset.for_create(:create, create_attrs)
      |> Ash.create!(domain: JidoHub.Pods, authorize?: false)

    if visibility == :private do
      pod
    else
      pod
      |> Ash.Changeset.for_update(:update, %{})
      |> Ash.Changeset.force_change_attribute(:visibility, visibility)
      |> Ash.update!(domain: JidoHub.Pods, authorize?: false)
    end
  end
end
