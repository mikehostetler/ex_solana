defmodule JidoHub.Integration.PodMembershipTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods

  describe "pod membership management for user-owned pods" do
    test "pod owner can add member to user-owned pod" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert membership.pod_id == pod.id
      assert membership.user_id == member.id
      assert membership.role == :member
      assert membership.joined_at
    end

    test "pod owner can add admin to user-owned pod" do
      owner = create_user!()
      admin = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: admin.id, role: :admin},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert membership.role == :admin
    end

    test "pod owner can update member role" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, updated} =
        membership
        |> Ash.Changeset.for_update(:update, %{role: :admin}, actor: owner)
        |> Ash.update(domain: Pods)

      assert updated.role == :admin
    end

    test "pod owner can remove member" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      :ok =
        membership
        |> Ash.Changeset.for_destroy(:destroy, %{}, actor: owner)
        |> Ash.destroy(domain: Pods)

      assert {:error, %Ash.Error.Invalid{}} =
               Pods.PodMembership
               |> Ash.get(membership.id, domain: Pods, actor: owner)
    end

    test "member cannot add other members" do
      owner = create_user!()
      member = create_user!()
      other = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, _membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} =
               Pods.PodMembership
               |> Ash.Changeset.for_create(
                 :create,
                 %{pod_id: pod.id, user_id: other.id, role: :member},
                 actor: member
               )
               |> Ash.create(domain: Pods)
    end

    test "member cannot update other members" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, _membership1} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership2
               |> Ash.Changeset.for_update(:update, %{role: :admin}, actor: member1)
               |> Ash.update(domain: Pods)
    end

    test "member cannot remove other members" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, _membership1} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership2
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: member1)
               |> Ash.destroy(domain: Pods)
    end

    test "non-member cannot add members" do
      owner = create_user!()
      non_member = create_user!()
      other = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      assert {:error, %Ash.Error.Forbidden{}} =
               Pods.PodMembership
               |> Ash.Changeset.for_create(
                 :create,
                 %{pod_id: pod.id, user_id: other.id, role: :member},
                 actor: non_member
               )
               |> Ash.create(domain: Pods)
    end

    test "non-member cannot update memberships" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_update(:update, %{role: :admin}, actor: non_member)
               |> Ash.update(domain: Pods)
    end

    test "non-member cannot remove members" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} =
               membership
               |> Ash.Changeset.for_destroy(:destroy, %{}, actor: non_member)
               |> Ash.destroy(domain: Pods)
    end
  end

  describe "pod membership access" do
    test "member can read their own membership" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, fetched} =
        Pods.PodMembership
        |> Ash.get(membership.id, domain: Pods, actor: member)

      assert fetched.id == membership.id
      assert fetched.user_id == member.id
    end

    test "pod owner can read specific memberships" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      # Pod owner can read specific membership by loading from pod
      reloaded_pod = reload!(pod, [:pod_memberships])
      assert length(reloaded_pod.pod_memberships) == 1
      assert hd(reloaded_pod.pod_memberships).id == membership.id
    end

    test "non-member cannot read other memberships" do
      owner = create_user!()
      member = create_user!()
      non_member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, _membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      # Non-member cannot see memberships when reading (filtered out)
      memberships =
        Pods.PodMembership
        |> Ash.read!(domain: Pods, actor: non_member)

      assert memberships == []
    end
  end

  describe "pod membership restrictions for org-owned pods" do
    test "cannot create pod membership for org-owned pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner, "Org Pod")

      result =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, error} = result

      assert error.errors
             |> Enum.any?(fn e ->
               message = e.message || ""
               String.contains?(message, "Organization-owned pods use Organization memberships")
             end)
    end

    test "attempting pod membership for org-owned pod fails authorization" do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      pod = create_org_pod!(org, owner, "Org Pod")

      result1 =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: admin.id, role: :admin},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, error1} = result1

      assert error1.errors
             |> Enum.any?(fn e ->
               message = e.message || ""
               String.contains?(message, "Organization-owned pods use Organization memberships")
             end)

      result2 =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: admin
        )
        |> Ash.create(domain: Pods)

      assert {:error, error2} = result2

      assert error2.errors
             |> Enum.any?(fn e ->
               message = e.message || ""
               String.contains?(message, "Organization-owned pods use Organization memberships")
             end)
    end
  end

  describe "pod membership uniqueness" do
    test "cannot add same user twice to same pod" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Test Pod")

      {:ok, _membership} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Invalid{}} =
               Pods.PodMembership
               |> Ash.Changeset.for_create(
                 :create,
                 %{pod_id: pod.id, user_id: member.id, role: :admin},
                 actor: owner
               )
               |> Ash.create(domain: Pods)
    end

    test "same user can be member of different pods" do
      owner1 = create_user!()
      owner2 = create_user!()
      member = create_user!()
      pod1 = create_user_pod!(owner1, "Pod 1")
      pod2 = create_user_pod!(owner2, "Pod 2")

      {:ok, membership1} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod1.id, user_id: member.id, role: :member},
          actor: owner1
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        Pods.PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod2.id, user_id: member.id, role: :admin},
          actor: owner2
        )
        |> Ash.create(domain: Pods)

      assert membership1.pod_id == pod1.id
      assert membership1.user_id == member.id
      assert membership1.role == :member

      assert membership2.pod_id == pod2.id
      assert membership2.user_id == member.id
      assert membership2.role == :admin
    end
  end
end
