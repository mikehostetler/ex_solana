defmodule JidoHub.Organizations.Membership.Checks.ActorIsAdminOrOwnerTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Organizations.Membership.Checks.ActorIsAdminOrOwner

  describe "describe/1" do
    test "returns the check description" do
      assert ActorIsAdminOrOwner.describe([]) == "actor is an admin or owner in the organization"
    end
  end

  describe "match?/3 with organization owner" do
    test "allows organization owner to match" do
      owner = create_user!()
      org = create_org!(owner)
      add_membership!(org, owner, :owner)
      member = create_user!()

      membership = add_membership!(org, member, :member)

      context = %{data: membership}
      assert ActorIsAdminOrOwner.match?(owner, context, [])
    end
  end

  describe "match?/3 with organization admin" do
    test "allows organization admin to match" do
      owner = create_user!()
      admin = create_user!()
      org = create_org!(owner)
      add_membership!(org, admin, :admin)

      target_member = create_user!()
      membership = add_membership!(org, target_member, :member)

      context = %{data: membership}
      assert ActorIsAdminOrOwner.match?(admin, context, [])
    end
  end

  describe "match?/3 with organization member" do
    test "denies regular member" do
      owner = create_user!()
      member = create_user!()
      org = create_org!(owner)
      add_membership!(org, member, :member)

      target_member = create_user!()
      membership = add_membership!(org, target_member, :member)

      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(member, context, [])
    end
  end

  describe "match?/3 with non-member" do
    test "denies user not in organization" do
      owner = create_user!()
      non_member = create_user!()
      org = create_org!(owner)

      target_member = create_user!()
      membership = add_membership!(org, target_member, :member)

      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(non_member, context, [])
    end
  end

  describe "match?/3 with nil actor" do
    test "denies nil actor" do
      owner = create_user!()
      org = create_org!(owner)
      member = create_user!()
      membership = add_membership!(org, member, :member)

      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(nil, context, [])
    end
  end

  describe "match?/3 with nil membership" do
    test "denies when membership data is nil" do
      actor = create_user!()
      context = %{data: nil}
      refute ActorIsAdminOrOwner.match?(actor, context, [])
    end
  end

  describe "match?/3 with nil organization_id" do
    test "denies when membership has nil organization_id" do
      actor = create_user!()
      membership = %{organization_id: nil}
      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(actor, context, [])
    end
  end

  describe "match?/3 with empty context" do
    test "denies with empty context" do
      actor = create_user!()
      refute ActorIsAdminOrOwner.match?(actor, %{}, [])
    end
  end

  describe "match?/3 decision matrix" do
    setup do
      owner = create_user!()
      admin = create_user!()
      member = create_user!()
      non_member = create_user!()

      org = create_org!(owner)
      add_membership!(org, owner, :owner)
      add_membership!(org, admin, :admin)
      add_membership!(org, member, :member)

      target_member = create_user!()
      membership = add_membership!(org, target_member, :member)

      %{
        owner: owner,
        admin: admin,
        member: member,
        non_member: non_member,
        membership: membership
      }
    end

    test "owner in org -> allow", %{owner: owner, membership: membership} do
      context = %{data: membership}
      assert ActorIsAdminOrOwner.match?(owner, context, [])
    end

    test "admin in org -> allow", %{admin: admin, membership: membership} do
      context = %{data: membership}
      assert ActorIsAdminOrOwner.match?(admin, context, [])
    end

    test "member in org -> forbid", %{member: member, membership: membership} do
      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(member, context, [])
    end

    test "non-member -> forbid", %{non_member: non_member, membership: membership} do
      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(non_member, context, [])
    end

    test "nil actor -> forbid", %{membership: membership} do
      context = %{data: membership}
      refute ActorIsAdminOrOwner.match?(nil, context, [])
    end
  end

  describe "match?/3 with multiple organizations" do
    test "owner of different organization is denied" do
      owner1 = create_user!()
      owner2 = create_user!()
      org1 = create_org!(owner1)
      _org2 = create_org!(owner2)

      target_member = create_user!()
      membership_org1 = add_membership!(org1, target_member, :member)

      context = %{data: membership_org1}
      refute ActorIsAdminOrOwner.match?(owner2, context, [])
    end

    test "admin of different organization is denied" do
      owner1 = create_user!()
      owner2 = create_user!()
      admin2 = create_user!()

      org1 = create_org!(owner1)
      org2 = create_org!(owner2)
      add_membership!(org2, admin2, :admin)

      target_member = create_user!()
      membership_org1 = add_membership!(org1, target_member, :member)

      context = %{data: membership_org1}
      refute ActorIsAdminOrOwner.match?(admin2, context, [])
    end
  end
end
