defmodule JidoHub.Integration.PodCreationTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods
  alias JidoHub.Pods.Pod

  describe "User-Owned Pods" do
    test "user can create pod with owner_type :user and self as owner" do
      user = create_user!()

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "My Workspace",
            owner_type: :user,
            owner_id: user.id
          },
          actor: user
        )
        |> Ash.create(domain: Pods)

      assert pod.name == "My Workspace"
      assert pod.owner_type == :user
      assert pod.owner_id == user.id
    end

    test "slug is generated from pod name" do
      user = create_user!()

      pod = create_user_pod!(user, "My Cool Project")

      assert pod.slug == "my-cool-project"
    end

    test "full_path returns @username/slug" do
      user = create_user!("alice@test.com", "alice123", "password123")

      pod = create_user_pod!(user, "My Pod")

      pod = reload!(pod, [:full_path])
      assert pod.full_path == "@alice123/my-pod"
    end

    test "user cannot create pod owned by another user (CanCreatePod)" do
      user1 = create_user!()
      user2 = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Hack Pod",
                   owner_type: :user,
                   owner_id: user2.id
                 },
                 actor: user1
               )
               |> Ash.create(domain: Pods)
    end

    test "only pod owner can update user-owned pod" do
      user = create_user!()
      pod = create_user_pod!(user, "Original Name")

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{description: "Updated description"}, actor: user)
        |> Ash.update(domain: Pods)

      assert updated.description == "Updated description"
    end

    test "only pod owner can destroy user-owned pod" do
      user = create_user!()
      pod = create_user_pod!(user, "To Delete")

      assert :ok = Ash.destroy(pod, domain: Pods, actor: user)
    end

    test "non-owner cannot update user-owned pod" do
      owner = create_user!()
      other = create_user!()
      pod = create_user_pod!(owner, "Protected Pod")

      assert {:error, %Ash.Error.Forbidden{}} =
               pod
               |> Ash.Changeset.for_update(:update, %{description: "Hacked"}, actor: other)
               |> Ash.update(domain: Pods)
    end

    test "non-owner cannot destroy user-owned pod" do
      owner = create_user!()
      other = create_user!()
      pod = create_user_pod!(owner, "Protected Pod")

      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(pod, domain: Pods, actor: other)
    end
  end

  describe "Organization-Owned Pods (IsOrgAdmin)" do
    test "org owner can create org-owned pod" do
      owner = create_user!()
      org = create_org!(owner)

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Team Workspace",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert pod.owner_type == :organization
      assert pod.owner_id == org.id
    end

    test "org admin can create org-owned pod" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      {:ok, pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Admin Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: admin
        )
        |> Ash.create(domain: Pods)

      assert pod.owner_type == :organization
      assert pod.owner_id == org.id
    end

    test "org member cannot create org-owned pod (CanCreatePod)" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      assert {:error, %Ash.Error.Forbidden{}} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Member Pod",
                   owner_type: :organization,
                   owner_id: org.id
                 },
                 actor: member
               )
               |> Ash.create(domain: Pods)
    end

    test "non-member cannot create org-owned pod" do
      owner = create_user!()
      outsider = create_user!()
      org = create_org!(owner)

      assert {:error, %Ash.Error.Forbidden{}} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Outsider Pod",
                   owner_type: :organization,
                   owner_id: org.id
                 },
                 actor: outsider
               )
               |> Ash.create(domain: Pods)
    end

    test "slug is generated from pod name" do
      owner = create_user!()
      org = create_org!(owner)

      pod = create_org_pod!(org, owner, "Team Project Alpha")

      assert pod.slug == "team-project-alpha"
    end

    test "full_path returns @org-slug/slug" do
      owner = create_user!()
      org = create_org_with_slug!(owner, "acme-corp")

      pod = create_org_pod!(org, owner, "Main Project")

      pod = reload!(pod, [:full_path])
      assert pod.full_path == "@acme-corp/main-project"
    end

    test "owner calculation returns correct org data (Owner calculation)" do
      owner = create_user!()
      org = create_org!(owner, %{name: "Test Organization"})

      pod = create_org_pod!(org, owner, "Test Pod")

      pod = reload!(pod, [:owner])
      assert pod.owner.id == org.id
      assert pod.owner.name == "Test Organization"
      assert pod.owner.slug == "test-organization"
    end

    test "org owner can update org-owned pod (IsOrgAdmin)" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner, "Original")

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{description: "Owner update"}, actor: owner)
        |> Ash.update(domain: Pods)

      assert updated.description == "Owner update"
    end

    test "org admin can update org-owned pod (IsOrgAdmin)" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      pod = create_org_pod!(org, owner, "Team Pod")

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{description: "Admin update"}, actor: admin)
        |> Ash.update(domain: Pods)

      assert updated.description == "Admin update"
    end

    test "org member cannot update org-owned pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)
      pod = create_org_pod!(org, owner, "Team Pod")

      assert {:error, %Ash.Error.Forbidden{}} =
               pod
               |> Ash.Changeset.for_update(:update, %{description: "Member hack"}, actor: member)
               |> Ash.update(domain: Pods)
    end

    test "org owner can destroy org-owned pod" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner, "To Delete")

      assert :ok = Ash.destroy(pod, domain: Pods, actor: owner)
    end

    test "org admin can destroy org-owned pod" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      pod = create_org_pod!(org, owner, "To Delete")

      assert :ok = Ash.destroy(pod, domain: Pods, actor: admin)
    end

    test "org member cannot destroy org-owned pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)
      pod = create_org_pod!(org, owner, "Protected")

      assert {:error, %Ash.Error.Forbidden{}} = Ash.destroy(pod, domain: Pods, actor: member)
    end
  end

  describe "Pod Slug and Uniqueness" do
    test "same slug allowed across different owners" do
      user1 = create_user!()
      user2 = create_user!()

      pod1 = create_user_pod!(user1, "My Project")
      pod2 = create_user_pod!(user2, "My Project")

      assert pod1.slug == "my-project"
      assert pod2.slug == "my-project"
      assert pod1.id != pod2.id
    end

    test "duplicate slug for same owner fails (unique_slug_per_owner)" do
      user = create_user!()
      _pod1 = create_user_pod!(user, "Test Project")

      assert {:error, error} =
               Pod
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   name: "Different Name",
                   description: "manually set slug",
                   owner_type: :user,
                   owner_id: user.id
                 },
                 actor: user
               )
               |> Ash.Changeset.force_change_attribute(:slug, "test-project")
               |> Ash.create(domain: Pods)

      assert Enum.any?(error.errors, fn e ->
               String.contains?(e.message || "", "already been taken")
             end)
    end

    test "updating pod name regenerates slug (GenerateSlug)" do
      user = create_user!()
      pod = create_user_pod!(user, "Original Name")

      assert pod.slug == "original-name"

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{name: "New Name"}, actor: user)
        |> Ash.update(domain: Pods)

      assert updated.slug == "new-name"
    end

    test "updating pod description does not change slug" do
      user = create_user!()
      pod = create_user_pod!(user, "My Pod")

      original_slug = pod.slug

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{description: "New description"}, actor: user)
        |> Ash.update(domain: Pods)

      assert updated.slug == original_slug
    end

    test "slug uniqueness enforced per owner_type and owner_id" do
      user = create_user!()
      org = create_org!(user)

      user_pod = create_user_pod!(user, "Shared Name")
      org_pod = create_org_pod!(org, user, "Shared Name")

      assert user_pod.slug == "shared-name"
      assert org_pod.slug == "shared-name"
      assert user_pod.owner_type == :user
      assert org_pod.owner_type == :organization
    end
  end

  describe "Owner Calculation" do
    test "owner calculation returns correct user data for user-owned pods" do
      user = create_user!("bob@test.com", "bobuser", "password123")
      pod = create_user_pod!(user, "Bob's Pod")

      pod = reload!(pod, [:owner])
      assert pod.owner.id == user.id
      assert to_string(pod.owner.email) == "bob@test.com"
      assert pod.owner.username == "bobuser"
    end

    test "owner calculation returns correct org data for org-owned pods" do
      owner = create_user!()
      org = create_org!(owner, %{name: "Acme Corporation"})
      pod = create_org_pod!(org, owner, "Acme Pod")

      pod = reload!(pod, [:owner])
      assert pod.owner.id == org.id
      assert pod.owner.name == "Acme Corporation"
      assert pod.owner.slug == "acme-corporation"
    end
  end

  describe "FullPath Calculation" do
    test "full_path updates when pod name changes" do
      user = create_user!("charlie@test.com", "charlie123", "password123")
      pod = create_user_pod!(user, "Original")

      pod = reload!(pod, [:full_path])
      assert pod.full_path == "@charlie123/original"

      {:ok, updated} =
        pod
        |> Ash.Changeset.for_update(:update, %{name: "Updated"}, actor: user)
        |> Ash.update(domain: Pods)

      updated = reload!(updated, [:full_path])
      assert updated.full_path == "@charlie123/updated"
    end

    test "full_path is correct for org-owned pod" do
      owner = create_user!()
      org = create_org_with_slug!(owner, "tech-startup")
      pod = create_org_pod!(org, owner, "Product One")

      pod = reload!(pod, [:full_path])
      assert pod.full_path == "@tech-startup/product-one"
    end
  end
end
