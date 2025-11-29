defmodule JidoHub.Pods.PodMembershipTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods
  alias JidoHub.Pods.{Pod, PodMembership}

  describe "pod membership" do
    test "membership uniqueness constraint" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      {:ok, _} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{
            pod_id: pod.id,
            user_id: member.id,
            role: :member
          },
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert {:error, error} =
               PodMembership
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   pod_id: pod.id,
                   user_id: member.id,
                   role: :admin
                 },
                 actor: owner
               )
               |> Ash.create(domain: Pods)

      assert error.errors
             |> Enum.any?(fn e ->
               message = e.message || ""

               String.contains?(message, "already exists") ||
                 String.contains?(message, "has already been taken") ||
                 String.contains?(message, "violates unique constraint") ||
                 String.contains?(message, "UNIQUE constraint")
             end)
    end

    test "org pods don't use pod memberships" do
      owner = create_user!()
      org = create_org!(owner)

      {:ok, org_pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Org Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: owner
        )
        |> Ash.create(domain: Pods)

      loaded = Ash.load!(org_pod, :pod_memberships, domain: Pods)
      assert loaded.pod_memberships == []
    end
  end

  describe "membership authorization" do
    test "owner can add members, non-owner cannot" do
      owner = create_user!()
      member = create_user!()
      non_owner = create_user!()
      another_member = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      creation_cases = [
        %{
          description: "owner can add members",
          actor: owner,
          user_id: member.id,
          should_succeed: true
        },
        %{
          description: "non-owner cannot add members",
          actor: non_owner,
          user_id: another_member.id,
          should_succeed: false
        }
      ]

      for test_case <- creation_cases do
        result =
          PodMembership
          |> Ash.Changeset.for_create(
            :create,
            %{pod_id: pod.id, user_id: test_case.user_id, role: :member},
            actor: test_case.actor
          )
          |> Ash.create(domain: Pods)

        if test_case.should_succeed do
          assert {:ok, membership} = result
          assert membership.pod_id == pod.id
        else
          assert {:error, %Ash.Error.Forbidden{}} = result
        end
      end
    end

    test "owner can change member roles, others cannot" do
      owner = create_user!()
      member = create_user!()
      non_owner = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      {:ok, membership} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      role_change_cases = [
        %{
          description: "owner can change member roles",
          actor: owner,
          params: %{role: :admin},
          should_succeed: true,
          expected_role: :admin
        },
        %{
          description: "non-owner cannot change roles",
          actor: non_owner,
          params: %{role: :owner},
          should_succeed: false
        },
        %{
          description: "member cannot change their own role",
          actor: member,
          params: %{role: :owner},
          should_succeed: false
        }
      ]

      membership =
        Enum.reduce(role_change_cases, membership, fn test_case, current_membership ->
          result =
            current_membership
            |> Ash.Changeset.for_update(:update, test_case.params, actor: test_case.actor)
            |> Ash.update(domain: Pods)

          if test_case.should_succeed do
            assert {:ok, updated} = result
            assert updated.role == test_case.expected_role
            updated
          else
            assert {:error, %Ash.Error.Forbidden{}} = result
            current_membership
          end
        end)

      assert membership.role == :admin
    end

    test "owner can remove members, others cannot" do
      owner = create_user!()
      member = create_user!()
      non_owner = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      {:ok, membership} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      removal_cases = [
        %{
          description: "non-owner cannot remove members",
          actor: non_owner,
          should_succeed: false
        },
        %{
          description: "member cannot remove themselves",
          actor: member,
          should_succeed: false
        },
        %{
          description: "owner can remove members",
          actor: owner,
          should_succeed: true
        }
      ]

      for test_case <- removal_cases do
        result =
          membership
          |> Ash.Changeset.for_destroy(:destroy, %{}, actor: test_case.actor)
          |> Ash.destroy(domain: Pods)

        if test_case.should_succeed do
          assert :ok = result
        else
          assert {:error, %Ash.Error.Forbidden{}} = result
        end
      end
    end
  end

  describe "membership visibility" do
    test "visibility matrix for pod memberships" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      outsider = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      {:ok, membership1} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      visibility_cases = [
        %{
          actor: member1,
          description: "member can read their own membership",
          can_see: [membership1.id],
          cannot_see: []
        },
        %{
          actor: member2,
          description: "member can read their own membership",
          can_see: [membership2.id],
          cannot_see: []
        },
        %{
          actor: outsider,
          description: "outsider cannot read any memberships",
          can_see: [],
          cannot_see: [membership1.id, membership2.id]
        }
      ]

      for test_case <- visibility_cases do
        {:ok, visible_memberships} =
          PodMembership
          |> Ash.read(domain: Pods, actor: test_case.actor)

        visible_ids = Enum.map(visible_memberships, & &1.id)

        for membership_id <- test_case.can_see do
          assert membership_id in visible_ids
        end

        for membership_id <- test_case.cannot_see do
          result = Ash.get(PodMembership, membership_id, domain: Pods, actor: test_case.actor)
          assert {:error, %Ash.Error.Invalid{}} = result

          assert result
                 |> elem(1)
                 |> Map.get(:errors)
                 |> Enum.any?(fn e -> match?(%Ash.Error.Query.NotFound{}, e) end)
        end
      end
    end

    test "members across different pods only see their own memberships" do
      user1 = create_user!()
      user2 = create_user!()
      member = create_user!()

      pod1 = create_user_pod!(user1, "User1 Pod")
      pod2 = create_user_pod!(user2, "User2 Pod")

      {:ok, membership1} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod1.id, user_id: member.id, role: :member},
          actor: user1
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod2.id, user_id: member.id, role: :member},
          actor: user2
        )
        |> Ash.create(domain: Pods)

      {:ok, memberships} =
        PodMembership
        |> Ash.read(domain: Pods, actor: member)

      membership_ids = Enum.map(memberships, & &1.id)
      assert length(memberships) == 2
      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
    end
  end

  describe "role management" do
    test "default role is member" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      {:ok, membership} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert membership.role == :member
    end

    test "can create membership with owner role" do
      owner = create_user!()
      co_owner = create_user!()
      pod = create_user_pod!(owner, "Shared Pod")

      {:ok, membership} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: co_owner.id, role: :owner},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert membership.role == :owner
    end
  end

  describe "query scoping" do
    test "owner can manage memberships in their pod" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()

      pod = create_user_pod!(owner, "Owner Pod")

      {:ok, membership1} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      assert membership1.pod_id == pod.id
      assert membership2.pod_id == pod.id
      assert membership1.user_id == member1.id
      assert membership2.user_id == member2.id
    end
  end

  describe "timestamps" do
    test "joined_at is set on creation" do
      owner = create_user!()
      member = create_user!()
      pod = create_user_pod!(owner, "Team Pod")

      before = DateTime.utc_now()

      {:ok, membership} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      after_time = DateTime.utc_now()

      assert DateTime.compare(membership.joined_at, before) in [:gt, :eq]
      assert DateTime.compare(membership.joined_at, after_time) in [:lt, :eq]
    end
  end

  describe "Phase 1.1: read authorization security" do
    test "non-owner cannot read other users' pod memberships" do
      user1 = create_user!()
      user2 = create_user!()
      user3 = create_user!()

      pod = create_user_pod!(user1, "User1 Pod")

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: user2.id, role: :member},
          actor: user1
        )
        |> Ash.create(domain: Pods)

      result = Ash.get(PodMembership, membership2.id, domain: Pods, actor: user3)
      assert {:error, %Ash.Error.Invalid{}} = result

      assert result
             |> elem(1)
             |> Map.get(:errors)
             |> Enum.any?(fn e -> match?(%Ash.Error.Query.NotFound{}, e) end)
    end

    test "pod owner can read all memberships for their pod" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()

      pod = create_user_pod!(owner, "Owner Pod")

      {:ok, membership1} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, all_memberships} = PodMembership |> Ash.read(domain: Pods, actor: owner)

      memberships = Enum.filter(all_memberships, &(&1.pod_id == pod.id))
      membership_ids = Enum.map(memberships, & &1.id)
      assert length(memberships) == 2
      assert membership1.id in membership_ids
      assert membership2.id in membership_ids
    end

    test "members can read their own membership only" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()

      pod = create_user_pod!(owner, "Team Pod")

      {:ok, membership1} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member1.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, membership2} =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: member2.id, role: :member},
          actor: owner
        )
        |> Ash.create(domain: Pods)

      {:ok, memberships} = PodMembership |> Ash.read(domain: Pods, actor: member1)
      membership_ids = Enum.map(memberships, & &1.id)

      assert length(memberships) == 1
      assert membership1.id in membership_ids
      refute membership2.id in membership_ids
    end
  end

  describe "Phase 1.1: create authorization security" do
    test "cannot create membership for org-owned pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)

      {:ok, org_pod} =
        Pod
        |> Ash.Changeset.for_create(
          :create,
          %{
            name: "Org Pod",
            owner_type: :organization,
            owner_id: org.id
          },
          actor: owner
        )
        |> Ash.create(domain: Pods)

      result =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: org_pod.id, user_id: member.id, role: :member},
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

    test "only pod owner can add members" do
      user1 = create_user!()
      user2 = create_user!()
      user3 = create_user!()

      pod = create_user_pod!(user1, "User1 Pod")

      result =
        PodMembership
        |> Ash.Changeset.for_create(
          :create,
          %{pod_id: pod.id, user_id: user3.id, role: :member},
          actor: user2
        )
        |> Ash.create(domain: Pods)

      assert {:error, %Ash.Error.Forbidden{}} = result
    end
  end
end
