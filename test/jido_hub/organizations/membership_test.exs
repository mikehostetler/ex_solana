defmodule JidoHub.Organizations.MembershipTest do
  use JidoHub.DataCase

  import JidoHub.Fixtures

  alias JidoHub.Organizations.Membership

  describe "create/2" do
    test "creates membership with valid attributes" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)

      {:ok, membership} =
        Membership
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:user_id, member.id)
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.for_create(:create, %{role: :member})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert membership.user_id == member.id
      assert membership.organization_id == organization.id
      assert membership.role == :member
      assert membership.joined_at
    end

    test "defaults role to member" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)

      {:ok, membership} =
        Membership
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:user_id, member.id)
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.for_create(:create, %{})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert membership.role == :member
    end

    test "validates role is valid" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :invalid_role})
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
      assert Enum.any?(errors, &(&1.field == :role))
    end

    test "enforces unique user-organization constraint" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)

      {:ok, _membership1} =
        Membership
        |> Ash.Changeset.new()
        |> Ash.Changeset.set_argument(:user_id, member.id)
        |> Ash.Changeset.set_argument(:organization_id, organization.id)
        |> Ash.Changeset.for_create(:create, %{role: :member})
        |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :admin})
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      refute Enum.empty?(errors)
    end
  end

  describe "update_role/2" do
    test "updates membership role" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)
      membership = create_membership!(organization, member, :member)

      {:ok, updated} =
        membership
        |> Ash.Changeset.for_update(:update_role, %{role: :admin})
        |> Ash.update(domain: JidoHub.Organizations, actor: owner)

      assert updated.role == :admin
    end
  end

  describe "role transitions" do
    test "supports role changes between member and admin" do
      owner = create_user!()
      organization = create_organization!(owner)

      for {from_role, to_role, description} <- [
            {:member, :admin, "promote member to admin"},
            {:admin, :member, "demote admin to member"}
          ] do
        user = create_user!()
        membership = create_membership!(organization, user, from_role)

        {:ok, updated} =
          membership
          |> Ash.Changeset.for_update(:update_role, %{role: to_role})
          |> Ash.update(domain: JidoHub.Organizations, actor: owner)

        assert updated.role == to_role, "failed to #{description}"
      end
    end
  end

  describe "authorization - read" do
    test "members and owner can read, non-members cannot" do
      owner = create_user!()
      member1 = create_user!()
      member2 = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      membership = create_membership!(organization, member1, :member)
      _other_membership = create_membership!(organization, member2, :member)

      for {actor, description, expected} <- [
            {member1, "member reading own membership", :ok},
            {owner, "owner reading membership", :ok},
            {member2, "other member reading membership", :ok},
            {non_member, "non-member", :error}
          ] do
        result =
          Ash.get(Membership, membership.id,
            domain: JidoHub.Organizations,
            actor: actor
          )

        case expected do
          :ok ->
            assert {:ok, fetched} = result, "#{description} should succeed"
            assert fetched.id == membership.id

          :error ->
            assert {:error, %Ash.Error.Invalid{}} = result, "#{description} should fail"
        end
      end
    end
  end

  describe "authorization - create" do
    test "org owner can create memberships" do
      owner = create_user!()
      organization = create_organization!(owner)
      new_member = create_user!()

      assert {:ok, membership} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, new_member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :member})
               |> Ash.create(domain: JidoHub.Organizations, actor: owner)

      assert membership.user_id == new_member.id
      assert membership.organization_id == organization.id
    end

    test "org admin can create memberships" do
      owner = create_user!()
      admin = create_user!()
      organization = create_organization!(owner)
      _admin_membership = create_membership!(organization, admin, :admin)
      new_member = create_user!()

      assert {:ok, membership} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, new_member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :member})
               |> Ash.create(domain: JidoHub.Organizations, actor: admin)

      assert membership.user_id == new_member.id
      assert membership.organization_id == organization.id
    end

    test "org member cannot create memberships" do
      owner = create_user!()
      member = create_user!()
      organization = create_organization!(owner)
      _member_membership = create_membership!(organization, member, :member)
      new_member = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, new_member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :member})
               |> Ash.create(domain: JidoHub.Organizations, actor: member)
    end

    test "non-member cannot create memberships" do
      owner = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      new_member = create_user!()

      assert {:error, %Ash.Error.Forbidden{}} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, new_member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create, %{role: :member})
               |> Ash.create(domain: JidoHub.Organizations, actor: non_member)
    end
  end

  describe "authorization - update" do
    test "owner and admins can update, members and non-members cannot" do
      owner = create_user!()
      admin = create_user!()
      regular_member = create_user!()
      target_member = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      _admin_membership = create_membership!(organization, admin, :admin)
      _regular_membership = create_membership!(organization, regular_member, :member)
      target_membership = create_membership!(organization, target_member, :member)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {admin, "admin", :ok},
            {regular_member, "regular member", :forbidden},
            {non_member, "non-member", :forbidden}
          ] do
        result =
          target_membership
          |> Ash.Changeset.for_update(:update_role, %{role: :admin})
          |> Ash.update(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert {:ok, updated} = result, "#{description} should update role"
            assert updated.role == :admin

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not update role"
        end

        _target_membership = reload!(target_membership)
      end
    end
  end

  describe "authorization - destroy" do
    test "owner and admins can remove, members and non-members cannot" do
      owner = create_user!()
      admin = create_user!()
      regular_member = create_user!()
      non_member = create_user!()
      organization = create_organization!(owner)
      _admin_membership = create_membership!(organization, admin, :admin)
      _regular_membership = create_membership!(organization, regular_member, :member)

      for {actor, description, expected} <- [
            {owner, "owner", :ok},
            {admin, "admin", :ok},
            {regular_member, "regular member", :forbidden},
            {non_member, "non-member", :forbidden}
          ] do
        target_user = create_user!()
        membership = create_membership!(organization, target_user, :member)

        result =
          membership
          |> Ash.Changeset.for_destroy(:destroy)
          |> Ash.destroy(domain: JidoHub.Organizations, actor: actor)

        case expected do
          :ok ->
            assert :ok = result, "#{description} should remove membership"

          :forbidden ->
            assert {:error, %Ash.Error.Forbidden{}} = result,
                   "#{description} should not remove membership"
        end
      end
    end
  end

  describe "invitation acceptance via bypassed action" do
    test "create_via_invite bypasses authorization" do
      owner = create_user!()
      organization = create_organization!(owner)
      new_member = create_user!()

      # This should succeed even without an actor since it uses the bypassed action
      assert {:ok, membership} =
               Membership
               |> Ash.Changeset.new()
               |> Ash.Changeset.set_argument(:user_id, new_member.id)
               |> Ash.Changeset.set_argument(:organization_id, organization.id)
               |> Ash.Changeset.for_create(:create_via_invite, %{role: :member})
               |> Ash.create(domain: JidoHub.Organizations, authorize?: false)

      assert membership.user_id == new_member.id
      assert membership.organization_id == organization.id
      assert membership.role == :member
    end
  end
end
