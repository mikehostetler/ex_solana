defmodule JidoHub.Pods.PodAuthorizationTest do
  @moduledoc """
  Comprehensive authorization tests for Pod read policies, ensuring proper tenant isolation.
  """
  use JidoHub.DataCase, async: false

  alias JidoHub.Accounts.User
  alias JidoHub.Organizations.{Organization, Membership}
  alias JidoHub.Pods.Pod
  alias JidoHub.Pods.PodMembership

  describe "public pod visibility" do
    test "unauthenticated users can read public pods" do
      user = create_user!()
      pod = create_pod!(user, :user, visibility: :public)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: nil, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "authenticated users can read any public pod" do
      owner = create_user!()
      reader = create_user!()
      pod = create_pod!(owner, :user, visibility: :public)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: reader, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "public org pods are readable by non-members" do
      org = create_org!()
      non_member = create_user!()
      pod = create_pod!(org, :organization, visibility: :public)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: non_member, authorize?: true)
      assert found_pod.id == pod.id
    end
  end

  describe "private user pod authorization" do
    test "owner can read their own private pod" do
      user = create_user!()
      pod = create_pod!(user, :user, visibility: :private)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: user, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "non-owner cannot read another user's private pod" do
      owner = create_user!()
      other_user = create_user!()
      _pod = create_pod!(owner, :user, visibility: :private)

      assert {:ok, []} =
               Ash.read(Pod, actor: other_user, authorize?: true, domain: JidoHub.Pods)
    end

    test "unauthenticated user cannot read private pod" do
      user = create_user!()
      _pod = create_pod!(user, :user, visibility: :private)

      assert {:ok, []} = Ash.read(Pod, actor: nil, authorize?: true)
    end

    test "pod member can read private user pod via membership" do
      owner = create_user!()
      member = create_user!()
      pod = create_pod!(owner, :user, visibility: :private)

      create_pod_membership!(pod, member)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: member, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "removing pod membership revokes read access" do
      owner = create_user!()
      member = create_user!()
      pod = create_pod!(owner, :user, visibility: :private)

      membership = create_pod_membership!(pod, member)
      assert {:ok, pods_before} = Ash.read(Pod, actor: member, authorize?: true)
      assert length(pods_before) == 1

      Ash.destroy!(membership, domain: JidoHub.Pods, authorize?: false)
      assert {:ok, []} = Ash.read(Pod, actor: member, authorize?: true)
    end
  end

  describe "private organization pod authorization" do
    test "org member can read org-owned private pod" do
      org = create_org!()
      member = create_user!()
      create_org_membership!(org, member)

      pod = create_pod!(org, :organization, visibility: :private)

      assert {:ok, [found_pod]} = Ash.read(Pod, actor: member, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "non-org-member cannot read org-owned private pod" do
      org = create_org!()
      non_member = create_user!()
      _pod = create_pod!(org, :organization, visibility: :private)

      assert {:ok, []} = Ash.read(Pod, actor: non_member, authorize?: true)
    end

    test "removing org membership revokes pod read access" do
      org = create_org!()
      member = create_user!()
      membership = create_org_membership!(org, member)
      _pod = create_pod!(org, :organization, visibility: :private)

      assert {:ok, [_]} = Ash.read(Pod, actor: member, authorize?: true)

      Ash.destroy!(membership, domain: JidoHub.Organizations, authorize?: false)
      assert {:ok, []} = Ash.read(Pod, actor: member, authorize?: true)
    end
  end

  describe "mixed visibility scenarios" do
    test "user can see only their own pods and public pods" do
      user1 = create_user!()
      user2 = create_user!()

      pod1_private = create_pod!(user1, :user, visibility: :private)
      _pod2_private = create_pod!(user2, :user, visibility: :private)
      pod2_public = create_pod!(user2, :user, visibility: :public)

      {:ok, visible_pods} = Ash.read(Pod, actor: user1, authorize?: true)
      pod_ids = Enum.map(visible_pods, & &1.id)

      assert pod1_private.id in pod_ids
      assert pod2_public.id in pod_ids
      refute _pod2_private.id in pod_ids
    end

    test "org member sees org pods, their own pods, and public pods" do
      org = create_org!()
      member = create_user!()
      other_user = create_user!()
      create_org_membership!(org, member)

      member_pod = create_pod!(member, :user, visibility: :private)
      org_pod = create_pod!(org, :organization, visibility: :private)
      _other_private = create_pod!(other_user, :user, visibility: :private)
      other_public = create_pod!(other_user, :user, visibility: :public)

      {:ok, visible_pods} = Ash.read(Pod, actor: member, authorize?: true)
      pod_ids = Enum.map(visible_pods, & &1.id)

      assert member_pod.id in pod_ids
      assert org_pod.id in pod_ids
      assert other_public.id in pod_ids
      refute _other_private.id in pod_ids
    end
  end

  describe "by_slug action authorization" do
    test "can read public pod by slug without authentication" do
      user = create_user!()
      pod = create_pod!(user, :user, visibility: :public, name: "test-pod")

      query =
        Pod
        |> Ash.Query.for_read(:by_slug, %{
          owner_type: :user,
          owner_id: user.id,
          slug: pod.slug
        })

      assert {:ok, [found_pod]} = Ash.read(query, actor: nil, authorize?: true)
      assert found_pod.id == pod.id
    end

    test "cannot read private pod by slug without authorization" do
      user = create_user!()
      other = create_user!()
      pod = create_pod!(user, :user, visibility: :private, name: "private-pod")

      query =
        Pod
        |> Ash.Query.for_read(:by_slug, %{
          owner_type: :user,
          owner_id: user.id,
          slug: pod.slug
        })

      assert {:ok, []} = Ash.read(query, actor: other, authorize?: true)
    end

    test "owner can read private pod by slug" do
      user = create_user!()
      pod = create_pod!(user, :user, visibility: :private, name: "my-pod")

      query =
        Pod
        |> Ash.Query.for_read(:by_slug, %{
          owner_type: :user,
          owner_id: user.id,
          slug: pod.slug
        })

      assert {:ok, [found_pod]} = Ash.read(query, actor: user, authorize?: true)
      assert found_pod.id == pod.id
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

  defp create_org!(attrs \\ %{}) do
    owner = create_user!()

    default_attrs = %{
      name: "org-#{System.unique_integer([:positive])}"
    }

    attrs = Map.merge(default_attrs, Map.new(attrs))

    Organization
    |> Ash.Changeset.for_create(:create, attrs, actor: owner)
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
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

  defp create_org_membership!(org, user, role \\ :member) do
    Membership
    |> Ash.Changeset.for_create(:create, %{
      organization_id: org.id,
      user_id: user.id,
      role: role
    })
    |> Ash.create!(domain: JidoHub.Organizations, authorize?: false)
  end

  defp create_pod_membership!(pod, user, role \\ :member) do
    PodMembership
    |> Ash.Changeset.for_create(:create, %{
      pod_id: pod.id,
      user_id: user.id,
      role: role
    })
    |> Ash.create!(domain: JidoHub.Pods, authorize?: false)
  end
end
