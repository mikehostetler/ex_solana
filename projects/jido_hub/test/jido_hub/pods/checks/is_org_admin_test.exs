defmodule JidoHub.Pods.Pod.Checks.IsOrgAdminTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods.Pod.Checks.IsOrgAdmin

  describe "describe/1" do
    test "returns the check description" do
      assert IsOrgAdmin.describe([]) == "User is admin or owner of the pod's organization"
    end
  end

  describe "match?/3 with organization direct owner" do
    test "allows organization direct owner via changeset" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      assert IsOrgAdmin.match?(owner, context, [])
    end

    test "allows organization direct owner via resource" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      context = %{resource: pod}

      assert IsOrgAdmin.match?(owner, context, [])
    end
  end

  describe "match?/3 with organization admin member" do
    test "allows organization admin via changeset" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      assert IsOrgAdmin.match?(admin, context, [])
    end

    test "allows organization admin via resource" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      context = %{resource: pod}

      assert IsOrgAdmin.match?(admin, context, [])
    end
  end

  describe "match?/3 with organization owner member" do
    test "allows organization owner role member via changeset" do
      direct_owner = create_user!()
      owner_member = create_user!()
      org = create_org!(direct_owner)
      add_membership!(org, owner_member, :owner)
      pod = create_org_pod!(org, direct_owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      assert IsOrgAdmin.match?(owner_member, context, [])
    end

    test "allows organization owner role member via resource" do
      direct_owner = create_user!()
      owner_member = create_user!()
      org = create_org!(direct_owner)
      add_membership!(org, owner_member, :owner)
      pod = create_org_pod!(org, direct_owner)

      pod = reload!(pod)
      context = %{resource: pod}

      assert IsOrgAdmin.match?(owner_member, context, [])
    end
  end

  describe "match?/3 with organization regular member" do
    test "denies organization member via changeset" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      refute IsOrgAdmin.match?(member, context, [])
    end

    test "denies organization member via resource" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      context = %{resource: pod}

      refute IsOrgAdmin.match?(member, context, [])
    end
  end

  describe "match?/3 with non-member" do
    test "denies non-member via changeset" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      refute IsOrgAdmin.match?(non_member, context, [])
    end

    test "denies non-member via resource" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      context = %{resource: pod}

      refute IsOrgAdmin.match?(non_member, context, [])
    end
  end

  describe "match?/3 with user-owned pod" do
    test "denies for user-owned pod via changeset" do
      user = create_user!()
      pod = create_user_pod!(user)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      refute IsOrgAdmin.match?(user, context, [])
    end

    test "denies for user-owned pod via resource" do
      user = create_user!()
      pod = create_user_pod!(user)

      pod = reload!(pod)
      context = %{resource: pod}

      refute IsOrgAdmin.match?(user, context, [])
    end
  end

  describe "match?/3 with nil actor" do
    test "denies nil actor via changeset" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      changeset = Ash.Changeset.for_update(pod, :update, %{name: "Updated"})
      context = %{changeset: changeset}

      refute IsOrgAdmin.match?(nil, context, [])
    end

    test "denies nil actor via resource" do
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      context = %{resource: pod}

      refute IsOrgAdmin.match?(nil, context, [])
    end
  end

  describe "match?/3 with non-existent organization" do
    test "denies when organization does not exist" do
      user = create_user!()
      owner = create_user!()
      org = create_org!(owner)
      pod = create_org_pod!(org, owner)

      pod = reload!(pod)
      pod = %{pod | owner_id: Ash.UUID.generate()}

      context = %{resource: pod}
      refute IsOrgAdmin.match?(user, context, [])
    end
  end

  describe "match?/3 with empty context" do
    test "denies with empty context" do
      user = create_user!()
      refute IsOrgAdmin.match?(user, %{}, [])
    end
  end

  describe "match?/3 decision matrix" do
    setup do
      direct_owner = create_user!()
      admin = create_user!()
      owner_member = create_user!()
      member = create_user!()
      non_member = create_user!()

      org = create_org!(direct_owner)
      add_membership!(org, admin, :admin)
      add_membership!(org, owner_member, :owner)
      add_membership!(org, member, :member)

      pod = create_org_pod!(org, direct_owner)
      pod = reload!(pod)

      %{
        direct_owner: direct_owner,
        admin: admin,
        owner_member: owner_member,
        member: member,
        non_member: non_member,
        pod: pod
      }
    end

    test "direct org owner -> allow", %{direct_owner: direct_owner, pod: pod} do
      context = %{resource: pod}
      assert IsOrgAdmin.match?(direct_owner, context, [])
    end

    test "admin member -> allow", %{admin: admin, pod: pod} do
      context = %{resource: pod}
      assert IsOrgAdmin.match?(admin, context, [])
    end

    test "owner role member -> allow", %{owner_member: owner_member, pod: pod} do
      context = %{resource: pod}
      assert IsOrgAdmin.match?(owner_member, context, [])
    end

    test "regular member -> forbid", %{member: member, pod: pod} do
      context = %{resource: pod}
      refute IsOrgAdmin.match?(member, context, [])
    end

    test "non-member -> forbid", %{non_member: non_member, pod: pod} do
      context = %{resource: pod}
      refute IsOrgAdmin.match?(non_member, context, [])
    end

    test "nil actor -> forbid", %{pod: pod} do
      context = %{resource: pod}
      refute IsOrgAdmin.match?(nil, context, [])
    end
  end

  describe "match?/3 with multiple organizations" do
    test "admin of different organization is denied" do
      owner1 = create_user!()
      owner2 = create_user!()
      admin2 = create_user!()

      org1 = create_org!(owner1)
      org2 = create_org!(owner2)
      add_membership!(org2, admin2, :admin)

      pod1 = create_org_pod!(org1, owner1)
      pod1 = reload!(pod1)

      context = %{resource: pod1}
      refute IsOrgAdmin.match?(admin2, context, [])
    end
  end
end
