defmodule JidoHub.Pods.Pod.Checks.CanCreatePodTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Pods.Pod
  alias JidoHub.Pods.Pod.Checks.CanCreatePod

  describe "describe/1" do
    test "returns the check description" do
      assert CanCreatePod.describe([]) ==
               "User can create pod for themselves or organizations they admin"
    end
  end

  describe "match?/3 with user-owned pod" do
    test "allows user to create pod for themselves" do
      user = create_user!()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :user)
        |> Ash.Changeset.set_argument(:owner_id, user.id)
        |> Ash.Changeset.for_create(:create, %{name: "My Pod"}, actor: user)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(user, context, [])
    end

    test "denies user from creating pod for different user" do
      user = create_user!()
      other_user = create_user!()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :user)
        |> Ash.Changeset.set_argument(:owner_id, other_user.id)
        |> Ash.Changeset.for_create(:create, %{name: "Other Pod"}, actor: user)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(user, context, [])
    end
  end

  describe "match?/3 with organization-owned pod (direct owner)" do
    test "allows organization direct owner to create pod" do
      user = create_user!()
      org = create_org!(user)

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Org Pod"}, actor: user)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(user, context, [])
    end
  end

  describe "match?/3 with organization-owned pod (admin via membership)" do
    test "allows organization admin to create pod" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Admin Pod"}, actor: admin)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(admin, context, [])
    end

    test "allows organization owner role member to create pod" do
      direct_owner = create_user!()
      owner_member = create_user!()
      org = create_org!(direct_owner)
      add_membership!(org, owner_member, :owner)

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Owner Pod"}, actor: owner_member)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(owner_member, context, [])
    end
  end

  describe "match?/3 with organization-owned pod (non-admin member)" do
    test "denies regular member from creating pod" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Member Pod"}, actor: member)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(member, context, [])
    end
  end

  describe "match?/3 with organization-owned pod (non-member)" do
    test "denies non-member from creating pod" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Non-member Pod"}, actor: non_member)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(non_member, context, [])
    end
  end

  describe "match?/3 with invalid owner_type" do
    test "denies with nil owner_type" do
      user = create_user!()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, nil)
        |> Ash.Changeset.set_argument(:owner_id, user.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: user)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(user, context, [])
    end

    test "denies with invalid owner_type" do
      user = create_user!()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :invalid)
        |> Ash.Changeset.set_argument(:owner_id, user.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: user)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(user, context, [])
    end
  end

  describe "match?/3 with non-existent organization" do
    test "denies with invalid organization id" do
      user = create_user!()
      fake_org_id = Ash.UUID.generate()

      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, fake_org_id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: user)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(user, context, [])
    end
  end

  describe "match?/3 with empty context" do
    test "denies with empty context" do
      user = create_user!()
      refute CanCreatePod.match?(user, %{}, [])
    end
  end

  describe "match?/3 decision matrix" do
    setup do
      user = create_user!()
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      non_member = create_user!()

      org = create_org!(owner)
      add_membership!(org, admin, :admin)
      add_membership!(org, member, :member)

      %{
        user: user,
        owner: owner,
        admin: admin,
        member: member,
        non_member: non_member,
        org: org
      }
    end

    test "user creates for self -> allow", %{user: user} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :user)
        |> Ash.Changeset.set_argument(:owner_id, user.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: user)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(user, context, [])
    end

    test "user creates for other user -> forbid", %{user: user, owner: owner} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :user)
        |> Ash.Changeset.set_argument(:owner_id, owner.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: user)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(user, context, [])
    end

    test "direct org owner creates for org -> allow", %{owner: owner, org: org} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: owner)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(owner, context, [])
    end

    test "org admin creates for org -> allow", %{admin: admin, org: org} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: admin)

      context = %{changeset: changeset}
      assert CanCreatePod.match?(admin, context, [])
    end

    test "org member creates for org -> forbid", %{member: member, org: org} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: member)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(member, context, [])
    end

    test "non-member creates for org -> forbid", %{non_member: non_member, org: org} do
      changeset =
        Pod
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:owner_type, :organization)
        |> Ash.Changeset.set_argument(:owner_id, org.id)
        |> Ash.Changeset.for_create(:create, %{name: "Pod"}, actor: non_member)

      context = %{changeset: changeset}
      refute CanCreatePod.match?(non_member, context, [])
    end
  end
end
